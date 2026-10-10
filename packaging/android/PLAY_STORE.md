# Publishing the Android app on Google Play

Audit of the current build (versionName 0.1.2, API 36) against Google Play policy, and what is
still left to do in the Play Console. Re-run the checks below before every submission.

## Already compliant (verified on the release APK)

| Requirement | Status |
| --- | --- |
| Target API level | 36 (Play requires the latest or one below) |
| 16 KB page size support | Native libraries are 16 KB aligned (`zipalign -c -P 16 4`) |
| Not debuggable | `android:debuggable` is false |
| No `INTERNET` permission | Only debug/profile builds have it; the release APK does not |
| No restricted permissions | No SMS, call log, location in the background, all-files, `QUERY_ALL_PACKAGES`, accessibility or device admin |
| Bluetooth scan not used for location | `BLUETOOTH_SCAN` is declared `neverForLocation`; legacy location permission is `maxSdkVersion=30` |
| Foreground service type declared | `connectedDevice` + `FOREGROUND_SERVICE_CONNECTED_DEVICE` (BLE advertising) |
| Boot start allowed | `connectedDevice` is not one of the foreground service types blocked from `BOOT_COMPLETED` on Android 15 |
| Cloud backup off | `allowBackup=false` and `dataExtractionRules` exclude everything (secrets are bound to the device Keystore) |
| No proprietary SDKs | No Google Play services, Firebase, ads or analytics; QR scanning uses ZXing (Apache-2.0) |
| Privacy policy | In the app (Settings -> Privacy policy) and public at https://github.com/sandipbera35/StepAway/blob/main/PRIVACY.md |
| Open-source licenses shown | About -> Open-source licenses |

## Must do before the first upload

1. **Create an upload key** and keep it safe (losing it is recoverable only through Play support):
   `keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. **Sign releases with it.** Locally: create `mobile/android/key.properties` (git-ignored)
   with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. In GitHub Actions add the
   secrets `ANDROID_KEYSTORE_B64` (`base64 -w0 upload.jks`), `ANDROID_STORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The release workflow then produces a properly
   signed `stepaway-android.aab`. **Enrol in Play App Signing** when asked.
3. **Upload the `.aab`**, not the APK. Version codes must increase on every upload
   (`tools/version.sh set X.Y.Z` handles this).

## Play Console declarations (these are where apps usually get rejected)

- **Data safety form:** collects no data, shares no data; data is encrypted in transit
  (n/a, no transfer); users can request deletion (n/a, nothing is collected). Answer "No" to
  "Does your app collect or share any of the required user data types".
- **Privacy policy URL:** the PRIVACY.md link above.
- **Foreground service declaration:** type *Connected device*. Explain: "Broadcasts a short
  Bluetooth Low Energy signal so the user's computer can tell the phone is nearby and lock
  itself when the user walks away. Must keep running with the screen off." Attach a short
  screen recording showing: pairing, protection switched on, the notification, and the
  computer locking when the phone leaves.
- **App access:** the app needs a companion desktop app to show its full function. Give the
  reviewer the desktop download link and a short test path, or a video; without it reviewers
  often reject for "broken functionality". The app works without a computer up to the pairing
  screen (onboarding, settings, permissions, privacy policy).
- **Permissions declaration:** none of the restricted ones are used. Camera is used only to scan
  the pairing QR code.
- **Content rating questionnaire:** utility app, no user content: rated for everyone.
- **Target audience:** 18+ / not directed at children (the policy says so).
- **Ads:** none. **Government/health/finance apps:** no.
- **Store listing:** do not imply that StepAway is a security guarantee (the About page says
  distance is an estimate). Do not use Google trademarks in the name or icon.

## Re-check before each upload

```sh
apkanalyzer manifest permissions app-release.apk     # no INTERNET
apkanalyzer manifest target-sdk app-release.apk      # still current
apkanalyzer manifest debuggable app-release.apk      # false
zipalign -c -P 16 -v 4 app-release.apk               # 16 KB aligned
```

This document is an engineering checklist, not legal advice. Google's policies change; confirm
against https://support.google.com/googleplay/android-developer/ before submitting.
