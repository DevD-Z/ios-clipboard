import SwiftUI
import UIKit

struct ClipboardListView: View {
    @ObservedObject var model: ClipboardAppModel
    @StateObject private var googleSync = GoogleDriveSyncModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var showingNewItem = false
    @State private var showingSettings = false
    @State private var recentCopiedText: String?
    @State private var recentCopiedAt: Date?
    @AppStorage("clipboardLastSeenChangeCount") private var clipboardLastSeenChangeCount = -1
    @AppStorage("clipboardLastSeenTime") private var clipboardLastSeenTime = 0.0
    private let recentCopyLifetime: TimeInterval = 60 * 60


    private var visibleItems: [ClipboardItem] {
        model.items.filter { item in
            (!favoritesOnly || item.isFavorite) && (query.isEmpty || item.text.localizedCaseInsensitiveContains(query))
        }
    }

    private var emptyTitle: String { String(localized: favoritesOnly ? "No Favorites" : "No Snippets Yet") }
    private var emptyDescription: String {
        return String(localized: favoritesOnly ? "Mark a snippet as a favorite to find it here." : "Save from clipboard or create a snippet to use it from your keyboard.")
    }

    var body: some View {
        NavigationStack {
            snippetList
            .navigationTitle("Clipboard")
            .onAppear {
                observeCurrentClipboard()
                googleSync.restoreIfNeeded(model: model)
            }
            .onChange(of: model.items) { _, _ in
                googleSync.scheduleSync(model: model)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                observeCurrentClipboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                observeCurrentClipboard()
                googleSync.scheduleSync(model: model)
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                removeExpiredRecentCopy()
            }
            .searchable(text: $query, prompt: "Search snippets")
            .navigationDestination(for: ClipboardItem.self) { SnippetEditor(item: $0, model: model) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { favoritesOnly.toggle() } label: {
                        Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
                    }
                    .accessibilityIdentifier("appFavoritesControl")
                    .accessibilityValue(favoritesOnly ? Text("Showing favorites") : Text("Showing all snippets"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
                        .accessibilityIdentifier("appSettingsControl")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: saveFromClipboard) {
                        Text("Save from clipboard").foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.blue)
                    .accessibilityIdentifier("appSaveFromClipboardControl")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showingNewItem = true } label: { Label("New Snippet", systemImage: "plus") }
                        .accessibilityIdentifier("appNewSnippetControl")
                }
            }
            .sheet(isPresented: $showingNewItem) { NewSnippetSheet(model: model) }
            .sheet(isPresented: $showingSettings) { SettingsView(model: model, googleSync: googleSync) }
            .sheet(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) { OnboardingView() }
        }
    }

    private func observeCurrentClipboard() {
        removeExpiredRecentCopy()
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        if count != clipboardLastSeenChangeCount {
            clipboardLastSeenChangeCount = count
            clipboardLastSeenTime = Date().timeIntervalSince1970
            recentCopiedText = nil
        }
        // Preserve the observed expiry time across app reopening, without persisting
        // the copied text itself. Once expired, it cannot be revived until a new copy.
        guard clipboardLastSeenTime > 0,
              Date().timeIntervalSince1970 - clipboardLastSeenTime < recentCopyLifetime else {
            recentCopiedText = nil
            recentCopiedAt = nil
            return
        }
        if recentCopiedText == nil {
            // iOS may ask for permission when another app's pasteboard is read.
            if let copied = pasteboard.string, !copied.isEmpty {
                recentCopiedText = copied
                recentCopiedAt = Date(timeIntervalSince1970: clipboardLastSeenTime)
            }
        }
    }

    private func removeExpiredRecentCopy() {
        guard let last = recentCopiedAt else { return }
        if Date().timeIntervalSince(last) >= recentCopyLifetime {
            recentCopiedText = nil
            recentCopiedAt = nil
        }
    }

    private func saveFromClipboard() {
        let text = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.errorMessage = String(localized: "Clipboard has no text to save.")
            return
        }
        model.add(text)
    }

    private var snippetList: some View {
        List {
            if model.isUsingLocalOnlyStorage {
                Section {
                    Label("Local-only mode: saved snippets work here, but the keyboard needs App Group signing to access them.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let recentCopiedText, let recentCopiedAt,
               Date().timeIntervalSince(recentCopiedAt) < recentCopyLifetime {
                Section("Latest copied text · disappears after 1 hour") {
                    HStack {
                        Text(recentCopiedText).lineLimit(3)
                        Spacer()
                        Button("Save") { model.add(recentCopiedText) }
                            .buttonStyle(.bordered)
                    }
                    .accessibilityIdentifier("appRecentCopiedText")
                }
            }
            if hasCompletedOnboarding, let error = model.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if visibleItems.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: favoritesOnly ? "star" : "doc.on.clipboard", description: Text(emptyDescription))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ForEach(visibleItems) { item in SnippetNavigationRow(item: item, model: model) }
            }
        }
    }
}

private struct SnippetNavigationRow: View {
    let item: ClipboardItem
    @ObservedObject var model: ClipboardAppModel
    var body: some View {
        NavigationLink(value: item) { SnippetRow(item: item) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { model.delete(item) } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityIdentifier("snippetDeleteAction")
            }
            .swipeActions(edge: .leading) {
                Button { model.toggleFavorite(item) } label: { Label(LocalizedStringKey(item.isFavorite ? "Unfavorite" : "Favorite"), systemImage: item.isFavorite ? "star.slash" : "star") }
                    .tint(.yellow)
                    .accessibilityIdentifier("snippetFavoriteAction")
            }
            .contextMenu {
                Button { model.toggleFavorite(item) } label: { Label(LocalizedStringKey(item.isFavorite ? "Remove Favorite" : "Favorite"), systemImage: item.isFavorite ? "star.slash" : "star") }
                Button(role: .destructive) { model.delete(item) } label: { Label("Delete", systemImage: "trash") }
            }
    }
}

private struct SnippetRow: View {
    let item: ClipboardItem
    var body: some View {
        HStack(spacing: 12) {
            Text(item.text).lineLimit(2).truncationMode(.tail)
            Spacer(minLength: 0)
            if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel(Text("Favorite")) }
        }.accessibilityElement(children: .combine)
    }
}

private struct NewSnippetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ClipboardAppModel
    @State private var text = ""
    @State private var isSaving = false
    @State private var saveError: String?
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).padding(8).navigationTitle("New Snippet")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("newSnippetCancelButton") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("newSnippetSaveButton") }
                }
                .alert("Couldn’t Save Snippet", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK", role: .cancel) { saveError = nil } } message: { Text(saveError ?? "") }
        }
    }
    private func save() {
        isSaving = true
        model.add(text) { success in
            isSaving = false
            if success { dismiss() } else { saveError = model.errorMessage ?? String(localized: "Couldn’t save this snippet.") }
        }
    }
}
