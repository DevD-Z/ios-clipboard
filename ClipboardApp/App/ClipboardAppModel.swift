import Foundation
import Combine
import CoreData

@MainActor
final class ClipboardAppModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var errorMessage: String?
    @Published private(set) var isCloudSyncEnabled: Bool
    @Published private(set) var isChangingCloudSync = false
    @Published var cloudSyncErrorMessage: String?

    private let store: ClipboardStore?
    private let ioQueue = DispatchQueue(label: "com.iosclipboard.storage", qos: .userInitiated)
    private var cloudEventObserver: NSObjectProtocol?

    @Published private(set) var isUsingLocalOnlyStorage = false

    /// The Google/App Group-only build intentionally does not ship CloudKit entitlements.
    var isCloudSyncSupported: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "ClipboardCloudKitSupported") as? Bool) ?? true
    }

    init(store injectedStore: ClipboardStore? = nil) {
        let cloudSupported = (Bundle.main.object(forInfoDictionaryKey: "ClipboardCloudKitSupported") as? Bool) ?? true
        let cloudSyncRequested = UserDefaults.standard.bool(forKey: AppGroup.cloudSyncPreferenceKey)
        let sharedStore = try? ClipboardStore(
            access: .readWrite,
            cloudSyncEnabled: cloudSupported && cloudSyncRequested
        )
        // No App Group entitlement is present in some re-signed IPA builds.
        // Keep the app usable without ever pretending that the keyboard can share this fallback.
        let localURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardLocalOnly", isDirectory: true)
        let resolvedStore = injectedStore ?? sharedStore ?? ClipboardStore(
            containerURL: localURL, access: .readWrite, cloudSyncEnabled: false
        )
        let localOnly = injectedStore == nil && sharedStore == nil
        // Initialize all required stored properties before reading any self properties.
        self.store = resolvedStore
        self.isUsingLocalOnlyStorage = localOnly
        self.isCloudSyncEnabled = cloudSupported && !localOnly && cloudSyncRequested
        if localOnly {
            errorMessage = nil
        } else if injectedStore == nil, let shared = sharedStore {
            // Once a correctly signed App Group becomes available, keep previously
            // saved fallback items instead of making them seem to disappear.
            ioQueue.async { [weak self] in
                let db = localURL.appendingPathComponent(AppGroup.swiftDataStoreFilename)
                guard FileManager.default.fileExists(atPath: db.path) else { return }
                let local = ClipboardStore(containerURL: localURL, access: .readOnly)
                do {
                    let items = try local.load()
                    if !items.isEmpty {
                        _ = try shared.mergeBackupItems(items)
                        DispatchQueue.main.async { self?.reload() }
                    }
                } catch {
                    // Never delete or overwrite fallback data on a failed import.
                    DispatchQueue.main.async {
                        self?.errorMessage = "Could not import previous local-only snippets: \(error.localizedDescription)"
                    }
                }
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let model = Unmanaged<ClipboardAppModel>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { model.reload() }
            },
            AppGroup.changeNotification as CFString, nil, .deliverImmediately)
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let imported = event.type == .import && event.succeeded
            let failed = !event.succeeded
            Task { @MainActor [weak self] in
                guard let self, self.isCloudSyncEnabled else { return }
                if imported {
                    self.reload()
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        CFNotificationName(AppGroup.changeNotification as CFString),
                        nil, nil, true
                    )
                } else if failed {
                    self.cloudSyncErrorMessage = String(localized: "iCloud couldn’t sync right now. Your snippets remain available on this device.")
                }
            }
        }
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(AppGroup.changeNotification as CFString), nil)
        if let cloudEventObserver { NotificationCenter.default.removeObserver(cloudEventObserver) }
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        if enabled && !isCloudSyncSupported {
            cloudSyncErrorMessage = "This build supports App Group and Google Drive without iCloud. Use the CloudKit signed workflow to enable iCloud."
            return
        }
        if isUsingLocalOnlyStorage {
            cloudSyncErrorMessage = "App Group signing is missing. Local saving works, but iCloud and the keyboard need a properly signed App Group."
            return
        }
        guard !isChangingCloudSync, enabled != isCloudSyncEnabled else { return }
        guard let store else {
            cloudSyncErrorMessage = ClipboardStoreError.sharedContainerUnavailable.localizedDescription
            return
        }
        isChangingCloudSync = true
        ioQueue.async { [weak self] in
            let result = Result { try store.setCloudSyncEnabled(enabled) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChangingCloudSync = false
                switch result {
                case .success:
                    UserDefaults.standard.set(enabled, forKey: AppGroup.cloudSyncPreferenceKey)
                    self.isCloudSyncEnabled = enabled
                    self.cloudSyncErrorMessage = nil
                    self.reload()
                case let .failure(error):
                    self.cloudSyncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func reload() {
        guard let store else { return }
        ioQueue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                switch result {
                case let .success(items): self?.items = items; self?.errorMessage = nil
                case let .failure(error): self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Exports a snapshot of the actual SQLite-backed store, not a potentially stale UI list.
    func exportBackup(completion: @escaping (Result<Data, Error>) -> Void) {
        guard let store else {
            completion(.failure(ClipboardStoreError.sharedContainerUnavailable))
            return
        }
        ioQueue.async {
            let result = Result { try ClipboardBackupArchive.encode(items: store.load()) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func importBackup(data: Data, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let store else {
            completion(.failure(ClipboardStoreError.sharedContainerUnavailable))
            return
        }
        ioQueue.async { [weak self] in
            let result = Result {
                let items = try ClipboardBackupArchive.decode(data)
                return try store.mergeBackupItems(items)
            }
            DispatchQueue.main.async {
                if case .success = result { self?.reload() }
                completion(result)
            }
        }
    }

    func replicaSnapshot() async throws -> [ClipboardItem] {
        guard let store else { throw ClipboardStoreError.sharedContainerUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                continuation.resume(with: Result { try store.replicaSnapshot() })
            }
        }
    }

    func mergeGoogleReplica(_ items: [ClipboardItem]) async throws -> Int {
        guard let store else { throw ClipboardStoreError.sharedContainerUnavailable }
        let count: Int = try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                continuation.resume(with: Result { try store.mergeReplica(items) })
            }
        }
        if count > 0 { reload() }
        return count
    }

    func add(_ text: String, completion: @escaping (Bool) -> Void = { _ in }) {
        perform({ try $0.add(text: text) }, completion: completion)
    }

    func update(_ item: ClipboardItem, text: String, completion: @escaping (Bool) -> Void = { _ in }) {
        perform({ try $0.update(id: item.id, text: text) }, completion: completion)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        perform { try $0.toggleFavorite(id: item.id) }
    }

    func delete(_ item: ClipboardItem) {
        perform { try $0.delete(id: item.id) }
    }

    private func perform(_ action: @escaping (ClipboardStore) throws -> Void, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let store else {
            errorMessage = ClipboardStoreError.sharedContainerUnavailable.localizedDescription
            completion(false)
            return
        }
        ioQueue.async { [weak self] in
            let result = Result { try action(store); return try store.load() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(items): self.items = items; self.errorMessage = nil; completion(true)
                case let .failure(error): self.errorMessage = error.localizedDescription; completion(false)
                }
            }
        }
    }
}
