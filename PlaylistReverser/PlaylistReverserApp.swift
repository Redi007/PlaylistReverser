import SwiftUI

@main
struct PlaylistReverserApp: App {
    @State private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            Task.detached { exit(await SelfTest.run(arguments: CommandLine.arguments) ? 0 : 1) }
        }
    }

    var body: some Scene {
        WindowGroup("Playlist Reverser") {
            ContentView()
                .environment(model)
                .tint(.accentColor)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Playlist Reverser") { showAbout() }
            }
        }
    }

    private func showAbout() {
        let license = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "MIT License"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let credits = NSAttributedString(string: license, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            .version: "",
            .credits: credits
        ])
    }
}
