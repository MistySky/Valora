import AppKit
import Foundation

// Development-only verification flags (`--verify*`, `--audit*`, `--preview*`,
// `--expand-media`, `--lock-card-preview`) reach code that is compiled only into
// development builds. Reject them here, before NSApplication/AppKit exists and
// before any media, audio or permission source can start, instead of silently
// falling back to the production launch path.
if let flag = LaunchPolicy.rejection(arguments: CommandLine.arguments,
                                     developmentBuild: LaunchPolicy.isDevelopmentBuild) {
    fputs("Valora: \(flag) is a development-only verification flag and is not available in this build. Remove it to launch normally.\n", stderr)
    exit(2)
}

let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
app.run()
