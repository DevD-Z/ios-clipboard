import Combine
import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

private enum DriveSyncError: LocalizedError {
    case notConfigured
    case signedOut
    case permissionRequired
    case unavailablePresenter
    case invalidRemoteData
    case conflict
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure the Google iOS OAuth Client ID and URL scheme before using Google Drive."
        case .signedOut: return "Connect a Google account to sync."
        case .permissionRequired: return "Google Drive app-data permission was not granted. Disconnect and connect again."
        case .unavailablePresenter: return "Could not open Google Sign-In. Open the app and try again."
        case .invalidRemoteData: return "Google Drive contains an invalid or incompatible Clipboard sync file. It was not overwritten."
        case .conflict: return "Another device changed the cloud copy. Try syncing again."
        case let .http(code, message): return "Google Drive error \(code): \(message)"
        }
    }
}

/// Stores Google OAuth credentials in Google Sign-In's keychain, never in UserDefaults.
/// Sync runs after user consent, foreground entry and local changes; background scheduling
/// is intentionally not promised by iOS.
@MainActor
final class GoogleDriveSyncModel: ObservableObject {
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "googleDriveAutoSync")
    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Google Drive is disconnected."

    private var didTryRestore = false
    private var queued = false
    private var debounceTask: Task<Void, Never>?

    var isConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com"),
              !id.contains("YOUR_"),
              let component = id.components(separatedBy: ".apps.googleusercontent.com").first,
              !component.isEmpty,
              let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else { return false }
        let expectedScheme = "com.googleusercontent.apps." + component
        return urlTypes.contains { type in
            let schemes = type["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains(expectedScheme)
        }
    }

    func restoreIfNeeded(model: ClipboardAppModel) {
        guard !didTryRestore else { return }
        didTryRestore = true
        guard isConfigured else {
            status = "Google OAuth is not configured. Local storage and manual backups still work."
            return
        }
        Task {
            do {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                isSignedIn = true
                accountEmail = user.profile?.email
                status = "Connected to Google Drive."
                if isEnabled { await performSync(model: model) }
            } catch {
                isSignedIn = false
                isEnabled = false
                UserDefaults.standard.set(false, forKey: "googleDriveAutoSync")
                status = "Connect your Google account to enable Auto Sync."
            }
        }
    }

    func signIn(model: ClipboardAppModel) {
        guard isConfigured else { status = DriveSyncError.notConfigured.localizedDescription; return }
        guard !isBusy else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            status = DriveSyncError.unavailablePresenter.localizedDescription
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                var presenter = root
                while let next = presenter.presentedViewController {
                    presenter = next
                }
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [DriveAppDataAPI.scope]
                )
                guard result.user.grantedScopes?.contains(DriveAppDataAPI.scope) == true else {
                    throw DriveSyncError.permissionRequired
                }
                isSignedIn = true
                accountEmail = result.user.profile?.email
                isEnabled = true
                UserDefaults.standard.set(true, forKey: "googleDriveAutoSync")
                status = "Connected. Google Drive Auto Sync is enabled."
            } catch {
                status = error.localizedDescription
            }
            if isSignedIn && isEnabled { syncNow(model: model) }
        }
    }

    func signOut() {
        debounceTask?.cancel()
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        isEnabled = false
        accountEmail = nil
        UserDefaults.standard.set(false, forKey: "googleDriveAutoSync")
        status = "Disconnected. Snippets remain on this device."
    }

    func setEnabled(_ enabled: Bool, model: ClipboardAppModel) {
        guard isSignedIn else { status = DriveSyncError.signedOut.localizedDescription; return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "googleDriveAutoSync")
        status = enabled ? "Auto Sync is enabled." : "Auto Sync is paused; local snippets are kept."
        if enabled { syncNow(model: model) } else { debounceTask?.cancel() }
    }

    func scheduleSync(model: ClipboardAppModel) {
        guard isEnabled, isSignedIn else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await performSync(model: model)
        }
    }

    func syncNow(model: ClipboardAppModel) {
        guard isSignedIn, isConfigured else {
            status = "Connect Google Drive first."
            return
        }
        Task { await performSync(model: model) }
    }

    private func performSync(model: ClipboardAppModel) async {
        guard isEnabled, isSignedIn else { return }
        guard !isBusy else { queued = true; return }
        isBusy = true
        status = "Syncing with Google Drive…"
        do {
            let result = try await DriveAppDataAPI().sync(model: model)
            status = "Last synced: \(Date().formatted(date: .abbreviated, time: .shortened)) (\(result) items)"
        } catch {
            status = "Sync failed: \(error.localizedDescription) — your local snippets are safe."
        }
        isBusy = false
        if queued {
            queued = false
            scheduleSync(model: model)
        }
    }
}

@MainActor
private struct DriveAppDataAPI {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    private let filename = "clipboard-replica-v1.json"
    private let maxBytes = 20 * 1024 * 1024

    private struct FileList: Decodable {
        struct Entry: Decodable { let id: String; let name: String }
        let files: [Entry]
    }

    private struct Replica: Codable {
        let formatVersion: Int
        let items: [ClipboardItem]
    }

    private struct Remote {
        let id: String
        let data: Data
        let etag: String?
        let replica: Replica
    }

    func sync(model: ClipboardAppModel) async throws -> Int {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw DriveSyncError.signedOut }
        guard user.grantedScopes?.contains(Self.scope) == true else { throw DriveSyncError.permissionRequired }
        let refreshed = try await user.refreshTokensIfNeeded()
        let token = refreshed.accessToken.tokenString

        // Fetch remote before saving. If upload conflicts, re-fetch and merge up to 3 times.
        for _ in 0..<3 {
            let remote = try await fetchRemote(token: token)
            if let remote {
                _ = try await model.mergeGoogleReplica(remote.replica.items)
            }
            let items = try await model.replicaSnapshot().sorted { $0.id.uuidString < $1.id.uuidString }
            guard items.count <= 10_000 else { throw DriveSyncError.invalidRemoteData }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let payload = try encoder.encode(Replica(formatVersion: 1, items: items))
            guard payload.count <= maxBytes else { throw DriveSyncError.invalidRemoteData }
            if payload == remote?.data { return items.filter { !$0.isDeleted }.count }
            if remote == nil && items.isEmpty { return 0 }

            do {
                if let remote {
                    try await updateRemote(remote, payload: payload, token: token)
                } else {
                    try await createRemote(payload: payload, token: token)
                }
                return items.filter { !$0.isDeleted }.count
            } catch DriveSyncError.conflict { continue }
        }
        throw DriveSyncError.conflict
    }

    private func fetchRemote(token: String) async throws -> Remote? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name = '\(filename)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name),nextPageToken"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        let (metadata, _) = try await request(components.url!, token: token)
        let listed = try JSONDecoder().decode(FileList.self, from: metadata)
        guard let found = listed.files.first(where: { $0.name == filename }) else { return nil }
        var media = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(found.id)")!
        media.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let (data, http) = try await request(media.url!, token: token)
        guard data.count <= maxBytes,
              let replica = try? JSONDecoder().decode(Replica.self, from: data),
              replica.formatVersion == 1,
              replica.items.count <= 10_000,
              Set(replica.items.map(\.id)).count == replica.items.count else {
            throw DriveSyncError.invalidRemoteData
        }
        return Remote(id: found.id, data: data, etag: http.value(forHTTPHeaderField: "ETag"), replica: replica)
    }

    private func updateRemote(_ remote: Remote, payload: Data, token: String) async throws {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(remote.id)?uploadType=media")!
        _ = try await request(url, token: token, method: "PATCH", body: payload,
                              contentType: "application/json", ifMatch: remote.etag)
    }

    private func createRemote(payload: Data, token: String) async throws {
        let boundary = "ClipboardBoundary-\(UUID().uuidString)"
        let info: [String: Any] = [
            "name": filename,
            "parents": ["appDataFolder"],
            "mimeType": "application/json"
        ]
        let metadata = try JSONSerialization.data(withJSONObject: info)
        var data = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        data.append(metadata)
        data.append(Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
        data.append(payload)
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
        _ = try await request(url, token: token, method: "POST", body: data,
                              contentType: "multipart/related; boundary=\(boundary)")
    }

    private func request(_ url: URL, token: String, method: String = "GET", body: Data? = nil,
                         contentType: String? = nil, ifMatch: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let ifMatch { req.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DriveSyncError.invalidRemoteData }
        if http.statusCode == 412 { throw DriveSyncError.conflict }
        guard (200..<300).contains(http.statusCode) else {
            throw DriveSyncError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        return (data, http)
    }
}
