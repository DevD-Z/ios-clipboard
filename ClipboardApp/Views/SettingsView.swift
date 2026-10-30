import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: ClipboardAppModel
    @ObservedObject var googleSync: GoogleDriveSyncModel
    @Environment(\.dismiss) private var dismiss
    @State private var backupDocument: ClipboardBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var isPreparingBackup = false
    @State private var isImportingBackup = false
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            settingsList
        }
    }

    private var settingsList: some View {
        List {
            googleDriveSection
            storageSection
            backupSection
            iCloudSection
            keyboardSection
            privacySection
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("settingsDoneButton")
            }
        }
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Clipboard-Backup"
        ) { result in
            if case let .failure(error) = result {
                backupMessage = error.localizedDescription
            }
            backupDocument = nil
        }
        .fileImporter(
            isPresented: $showingBackupImporter,
            allowedContentTypes: [.json]
        ) { result in
            importBackup(result)
        }
        .alert("Backup & Restore", isPresented: backupAlertPresented) {
            Button("OK", role: .cancel) { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
        .alert("iCloud Sync", isPresented: cloudAlertPresented) {
            Button("OK", role: .cancel) { model.cloudSyncErrorMessage = nil }
        } message: {
            Text(model.cloudSyncErrorMessage ?? "")
        }
    }

    private var backupAlertPresented: Binding<Bool> {
        Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )
    }

    private var cloudAlertPresented: Binding<Bool> {
        Binding(
            get: { model.cloudSyncErrorMessage != nil },
            set: { if !$0 { model.cloudSyncErrorMessage = nil } }
        )
    }

    private var googleAutoSyncBinding: Binding<Bool> {
        Binding(
            get: { googleSync.isEnabled },
            set: { googleSync.setEnabled($0, model: model) }
        )
    }

    @ViewBuilder
    private var googleDriveSection: some View {
        Section {
            if googleSync.isConfigured {
                if googleSync.isSignedIn {
                    Label(
                        googleSync.accountEmail ?? "Connected to Google",
                        systemImage: "person.crop.circle"
                    )
                    Toggle("Auto Sync", isOn: googleAutoSyncBinding)
                    Button("Sync Now") {
                        googleSync.syncNow(model: model)
                    }
                    .disabled(googleSync.isBusy)

                    Button("Disconnect Google Account", role: .destructive) {
                        googleSync.signOut()
                    }
                } else {
                    Button("Connect Google Drive") {
                        googleSync.signIn(model: model)
                    }
                    .disabled(googleSync.isBusy)
                }
            } else {
                Label("Google OAuth setup required", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("Add an iOS OAuth Client ID and reversed URL scheme to ClipboardApp/Info.plist before building.")
            }

            Text(googleSync.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Google Drive Auto Sync")
        } footer: {
            Text("Sync runs on changes while the app is active and when it reopens. iOS does not guarantee continuous background sync. Google Drive stores an app-private JSON replica; iCloud is optional.")
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section("Storage") {
            if model.isUsingLocalOnlyStorage {
                Label("Local storage fallback is active", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("This IPA is missing the shared App Group entitlement. Saving inside the app works, but the keyboard cannot read these items. Install a build signed with matching App Group profiles to enable sharing.")
            }

            Label("Saved locally on this device", systemImage: "iphone")
            Text("iCloud is optional. Your snippets stay on this device unless you enable iCloud Sync or export a backup.")
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export backup to Files / Google Drive", systemImage: "square.and.arrow.up")
            }
            .disabled(isPreparingBackup || isImportingBackup)
            .accessibilityIdentifier("settingsExportBackupButton")

            Button {
                showingBackupImporter = true
            } label: {
                Label("Import backup from Files / Google Drive", systemImage: "square.and.arrow.down")
            }
            .disabled(isPreparingBackup || isImportingBackup)
            .accessibilityIdentifier("settingsImportBackupButton")
        } header: {
            Text("Backup & Restore")
        } footer: {
            Text("Manual backup only, not automatic Google sync. Install Google Drive, sign in, and enable it in the iOS Files app to save or open a backup there. Imported snippets are merged with existing snippets. Backup files contain unencrypted text.")
        }
    }

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            Toggle(
                "Sync with iCloud",
                isOn: Binding(
                    get: { model.isCloudSyncEnabled },
                    set: { model.setCloudSyncEnabled($0) }
                )
            )
            .disabled(model.isChangingCloudSync)
            .accessibilityIdentifier("settingsICloudSyncToggle")
        } header: {
            Text("iCloud (Optional)")
        } footer: {
            Text("Optional. Sync saved snippets across your devices signed in to the same Apple Account. Turning this off keeps snippets on this device and stops future syncing; copies already in iCloud remain there.")
        }
    }

    @ViewBuilder
    private var keyboardSection: some View {
        Section("Keyboard") {
            Label("Add Clipboard in Settings > General > Keyboard > Keyboards > Add New Keyboard.", systemImage: "keyboard")
            Label("Use the globe key to switch to Clipboard.", systemImage: "globe")
            Label("Clipboard uses Full Access to save from clipboard, favorite, or delete snippets from the keyboard. The keyboard itself does not connect to iCloud.", systemImage: "lock")
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .accessibilityIdentifier("settingsOpenSystemSettingsButton")
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section("Privacy") {
            Text("Snippets stay on this device unless you turn on iCloud sync, enable Google Drive Auto Sync, or manually export a backup.")
            Text("Clipboard has no advertising. iCloud sync uses your private iCloud database. Google Drive Auto Sync uses your Google account's app-private data folder. Exported backup files are unencrypted, so only save them in a location you trust.")
        }
    }

    private func exportBackup() {
        guard !isPreparingBackup else { return }
        isPreparingBackup = true
        model.exportBackup { result in
            isPreparingBackup = false
            switch result {
            case let .success(data):
                backupDocument = ClipboardBackupDocument(data: data)
                showingBackupExporter = true
            case let .failure(error):
                backupMessage = error.localizedDescription
            }
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        guard !isImportingBackup else { return }
        switch result {
        case let .failure(error):
            backupMessage = error.localizedDescription
        case let .success(url):
            do {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }

                let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard fileSize <= ClipboardBackupArchive.maximumBytes else {
                    throw ClipboardBackupError.fileTooLarge
                }

                let data = try Data(contentsOf: url)
                guard data.count <= ClipboardBackupArchive.maximumBytes else {
                    throw ClipboardBackupError.fileTooLarge
                }

                isImportingBackup = true
                model.importBackup(data: data) { result in
                    isImportingBackup = false
                    switch result {
                    case let .success(added):
                        backupMessage = "Import complete. Added \(added) snippets without replacing existing items."
                    case let .failure(error):
                        backupMessage = error.localizedDescription
                    }
                }
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }
}

/// A user-controlled JSON backup, intentionally independent of CloudKit and Google OAuth.
struct ClipboardBackupArchive: Codable {
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumItems = 10_000

    let formatVersion: Int
    let exportedAt: Date
    let items: [ClipboardItem]

    static func encode(items: [ClipboardItem]) throws -> Data {
        let archive = ClipboardBackupArchive(formatVersion: 1, exportedAt: .now, items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw ClipboardBackupError.fileTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> [ClipboardItem] {
        guard data.count <= maximumBytes else { throw ClipboardBackupError.fileTooLarge }
        guard let archive = try? JSONDecoder().decode(ClipboardBackupArchive.self, from: data),
              archive.formatVersion == 1,
              archive.items.count <= maximumItems else {
            throw ClipboardBackupError.invalidFile
        }
        let items = archive.items
        guard Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ClipboardBackupError.invalidFile
        }
        return items
    }
}

enum ClipboardBackupError: LocalizedError {
    case invalidFile
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Invalid Clipboard backup file or unsupported version."
        case .fileTooLarge: return "This backup exceeds the 20 MB limit."
        }
    }
}

struct ClipboardBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw ClipboardBackupError.invalidFile
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
