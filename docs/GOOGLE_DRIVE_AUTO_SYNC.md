# Google Drive Auto Sync setup

Google Drive Auto Sync is implemented using the official GoogleSignIn Swift Package
and the Google Drive REST API's **private appDataFolder**, with the narrow
`https://www.googleapis.com/auth/drive.appdata` permission.

## Required Google Cloud configuration

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select a project.
2. Enable **Google Drive API** in APIs & Services.
3. Configure the OAuth consent screen. Set the audience/test users as required.
4. Create an **OAuth Client ID** of type **iOS**, for the actual installed app's
   Bundle ID (currently `com.iosclipboard.app` unless you changed it for signing).
5. In Codemagic, add an application environment variable named `GOOGLE_IOS_CLIENT_ID`
   containing the full iOS OAuth Client ID (e.g. `1234567890-example.apps.googleusercontent.com`).
   Both workflows now generate the matching `GIDClientID` and reversed URL scheme
   in `ClipboardApp/Info.plist` at build time. No repository editing is required.
   Alternatively, configure the same two Info.plist entries manually.
6. Rebuild a properly signed IPA. Google Sign-In uses iOS Keychain for account tokens.
   An unsigned IPA will not automatically have the signing/keychain/App Group privileges.
7. In the app open **Settings > Google Drive Auto Sync > Connect Google Drive**.
   Grant access to the app's own hidden Drive data, then enable **Auto Sync**.

No OAuth client secret is stored in the repository. The placeholder must be replaced
with your own public iOS Client ID and reversed URL scheme. Do not publish client secrets,
refresh tokens, API keys with special privileges, or account credentials to GitHub.

## How it works

- Local snippets remain the primary data, available offline.
- When the app is active and snippets change, the app debounces then performs Drive sync.
- Returning to the app triggers a sync, and **Sync Now** is available in Settings.
- Google Drive stores a JSON replica in **appDataFolder**, not a user-visible Drive file.
- The replica carries timestamps and tombstones. Newer edits/deletes override older copies.
- Changes are merged into local storage before uploading; the importer never clears the DB.
- An existing corrupt/incompatible remote file blocks overwrite, protecting data.
- iCloud Sync remains optional and independent. Avoid enabling both initially
  if you need simple predictable synchronization.

Google Drive does not automatically push changes to a closed iOS app. iOS can suspend
or terminate the app in background, so **24/7 instant background sync is not guaranteed**.
There is no secret background clipboard monitoring.

## Common problems

**Google OAuth is not configured:** Your Info.plist contains placeholder values.

**Shared storage is unavailable:** Your installed IPA lacks the App Group entitlement.
The app has a local-only fallback so saving inside it continues to work; the keyboard
cannot see fallback data until both targets are signed with the same App Group capability.
See `ICLOUD_SETUP.md` for the App Group signing guidance. App Group does not require iCloud.

**Cannot sign in:** Check that the Google Cloud iOS OAuth client matches the Bundle ID
of the signed app, that its reversed URL scheme matches Info.plist, and that your
Google account is permitted to test the consent screen.

**Drive API 403:** Verify Drive API is enabled and appDataFolder scope was granted.

**Initial sync:** You must open the app to authorize and start sync on each device.
Both devices must use the same Google account and project OAuth configuration.

## Security and privacy

The sync file is JSON containing actual saved snippet text in Google Drive appDataFolder.
It is **not end-to-end encrypted by this application**, and is distinct from the manual
Files backup. Google account tokens are managed by the GoogleSignIn SDK in Keychain.
Only enable sync for data you are comfortable storing in your own Google account.

## References

- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developers.google.com/identity/sign-in/ios/api-access
- https://developers.google.com/workspace/drive/api/guides/appdata
- https://developers.google.com/workspace/drive/api/guides/manage-uploads

## Recent copied-text privacy

The one-hour preview records only the system pasteboard change count and the time
that Clipboard first observed a change. The text itself is not automatically
saved into the snippet database or uploaded to Drive. iOS does not expose the
original copy timestamp to other applications, so the one-hour interval is
measured from Clipboard's first observation, not guaranteed from the exact time
of copying. The preview requires pasteboard access and iOS can show a permission
prompt. Copying while the application is suspended cannot be monitored live.

## Why a successful unsigned build still shows warnings

Codemagic's **Unsigned IPA** workflow deliberately disables Apple code signing.
An unsigned app (or an IPA re-signed without the required App Group in both
provisioning profiles) cannot share its snippet database with the keyboard.

Use the **Signed App Group and iCloud (Development)** workflow after supplying
Apple signing profiles and a certificate. Its entitlement validation step
now fails if either signed target lacks `group.com.iosclipboard.shared`.

The Google account setup is **independent of Apple iCloud**, but Google OAuth
still requires a registered iOS Client ID and URL scheme and a signed app for
reliable keychain-based sign-in. Changing Swift code or hiding the warning
cannot create these external credentials.

When the system pasteboard contains no string, **Save from clipboard** cannot
save a previously created snippet. Copy text in another app or use **+**
to create a snippet manually. iOS can show a paste access permission request.
