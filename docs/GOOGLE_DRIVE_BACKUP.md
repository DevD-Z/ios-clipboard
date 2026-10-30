# Local storage, Google Drive, and optional iCloud

## Local storage

Clipboard stores text snippets in its local App Group database by default.
**No iCloud account is needed for on-device storage**. The Keyboard extension and
main app continue using the same App Group to access saved snippets.

The app and keyboard must still be signed with a valid App Group entitlement
if you want both components to share data. An unsigned IPA does not bypass Apple
signing or entitlement requirements.

## Google One vs Google Drive

Google One provides additional storage associated with a Google account; it is not
a separate public third-party clipboard synchronization API. For manually saved
backups, use Google Drive as a location inside the iOS Files app.

This implementation does NOT automatically synchronize, continuously poll, or access
your Google account via OAuth. No Google client ID, API key, or Google Cloud project
is necessary for the manual Files integration.

## Export a backup to Google Drive

1. Install the Google Drive iOS app and sign in.
2. Open iOS **Files > Browse**. Tap the **More (...)** menu, choose **Edit** and
   enable Google Drive under **Locations** (if not already enabled).
3. In Clipboard, open **Settings > Backup & Restore**.
4. Tap **Export backup to Files / Google Drive**.
5. Select Google Drive, choose a trusted folder and save `Clipboard-Backup.json`.

You can save into **On My iPhone** instead for a local-only backup.
The file contains your original snippets, timestamps, favorites, and unique IDs.

**Privacy:** The JSON is unencrypted. Avoid storing passwords, private tokens,
or other confidential information in a backup accessible to other people.

## Restore from Google Drive or Files

1. Open **Clipboard > Settings > Backup & Restore**.
2. Tap **Import backup from Files / Google Drive**.
3. Locate the JSON backup in Google Drive or another Files location.
4. Confirm the success message showing how many snippets were added.

Import is a **merge**, not a destructive restore: existing snippet IDs retain
their existing contents, and previously imported items are not duplicated.
Invalid files and unsupported versions are rejected. Backups are limited to 20 MB
to protect against unusually large or malformed imports.

If **iCloud Sync** is enabled at restore time, the imported local snippets may
also be uploaded to CloudKit. Disable iCloud Sync first if you only want
on-device storage.

## For automatic Google Drive sync (not included)

Automatic cross-device Google sync is a separate feature. It requires an iOS
Google OAuth 2.0 client registration, user consent, appropriate Drive API scopes,
token storage, conflict resolution and data protection. Google Drive's
`appDataFolder` API is one possible private storage location. The Files backup
feature does not imply any of those capabilities.

Google Drive app data reference:
https://developers.google.com/workspace/drive/api/guides/appdata
