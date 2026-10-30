# iCloud Sync: Apple Developer setup and signed builds

The Clipboard app stores snippets locally and optionally syncs them using **SwiftData + CloudKit**.
A successful **unsigned IPA** build does not grant iCloud capabilities. iCloud cannot be enabled
by changing only the source code or by re-signing with a provisioning profile that lacks CloudKit.

## Current project identifiers

| Item | Value |
| --- | --- |
| Containing app | `com.iosclipboard.app` |
| Keyboard extension | `com.iosclipboard.app.keyboard` |
| App Group | `group.com.iosclipboard.shared` |
| CloudKit container | `iCloud.com.iosclipboard.app` |

**These are example identifiers from the original source.** They must exist on (and belong to)
your Apple Developer team. If they are already registered by another team, replace them
with your own unique identifiers; changing the source alone will not register them with Apple.

## Step 1: Configure capabilities in Apple Developer

An active Apple Developer Program membership is required for the appropriate signing profiles.

1. Register an explicit App ID for the main app and another for the keyboard extension.
2. Create an App Group. Enable **App Groups** on **both** App IDs and assign the same group.
3. Enable **iCloud > CloudKit** on the **main app ID**, and associate the CloudKit container.
4. Enable the necessary Push Notifications capability for the main app if required by CloudKit mirroring.
5. Register the test iPhone's device identifier if using **Development** or **Ad Hoc** signing.
6. Create or refresh the provisioning profiles for **both** app and keyboard extension,
   ensuring each matches its Bundle ID and entitlements.

If you changed identifiers, update them in all of these files:

- `iOSClipboard.xcodeproj/project.pbxproj`: both targets' Debug/Release Bundle IDs
- `ClipboardApp/ClipboardApp.entitlements`: App Group and CloudKit container
- `ClipboardKeyboard/ClipboardKeyboard.entitlements`: App Group
- `Shared/Constants/AppGroup.swift`: App Group and CloudKit container strings
- `codemagic.yaml`: signed workflow's `ios_signing.bundle_identifier`

**Do not change identifiers for an already distributed app without understanding its data
and update compatibility.** Changing the App Group moves the shared storage location,
and changing the CloudKit container changes the sync database. Back up snippets first.

## Step 2: Configure signing in Codemagic

In **Codemagic > Team settings > codemagic.yaml settings > Code signing identities**:

1. Add or generate an **Apple Development** signing certificate.
2. Add/fetch **Development** provisioning profiles for the main app and keyboard extension.
3. Check that the main profile includes CloudKit and App Groups, and the extension profile
   includes the same App Group.
4. Use the `iOS Clipboard - Signed iCloud (Development)` workflow.

Codemagic executes `xcode-project use-profiles` and then `xcode-project build-ipa` to
build a signed IPA. It cannot synthesize Apple-approved entitlements or signing profiles.

Do **not** use `iOS Clipboard - Unsigned IPA` to test iCloud Sync.

## Step 3: Test iCloud correctly

- On the iPhone, sign in to an Apple Account for iCloud and enable iCloud Drive if needed.
- Install the properly signed development IPA on a device included in its profile.
- Open Clipboard, enable **Settings > Sync with iCloud**, add a snippet, and observe
  sync events on another installed device signed in to the same iCloud account.
- The first sync may take time and depends on network connectivity and iCloud availability.
- If sync still fails, inspect device logs and CloudKit Console for a concrete error,
  such as `permissionFailure`, `notAuthenticated`, `Invalid bundle ID for container`,
  or missing CloudKit schema.

### Production builds (Ad Hoc, TestFlight, App Store)

Before using production CloudKit, initialize the **development schema** and deploy it to
**production** in CloudKit Console. For this project, `ClipboardApp.swift` contains a
development-only `-InitializeCloudKitSchema` launch argument, which requires a signed
development build with a correctly configured CloudKit container.

A production signed IPA also requires corresponding Ad Hoc or App Store provisioning
profiles, and the Codemagic `distribution_type` must match them.

## References

- Apple Developer — Enable app capabilities:
  https://developer.apple.com/help/account/identifiers/enable-app-capabilities/
- Apple Developer — Deploy a CloudKit schema:
  https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema
- Codemagic — Signing iOS apps:
  https://docs.codemagic.io/yaml-code-signing/signing-ios/
- Codemagic — Building native iOS apps:
  https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/
