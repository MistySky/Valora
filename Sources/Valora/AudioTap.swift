import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

/// Core Audio process tap used by the live waveform.
///
/// 1.7.9 evidence: the original ships NSAudioCaptureUsageDescription ("Alcove
/// needs your permission to display the live waveform") and the 1.7.3 changelog
/// added the live waveform. This class captures the rendered mix only, keeps the
/// six bands in memory, writes nothing to disk and stops when disabled.
/// Swift 6 boundary: the singleton is shared with the Core Audio realtime
/// callback and a serial lifecycle queue. `_levels` is lock-guarded; FFT
/// scratch buffers are only touched by the serial lifecycle queue and the
/// device IOProc, which Core Audio stops before teardown.
final class LiveAudioTap: @unchecked Sendable {
    static let shared = LiveAudioTap()

    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var streamFormat: AudioStreamBasicDescription?
    private let lock = NSLock()
    private var _levels = [Float](repeating: 0, count: 6)
    private var _level: Float = 0
    private(set) var running = false

    private let fftSize = 1024
    private let log2n = vDSP_Length(10)
    private var fftSetup: FFTSetup?
    private var window: UnsafeMutablePointer<Float>?
    private var windowed: UnsafeMutablePointer<Float>?
    private var samples: UnsafeMutablePointer<Float>?
    private var splitReal: UnsafeMutablePointer<Float>?
    private var splitImag: UnsafeMutablePointer<Float>?
    private var magnitudes: UnsafeMutablePointer<Float>?
    private var sampleCount = 0
    private var smoothed = [Float](repeating: 0, count: 6)

    var levels: [Float] {
        lock.lock(); defer { lock.unlock() }
        return _levels
    }

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return _level
    }

    var formatDescription: String {
        guard let f = streamFormat else { return "none" }
        return "\(f.mSampleRate)Hz ch=\(f.mChannelsPerFrame) bits=\(f.mBitsPerChannel) flags=\(f.mFormatFlags)"
    }

    private let lifecycle = DispatchQueue(label: "com.wangqing.valora.audio-tap")

    /// Starts the tap off the main thread: HAL IOProc creation can block while
    /// another audio client is configuring its stream, and must not freeze the UI.
    func startAsync(completion: (@MainActor (OSStatus) -> Void)? = nil) {
        lifecycle.async {
            let status = self.start()
            FileHandle.standardError.write(Data("audio-tap async status=\(status) running=\(self.running) format=\(self.formatDescription)\n".utf8))
            if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion(status) } } }
        }
    }

    func stopAsync() {
        lifecycle.async { self.stop() }
    }

    @discardableResult
    func start() -> OSStatus {
        if running { return noErr }
        stop()
        guard allocateFFT() else { return -1 }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = "Valora Live Waveform"

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != 0 else { tapID = 0; releaseFFT(); return status }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { stop(); return status }
        streamFormat = format
        sampleCount = 0

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Valora Tap",
            kAudioAggregateDeviceUIDKey: "com.wangqing.valora.tap." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else { aggregateID = 0; stop(); return status }

        let float32 = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
        let nonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = max(1, Int(format.mChannelsPerFrame))
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if float32 {
                if nonInterleaved, buffers.count > 0 {
                    let first = buffers[0]
                    guard first.mData != nil else { return }
                    let frames = Int(first.mDataByteSize) / 4
                    let pointers = buffers.compactMap { $0.mData?.assumingMemoryBound(to: Float.self) }
                    for frame in 0..<frames {
                        var sum: Float = 0
                        for pointer in pointers where frame < Int(buffers[0].mDataByteSize) / 4 {
                            sum += pointer[frame]
                        }
                        self.append(sum / Float(max(1, pointers.count)))
                    }
                } else if let data = buffers.first?.mData {
                    let pointer = data.assumingMemoryBound(to: Float.self)
                    let frames = Int(buffers[0].mDataByteSize) / 4 / channels
                    for frame in 0..<frames {
                        var sum: Float = 0
                        for channel in 0..<channels { sum += pointer[frame * channels + channel] }
                        self.append(sum / Float(channels))
                    }
                }
            } else if let data = buffers.first?.mData {
                // Fallback for 16-bit sources; the tap normally reports float32.
                let pointer = data.assumingMemoryBound(to: Int16.self)
                let frames = Int(buffers[0].mDataByteSize) / 2 / channels
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += Float(pointer[frame * channels + channel]) / 32768 }
                    self.append(sum / Float(channels))
                }
            }
        }
        guard status == noErr, let ioProcID else { stop(); return status }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { stop(); return status }
        running = true
        return noErr
    }

    func stop() {
        if aggregateID != 0, let ioProcID { AudioDeviceStop(aggregateID, ioProcID) }
        if aggregateID != 0, let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
        ioProcID = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        streamFormat = nil
        running = false
        sampleCount = 0
        smoothed = [Float](repeating: 0, count: 6)
        lock.lock()
        _levels = [Float](repeating: 0, count: 6)
        _level = 0
        lock.unlock()
        releaseFFT()
    }

    deinit { stop() }

    // MARK: - FFT

    private var sampleRate: Double = 48_000

    private func allocateFFT() -> Bool {
        guard fftSetup == nil else { return true }
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return false }
        fftSetup = setup
        window = .allocate(capacity: fftSize)
        windowed = .allocate(capacity: fftSize)
        samples = .allocate(capacity: fftSize)
        splitReal = .allocate(capacity: fftSize / 2)
        splitImag = .allocate(capacity: fftSize / 2)
        magnitudes = .allocate(capacity: fftSize / 2)
        guard let window else { return false }
        vDSP_hann_window(window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        samples?.initialize(repeating: 0, count: fftSize)
        windowed?.initialize(repeating: 0, count: fftSize)
        splitReal?.initialize(repeating: 0, count: fftSize / 2)
        splitImag?.initialize(repeating: 0, count: fftSize / 2)
        magnitudes?.initialize(repeating: 0, count: fftSize / 2)
        return true
    }

    private func releaseFFT() {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
        fftSetup = nil
        window?.deallocate(); window = nil
        windowed?.deallocate(); windowed = nil
        samples?.deallocate(); samples = nil
        splitReal?.deallocate(); splitReal = nil
        splitImag?.deallocate(); splitImag = nil
        magnitudes?.deallocate(); magnitudes = nil
    }

    private func append(_ value: Float) {
        guard let samples else { return }
        samples[sampleCount] = value
        sampleCount += 1
        if sampleCount >= fftSize {
            processFrame()
            sampleCount = 0
        }
    }

    private func processFrame() {
        guard let setup = fftSetup, let window, let windowed, let samples,
              let splitReal, let splitImag, let magnitudes else { return }
        let n = vDSP_Length(fftSize)
        vDSP_vmul(samples, 1, window, 1, windowed, 1, n)
        var split = DSPSplitComplex(realp: splitReal, imagp: splitImag)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { pointer in
            vDSP_ctoz(pointer, 2, &split, 1, n / 2)
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, magnitudes, 1, n / 2)
        var scale = Float(1) / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, n / 2)

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, n)

        let binHz = sampleRate / Double(fftSize)
        let edges = [60.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 12000.0]
        var next = smoothed
        for band in 0..<6 {
            let low = max(1, Int(edges[band] / binHz))
            let high = min(fftSize / 2 - 1, max(low + 1, Int(edges[band + 1] / binHz)))
            var sum: Float = 0
            for index in low..<high { sum += magnitudes[index] }
            let magnitude = sum / Float(max(1, high - low))
            let decibels = 20 * log10(max(1e-7, magnitude))
            let target = min(1, max(0, (decibels + 70) / 60))
            let previous = next[band]
            next[band] = target > previous ? previous + (target - previous) * 0.55
                                              : previous + (target - previous) * 0.15
        }
        smoothed = next
        lock.lock()
        _levels = next
        _level = min(1, rms * 8)
        lock.unlock()
    }
}

enum AudioTapVerification {
    static func run() {
        let tap = LiveAudioTap.shared
        let status = tap.start()
        print("audio-tap status=\(status) running=\(tap.running) format=\(tap.formatDescription)")
        var peak: Float = 0
        var bandPeaks = [Float](repeating: 0, count: 6)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            peak = max(peak, tap.level)
            let levels = tap.levels
            for index in 0..<min(6, levels.count) { bandPeaks[index] = max(bandPeaks[index], levels[index]) }
        }
        print("audio-tap peak=\(peak) levels=\(tap.levels.map { String(format: "%.2f", $0) }.joined(separator: ","))")
        print("audio-tap bandPeaks=\(bandPeaks.map { String(format: "%.2f", $0) }.joined(separator: ","))")
        tap.stop()
        exit(status == noErr ? 0 : 1)
    }
}
