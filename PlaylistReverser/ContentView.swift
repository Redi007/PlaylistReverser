import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var confirmSave = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
                .navigationTitle(model.snapshot?.info.name ?? String(localized: "Playlist Reverser"))
        }
        .disabled(model.isSaving)
        .overlay { if model.isSaving { SavingOverlay() } }
        .task {
            await model.reloadPlaylists()
            #if DEBUG
            // Nur für Bildschirmfotos/manuelle Tests: --select <Name> [--reversed] [--rewrite] [--save-as <Name>]
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--select"), args.indices.contains(i + 1),
               let p = model.playlists.first(where: { $0.name == args[i + 1] }) {
                model.selectedID = p.id
                while model.phase == .loading { try? await Task.sleep(for: .milliseconds(100)) }
                if args.contains("--reversed") { model.toggleReversed() }
                if args.contains("--rewrite") { model.saveMode = .rewriteOriginal }
                if let j = args.firstIndex(of: "--save-as"), args.indices.contains(j + 1) {
                    model.copyName = args[j + 1]
                    model.save()
                }
            }
            #endif
        }
        .alert(String(localized: "Something Went Wrong"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }), presenting: model.error) { error in
            if case .notAuthorized = error {
                Button("Open System Settings") { openAutomationSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: { Text($0.errorDescription ?? "") }
        .sheet(item: $model.report) { SuccessSheet(report: $0) }
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        @Bindable var model = model
        let filtered = model.playlists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return List(filtered, selection: $model.selectedID) { playlist in
            HStack {
                Label(playlist.name, systemImage: playlist.isSmart ? "gearshape" : "music.note.list")
                    .lineLimit(1)
                    .help(playlist.isSmart ? Text("Smart playlist – can only be saved as a copy") : Text(playlist.name))
                Spacer()
                Text(playlist.trackCount, format: .number).foregroundStyle(.secondary).monospacedDigit().font(.callout)
            }
            .tag(playlist.id)
        }
        .searchable(text: $search, placement: .sidebar, prompt: Text("Search Playlists"))
        .overlay { sidebarPlaceholder(filteredIsEmpty: filtered.isEmpty) }
        .toolbar {
            ToolbarItem {
                Button { model.reloadAll() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .help("Reload playlists from Music")
                    .disabled(model.isLoadingList || model.isSaving)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }

    @ViewBuilder private func sidebarPlaceholder(filteredIsEmpty: Bool) -> some View {
        if model.isLoadingList && model.playlists.isEmpty {
            ProgressView("Loading Playlists…")
        } else if let error = model.listError, model.playlists.isEmpty {
            ContentUnavailableView {
                Label(error.isNotAuthorized ? "No Access to Music" : "Couldn’t Load Playlists", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "")
            } actions: {
                if error.isNotAuthorized {
                    Button("Open System Settings") { openAutomationSettings() }
                }
                Button("Try Again") { Task { await model.reloadPlaylists() } }
            }
        } else if model.playlists.isEmpty {
            ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                                   description: Text("No playlists of your own were found in Music."))
        } else if filteredIsEmpty {
            ContentUnavailableView.search(text: search)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView("Select a Playlist", systemImage: "arrow.up.arrow.down.circle",
                                   description: Text("Choose a playlist on the left to preview it in reverse. Nothing is saved to Music until you confirm."))
        case .loading:
            ProgressView("Reading Playlist…").controlSize(.large)
        case .ready:
            if let snapshot = model.snapshot {
                PreviewView(snapshot: snapshot, confirmSave: $confirmSave)
            }
        }
    }

    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension MusicError {
    var isNotAuthorized: Bool { if case .notAuthorized = self { true } else { false } }
}
