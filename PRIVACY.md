# StepAway privacy policy

_Last updated: 10 October 2026_

**StepAway does not collect, send, sell or share any personal data. It has no accounts, no ads, no analytics, no crash reporting and makes no internet connections. Everything it needs stays on your own devices.**

## 1. Who is responsible

StepAway is published by sandipbera35 (an individual). The desktop app and service are free and open-source software; the Android app is a paid, closed-source app. Because the developer never receives any of your data, the developer does not act as a processor or controller of your personal data. Questions can be asked in the issue tracker: https://github.com/sandipbera35/StepAway/issues

## 2. What StepAway stores on your computer

Pairing records: for each paired device a numeric ID, the name you gave it, a secret key shared with that device, and (only if you choose a "presence only" device) its Bluetooth address. The file is readable only by your user account.

Settings: distances, delays and the lists of apps and services you chose to close or stop when locking.

A diagnostic log of what the service did ("locking the session", "state changed"). It never contains secret keys or tokens.

The list of apps and services on your computer is read locally only to let you pick which ones to close or stop. It is not saved beyond your choices and never leaves the computer.

## 3. What StepAway stores on your phone

Pairing records: the name of your computer and the shared secret key. The key is encrypted with a key held in the Android Keystore.

Small preferences (theme, the speed setting, calibration, onboarding done).

Android backup is switched off for StepAway, so none of this is copied to a cloud backup.

## 4. Bluetooth

Your phone or watch broadcasts a short Bluetooth Low Energy signal containing StepAway's service identifier and a signed token that changes every 10 seconds. The token contains no name, location or account information and cannot be used without the secret key. Anyone nearby with a Bluetooth scanner can see that a StepAway signal is present, and its signal strength, but cannot tell who you are.

Your computer scans for these signals to estimate distance. It briefly sees the names and addresses of other nearby Bluetooth devices. These are held in memory for up to 20 seconds so you can pick a device in the list, are never written to disk unless you choose one, and are never sent anywhere.

The phone app scans for your computer's signal only while the app is open on its Home screen, to show the distance. It does not use Bluetooth to find your location.

## 5. Android permissions

Bluetooth (advertise, scan, connect): to send and receive the signals above.

Camera: only to scan the pairing QR code. Pictures are never saved or sent.

Notifications and foreground service: to show the notice that protection is running and keep it running with the screen off.

Run at start-up: to resume protection after the phone restarts.

Location (Android 11 and older only): the old Android Bluetooth scan rules require it. StepAway does not read your location.

The app does not request the Internet permission.

## 6. Sharing and third parties

None. StepAway contains no advertising, analytics or tracking code, and no code from Google Play services or similar proprietary SDKs. The only open-source libraries it uses are listed under "Open-source licenses" on the About page.

If you download StepAway from a website or app store, that store has its own privacy policy for the download itself.

## 7. Keeping and deleting your data

You are in control. To stop a device from locking your computer, remove it in the Devices page (computer) or Computers page (phone).

To erase everything: use Settings → Uninstall on the computer, which can delete all pairing records, settings and logs, or uninstall the app from your phone. If you delete files by hand, they are in ~/.config/stepaway and ~/.local/share/stepaway on Linux, and %APPDATA%\StepAway on Windows.

## 8. Security

Tokens are signed with a secret key using HMAC-SHA-256. Secret keys are never logged. When anything is uncertain, StepAway keeps the computer locked. Distance from Bluetooth signal strength is only an estimate, and no proximity lock can fully prevent someone who relays your phone's signal. Do not rely on StepAway as your only protection. Report vulnerabilities privately: https://github.com/sandipbera35/StepAway/security/policy

## 9. Children

StepAway is not directed at children and does not knowingly collect information from anyone, including children.

## 10. Your rights

Because the developer holds no data about you, there is nothing to access, correct or delete on the developer's side. Under laws such as the GDPR and CCPA you may ask, but the answer will be that no personal data is held. All data StepAway keeps is on your own devices and you can inspect or delete it at any time.

## 11. Changes to this policy

If StepAway ever changes what it does with data, this policy will be updated before the change ships, and the date above will change. The full history is public: https://github.com/sandipbera35/StepAway/blob/main/PRIVACY.md

---

This file is generated from `ui/lib/src/legal.dart`, the same text shown inside the apps (About → Privacy policy). Edit that file and run `python3 tools/gen-privacy-md.py`.
