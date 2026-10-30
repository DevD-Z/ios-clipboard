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
5. Edit `ClipboardApp/Info.plist`:
   - Replace `YOUR_IOS_CLIENT_ID.apps.googleusercontent.com` with your exact iOS Client ID.
   - Replace `com.googleusercontent.apps.REPLACE_WITH_YOUR_CLIENT_ID` with the **iOS URL scheme**
     provided by Google Cloud (the reversed client ID).
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
