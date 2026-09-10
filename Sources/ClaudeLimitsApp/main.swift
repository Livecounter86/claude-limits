import AppKit
import ClaudeLimitsCore

/// Menu-bar-only app: no dock icon, no windows.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController()
    }
}

/// `--print` renders the same reading to stdout instead of the menu bar, for
/// scripting and for checking what the app sees without opening the menu.
if CommandLine.arguments.contains("--print") {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        do {
            let snapshot = try await UsageAPI().fetchSnapshot()
            print(TextReport.render(snapshot))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exitCode = 1
        }
        semaphore.signal()
    }

    semaphore.wait()
    exit(exitCode)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
