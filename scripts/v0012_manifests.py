#!/usr/bin/env python3
"""V0012 evidence: real QRC, word fill, reading window, 3s budget and bounded cache."""
from pathlib import Path
import hashlib, json, subprocess, datetime

ROOT = Path(__file__).resolve().parents[1]
V11 = ROOT / 'docs/verification/v0011'
V12 = ROOT / 'docs/verification/v0012'
APP = ROOT / 'dist/Valora.app'

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

owned = [
    'Sources/ReferenceCore/LyricsTimeline.swift',
    'Sources/ReferenceCore/QQMusicLyrics.swift',
    'Sources/ReferenceCore/QQMusicQRC.swift',
    'Sources/ReferenceCore/MusicPreferences.swift',
    'Sources/ReferenceCore/NotchGeometry.swift',
    'Sources/ReferenceCore/PresentationMetrics.swift',
    'Sources/ReferenceCore/NotchContour.swift',
    'Sources/Valora/LyricsService.swift',
    'Sources/Valora/LyricsCache.swift',
    'Sources/Valora/LyricsController.swift',
    'Sources/Valora/CompactLyricsView.swift',
    'Sources/Valora/LyricsVerification.swift',
    'Sources/Valora/Models.swift',
    'Sources/Valora/NotchView.swift',
    'Sources/Valora/MarqueeLabel.swift',
    'Sources/Valora/PresentationController.swift',
    'Sources/Valora/SettingsView.swift',
    'Sources/Valora/SettingsLocalization.swift',
    'Sources/Valora/AppDelegate.swift',
    'Sources/Valora/AppRuntimeDefaults.swift',
    'Sources/Valora/Controllers.swift',
    'Sources/Valora/Verification.swift',
    'Tests/ReferenceCoreTests/QQMusicQRCTests.swift',
    'Tests/ReferenceCoreTests/NonNotchLyricsGeometryTests.swift',
    'Tests/ReferenceCoreTests/Fixtures/qq-qrc-studio.hex',
    'Tests/ReferenceCoreTests/LyricsTimelineTests.swift',
    'Tests/ReferenceCoreTests/QQMusicLyricsTests.swift',
    'Tests/ReferenceCoreTests/NotchContourTests.swift',
    'Tests/ValoraTests/LyricsServiceTests.swift',
    'Tests/ValoraTests/IndependentLyricsDeadlineTests.swift',
    'Tests/ValoraTests/LyricsCacheTests.swift',
    'Tests/ValoraTests/MultiDisplayCoordinatorTests.swift',
    'Tests/ValoraTests/RevivalSettingsReloadTests.swift',
    'Tests/ValoraTests/SettingsReductionTests.swift',
    'scripts/qq_lyrics_probe.swift',
    'scripts/run_qq_lyrics_probe.sh',
    'docs/research/lyrics-provider-comparison.md',
    'docs/verification/v0012/source-license.md',
    'docs/reports/v0012-shape-supplement.md',
    'docs/verification/v0012/zhifou-match/summary.json'
]
source = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task': 'docs/pi-tasks/v0012-word-lyrics-final.md',
    'r2_task': 'docs/pi-tasks/v0012-r2-local-timeline-deadline.md',
    'r2_task_sha256': sha(ROOT / 'docs/pi-tasks/v0012-r2-local-timeline-deadline.md'),
    'r4_task': 'docs/pi-tasks/v0012-r4-line-only-overflow.md',
    'r4_task_sha256': sha(ROOT / 'docs/pi-tasks/v0012-r4-line-only-overflow.md'),
    'r3_task': 'docs/pi-tasks/v0012-r3-anchor-cache-cancel.md',
    'r3_task_sha256': sha(ROOT / 'docs/pi-tasks/v0012-r3-anchor-cache-cancel.md'),
    'r3_decision': 'docs/verification/independent-v0012-r2/decision.md',
    'r3_decision_sha256': sha(ROOT / 'docs/verification/independent-v0012-r2/decision.md'),
    'r2_decision': 'docs/verification/independent-v0012-r1/decision.md',
    'r2_decision_sha256': sha(ROOT / 'docs/verification/independent-v0012-r1/decision.md'),
    'task_sha256': sha(ROOT / 'docs/pi-tasks/v0012-word-lyrics-final.md'),
    'lyrics_next_sha256': sha(ROOT / 'docs/LYRICS-NEXT.md'),
    'layout_findings_sha256': sha(ROOT / 'docs/verification/independent-v0011-layout-review/findings.md'),
    'v0011_report_sha256': sha(ROOT / 'docs/reports/v0011.md'),
    'v0011_source_report': str(V11 / 'source-fingerprints.json'),
    'v0012_owned': [{'path': p, 'v0012_sha256': sha(ROOT / p)} for p in owned],
    'qrc_license': 'QQMusicDecoder MIT adaptation; see docs/verification/v0012/source-license.md',
    'cache_limits': {
        'memory_entries': 50,
        'memory_payload_bytes': 5 * 1024 * 1024,
        'disk_bytes': 50 * 1024 * 1024,
        'policy': 'LRU; successful timed/word-timed only; hash filenames; atomic writes'
    },
    'preserved': [
        'V0008 reduced settings/context menu',
        'V0009 active-screen ownership and one expanded panel',
        'R1/R2 idle deadline behavior',
        'Valora color app icon and Outline-v7 menu-bar resources/wiring'
    ]
}
(V12 / 'source-fingerprints.json').write_text(json.dumps(source, indent=2, sort_keys=True))

qa = json.loads((V12 / 'qa/verification.json').read_text())
ui = json.loads((V12 / 'ui/verification.json').read_text())
multi = json.loads((V12 / 'multidisplay/verification.json').read_text())
settings = json.loads((V12 / 'settings/verification.json').read_text())
qrc = json.loads((V12 / 'qrc-network/network-summary.json').read_text())
verification = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'task_sha256': source['task_sha256'],
    'xctest': {
        'valora': 63, 'reference_core': 105, 'total': 168,
        'prior_v0011_baseline': 136,
        'log': str(V12 / 'test.log')
    },
    'qrc_real_network': {
        'command': './scripts/run_qq_lyrics_probe.sh docs/verification/v0012/qrc-network',
        'generated_at': qrc.get('generated_at'),
        'samples': [
            {'label': s.get('label'), 'status': s.get('status'),
             'qrc_decoded': s.get('qrc', {}).get('decoded'),
             'qrc_lines': s.get('qrc', {}).get('line_count'),
             'qrc_words': s.get('qrc', {}).get('word_count'),
             'first_word_start': s.get('qrc', {}).get('first_word_start'),
             'first_word_duration': s.get('qrc', {}).get('first_word_duration')}
            for s in qrc.get('samples', [])
        ],
        'summary': str(V12 / 'qrc-network/network-summary.json'),
        'note': 'Real public QRC decrypted; only timing/count summaries are recorded, no lyric text.'
    },
    'lyrics_qa': {
        'passed': qa.get('passed'), 'checks': len(qa.get('checks', [])),
        'provider': qa.get('provider'), 'evidence': str(V12 / 'qa/verification.json'),
        'log': str(V12 / 'qa.log'),
        'command': './dist/Valora.app/Contents/MacOS/Valora --verify-lyrics docs/verification/v0012/qa'
    },
    'music_ui': {'passed': ui.get('passed'), 'checks': len(ui.get('checks', [])), 'evidence': str(V12 / 'ui/verification.json')},
    'multidisplay': {'passed': multi.get('passed'), 'checks': len(multi.get('checks', [])), 'evidence': str(V12 / 'multidisplay/verification.json'),
                     'note': 'injected/fake screens; not physical dual-screen'},
    'settings': {'preferencePersistenceVerified': settings.get('preferencePersistenceVerified'),
                 'pages': settings.get('renderedPages'), 'evidence': str(V12 / 'settings/verification.json')},
    'non_notch_geometry': {
        'base_width': 140, 'music_compact_width': 214, 'expanded_width': 345,
        'forms': ['simulated notch', 'ordinary pill'],
        'physical_notch': 'hardware geometry remains authoritative; built-in sample 185pt',
        'screenshots': ['lyrics-nonnotch-pill-compact.png', 'lyrics-nonnotch-simulated-compact.png', 'lyrics-nonnotch-simulated-expanded.png']
    },
    'centering': {
        'short': 'music note + text centered in available lyric area',
        'long': 'real-word 30%-65% reading window with 0...overflow clamp',
        'expanded': 'same centered/reading rule at bottom; volume above',
        'icon': 'artwork accent color; unplayed text gray'
    },
    'capsule': {
        'non_notch_plain': 'pill radius capped at base compact height/2 when lyric row increases visible height',
        'simulated': 'notch contour unchanged',
        'physical': 'hardware contour unchanged',
        'screenshots': ['lyrics-nonnotch-pill-compact.png', 'lyrics-nonnotch-simulated-compact.png']
    },
    'cancellation': {
        'hidden_gate': 'LyricsController refuses new requests while screenHidden/showNotch hides the surface',
        'qrc': 'CancellationError is rethrown; no LRC fallback after cancel',
        'cache': 'canceled/noncooperative result checks Task.isCancelled and in-flight id before cache.put',
        'timeout': '3s group timeout hides; late results rejected by generation/identity'
    },
    'r4_line_only': {
        'policy': 'words-empty long LRC: gray text, short 15% prefix hold then continuous gray-line slide over line start...next line',
        'short': 'words-empty short stays centered/static',
        'pause_seek': 'local Timeline clock freezes on pause; seek recomputes line/offset; new line resets',
        'no_fake_word': 'no colored word fill or average character timing for words-empty lines'
    },
    'r3_fixes': {
        'deadline_latch': 'cancel/complete/attach acyclic latch stores pending completion; exactly one resume',
        'sample_anchor': 'model elapsedSampleDate + playbackRate; delayed mount/expand uses sample age',
        'metrics_cache': 'full song identity + line start/text + complete word segmentation; guarded indices; bounded 8 entries',
        'continuous_offset': 'word fraction through multi-character source words; 0...overflow; 30%-65%'
    },
    'r2_local_timeline': {
        'line_and_word': 'single 30Hz CompactLyricsView TimelineView; no 0.25s line selector',
        'anchor': 'last player elapsed + sample Date + playbackRate; rate<=0/paused holds',
        'offset': 'continuous word fraction; multi-character source word; 0...overflow, 30%-65%',
        'deadline': 'unstructured race gate resumes at budget even with noncooperative continuation provider'
    },
    'playback_clock': {
        'source': 'last player elapsed anchor + playbackRate',
        'refresh': 'visible 30Hz TimelineView only while playing; paused/hidden view stops',
        'measurement': 'line word/prefix widths cached per view; no per-frame full-line measurement'
    },
    'qrc_evidence_fields': {'decoded': True, 'decryption': 'mit_qqmusicdecoder_swift'},
    'matching': {
        'request': '知否知否 / 胡夏 / 同专辑 / 276s',
        'matched': '胡夏 / 郁可唯 collaboration candidate',
        'male_version': 'rejected by versionMismatch',
        'rule': 'request artist set subset of candidate artist set after version/album/duration gates; no contains/first-pick',
        'evidence': str(V12 / 'zhifou-match/summary.json')
    },
    'cache_tests': {
        'memory_limits': 'entry and payload eviction exercised with injected small limits',
        'disk_limit': 'disk byte limit and corrupt-file removal exercised',
        'negative_results': 'noLyrics/not-cached and same-version overwrite exercised',
        'in_flight': 'canceled old request and replacement same request exercised'
    },
    'limitations': [
        'Lyrics QA uses static injected playback/timeline; it does not claim real player/network frame alignment.',
        'Real QRC was fetched and decoded from explicit public samples; no account/cookie/local library data was used.',
        'Physical dual-screen and user real playback/seek remain pending; no real media/system writes were performed.',
        'The disk/memory cache tests use small injected limits; production defaults are 50 entries/5MiB memory/50MiB disk.'
    ]
}
(V12 / 'verification.json').write_text(json.dumps(verification, indent=2, sort_keys=True))

build = json.loads((ROOT / 'dist/build-verification.json').read_text())
entries = []
for path in sorted(p for p in APP.rglob('*') if p.is_file()):
    entries.append({'path': str(path.relative_to(APP)), 'bytes': path.stat().st_size, 'sha256': sha(path)})
artifact = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app': str(APP), 'bundle_identifier': build['bundle_id'],
    'version': build['version'], 'build': build['build'], 'architecture': build['architecture'],
    'binary_sha256': build['binary_sha256'],
    'info_plist_icon_key': build.get('icon_info_key'),
    'app_icon_sha256': sha(APP / 'Contents/Resources/AppIcon.icns'),
    'menubar_icon_files': {p.name: sha(p) for p in sorted((APP / 'Contents/Resources').glob('MenuBarIcon*'))},
    'codesign_verify': subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(APP)],
                                      text=True, capture_output=True).stderr.strip(),
    'file_count': len(entries), 'bundle_bytes': sum(e['bytes'] for e in entries),
    'files': entries, 'build_verification': build
}
(V12 / 'artifact-manifest.json').write_text(json.dumps(artifact, indent=2, sort_keys=True))
print('owned', len(owned), 'artifact', len(entries), artifact['bundle_bytes'], artifact['binary_sha256'])
