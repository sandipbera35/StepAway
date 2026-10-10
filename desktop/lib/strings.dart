import 'uninstall.dart';

/// All user-visible text lives here so it can move to ARB/intl files later.
class S {
  static const appName = 'StepAway';
  static const dashboard = 'Dashboard';
  static const devices = 'Devices';
  static const calibrate = 'Calibrate';
  static const settings = 'Settings';
  static const serviceDown = 'The StepAway service is not running.';
  static const startService = 'Start service';
  static const serviceStartFailed =
      'Could not start the StepAway service. Reinstall StepAway, or run stepawayd from the app folder.';
  static const noScanner =
      'Bluetooth scanning is not active. Check that Bluetooth is turned on.';
  static const pause = 'Pause protection';
  static const resume = 'Resume protection';
  static const paused = 'Protection is paused';
  static const distance = 'Estimated distance';
  static const noSignal = 'No signal from your phone';
  static const lockAt = 'Locks beyond';
  static const returnAt = 'Counts as back within';
  static const pairPhone = 'Add device';
  static const pairInstruction =
      'Open StepAway on your phone or tablet, tap "Scan QR code" and scan this code. Both screens must show the same number.';
  static const waitingForPhone = 'Waiting for your device...';
  static const paired = 'Device paired!';
  static const done = 'Done';
  static const cancel = 'Cancel';
  static const remove = 'Remove';
  static const removeTitle = 'Remove this device?';
  static const removeBody = 'It will no longer lock or unlock this computer.';
  static const noDevices = 'No device is paired yet.';
  static const lastSeen = 'Last seen';
  static const never = 'never';
  static const lockDistance = 'Lock distance';
  static const returnDistance = 'Return distance';
  static const lockDelay = 'Lock delay';
  static const returnDelay = 'Unlock delay';
  static const unlockTitle = 'Unlock when I return';
  static const unlockSubtitle =
      'Off by default. When on, the computer unlocks itself if your phone comes back after StepAway locked it.';
  static const unlockWarningTitle = 'Turn on automatic unlock?';
  static const unlockWarningBody =
      'Bluetooth distance can be tricked by relay devices. Anyone who can carry your phone\'s signal near this computer could unlock it. StepAway only unlocks a lock it created itself, and never right after a restart. Keep this off if the computer holds sensitive data.';
  static const turnOn = 'Turn on';
  static const autostartTitle = 'Start StepAway when I log in';
  static const autostartSubtitle =
      'Keeps protection running in the background even when this window is closed.';
  static const calibrationIntro =
      'Calibration makes distance estimates match your room. It takes two 10-second measurements.';
  static const calibNear =
      'Step 1: hold your phone about 0.5 m from the computer, then press start. The measurement begins after 5 seconds.';
  static const calibFar =
      'Step 2: press start, then walk to the spot where you want the computer to lock (the lock distance in Settings, 3 m by default) and hold your phone there. The measurement begins after 5 seconds.';
  static const startMeasure = 'Start measurement';
  static const measuring = 'Measuring...';
  static const calibDone = 'Calibration saved.';
  static const again = 'Calibrate again';
  static const notCalibratedTitle = 'Distance is not calibrated yet';
  static const notCalibratedBody =
      'Until you calibrate, distances are only a rough guess, so locking may happen much later than the distance you set. It takes about a minute.';
  static const calibrateNow = 'Calibrate now';
  static const getReady = 'Get into position... measuring starts in';
  static const seconds = 's';
  static const saved = 'Saved';
  static const appearance = 'Appearance';
  static const theme = 'Theme';
  static const themeSystem = 'System';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const distanceSection = 'Distance and timing';
  static const behaviorSection = 'Behaviour';
  static const connected = 'Connected';
  static const disconnected = 'Service stopped';
  static const signal = 'Signal';
  static const phone = 'Phone';
  static const protectionLabel = 'Protection';
  static const detected = 'Detected';
  static const notDetected = 'Not detected';
  static const active = 'Active';
  static const distanceOverTime = 'Distance over time';
  static const minimize = 'Minimise';
  static const maximize = 'Maximise';
  static const restore = 'Restore';
  static const close = 'Close';
  static const dashboardSubtitle = 'Live view of your phone and this computer';
  static const devicesSubtitle =
      'Phones that can lock and unlock this computer';
  static const settingsSubtitle = 'Tune distance, delays and behaviour';
  static const calibrateSubtitle =
      'Teach StepAway what distance looks like in your room';
  static const step1 = 'Near';
  static const step2 = 'Far';
  static const lockActions = 'When it locks';
  static const pauseMediaTitle = 'Pause music and videos';
  static const pauseMediaSubtitle =
      'Everything that is playing (Spotify, YouTube in your browser, VLC and more) is paused the moment StepAway locks this computer.';
  static const resumeMediaTitle = 'Resume when I unlock';
  static const resumeMediaSubtitle =
      'Only what StepAway paused is resumed, never anything you stopped yourself.';
  static const servicesTitle = 'Services to stop';
  static const servicesSection = 'Services to stop';
  static const appsSection = 'Apps to close';
  static const servicesSubtitle =
      'Background services on this list are stopped when StepAway locks and, if you like, started again after you unlock.';
  static const noServices = 'No services on the list.';
  static const addService = 'Add service';
  static const restartServicesTitle = 'Start them again after unlock';
  static const mediaUnavailable =
      'Media control is not available on this system.';
  static const servicesUnavailable =
      'Service control is not available on this system.';
  static const pickService = 'Choose a service';
  static const searchServices = 'Search or type a name, e.g. syncthing.service';
  static const addManually = 'Add';
  static const noRunning = 'No running user services found.';
  static const invalidService = 'Use a name ending in .service';
  static const protectedService =
      'That service is needed by your desktop session';
  static const appsTitle = 'Applications';
  static const appsSubtitle =
      'Apps on this list are asked to quit the moment StepAway locks this computer, and can be opened again after you unlock.';
  static const appsWarning =
      'Closing an app can lose unsaved work. Apps are asked to quit politely, so most will offer to save first.';
  static const noApps = 'No apps on the list.';
  static const addApp = 'Add app';
  static const reopenAppsTitle = 'Open them again after unlock';
  static const appsUnavailable = 'App control is not available on this system.';
  static const pickApp = 'Choose an app';
  static const searchApps = 'Search apps';
  static const runningNow = 'Running';
  static const noAppsFound = 'No matching apps found.';
  static const invalidServiceWindows =
      'Use a service name: letters, digits, space and _ . - only';
  static const searchServicesWindows =
      'Search or type a service name, e.g. Spooler';
  static const device = 'Device';
  static const addDeviceTitle = 'What do you want to add?';
  static const addPhone = 'Phone';
  static const addPhoneSub = 'Pair with the StepAway app (secure, can unlock)';
  static const addTablet = 'Tablet';
  static const addTabletSub = 'Pair with the StepAway app (secure, can unlock)';
  static const addWatch = 'Smartwatch or band';
  static const addWatchSub = 'Wear OS watch or any Bluetooth watch or band';
  static const addOther = 'Other Bluetooth device';
  static const addOtherSub = 'Earbuds, trackers and more (lock only)';
  static const watchChoiceTitle = 'Smartwatch or band';
  static const watchApp = 'I have the StepAway app on my watch';
  static const watchAppSub = 'Pair securely like a phone';
  static const watchBluetooth = 'Track a Bluetooth watch or band';
  static const watchBluetoothSub =
      'Works with watches and bands that keep a fixed Bluetooth address. Lock only.';
  static const nearbyTitle = 'Choose a Bluetooth device';
  static const nearbyHelp =
      'Turn the device on and keep it close to this computer. It appears here within a few seconds.';
  static const nearbyEmpty = 'Looking for devices...';
  static const unnamedDevice = 'Unnamed device';
  static const lockOnlyBadge = 'Lock only';
  static const lockOnlyWarning =
      'This device can lock the computer when it moves away, but it can never unlock it, because a plain Bluetooth device cannot prove who it is. Some devices change their Bluetooth address from time to time; those will stop working.';
  static const nameThisDevice = 'Name';
  static const deviceType = 'Type';
  static const add = 'Add';
  static const rename = 'Rename';
  static const changeType = 'Change type';
  static const multiDeviceTitle = 'Several devices';
  static const ruleAny = 'Any device';
  static const ruleAll = 'All devices';
  static const ruleAnyHelp =
      'You count as near while at least one of your devices is near. The computer locks when all of them are away.';
  static const ruleAllHelp =
      'You count as near only while every device is near. The computer locks as soon as any one leaves.';
  static const calibrateWhich = 'Device to calibrate';
  static const detectedCount = 'detected';
  static const beaconTitle = 'Show distance on my devices';
  static const beaconSubtitle =
      'Your phone, tablet or watch can show how far away this computer is. Uses a small signed Bluetooth beacon.';
  static const beaconUnavailable =
      'Bluetooth advertising is not available on this computer, so devices cannot show distance.';
  static const codeTitle = 'Pair with a code';
  static const codeInstruction =
      'On your watch, open StepAway and choose "Pair with a code". Type the 16 characters it shows here.';
  static const codeHint = 'XXXX-XXXX-XXXX-XXXX';
  static const codeStart = 'Start pairing';
  static const codeListening =
      'Listening for your watch... keep it close and the pairing screen open.';
  static const codeBad =
      'That code does not look right. It has 16 letters and digits.';

  static const about = 'About';
  static const aboutSubtitle = 'Version, license and privacy';
  static const privacyPolicy = 'Privacy policy';
  static const serviceVersion = 'Background service';
  static const serviceOlder = 'Older version (restart StepAway)';
  static const serviceNotRunning = 'Not running';

  // ---- uninstall ----
  static const uninstallSection = 'Uninstall';
  static const uninstallSubtitle =
      'Remove StepAway and everything it stored from this computer.';
  static const uninstallButton = 'Uninstall StepAway...';
  static const uninstallDialogTitle = 'Uninstall StepAway?';
  static const uninstallDialogBody =
      'This will remove StepAway from this computer:\n'
      '  \u2022 the app and the background service\n'
      '  \u2022 the startup entry and shortcuts';
  static const uninstallDeleteData =
      'Also delete paired devices, settings and logs';
  static const uninstallWarning =
      'This cannot be undone. This computer will stop locking when your phone moves away.';
  static const uninstallAdminNote =
      'You will be asked for your administrator password.';
  static const uninstallConfirm = 'Uninstall';
  static const uninstallingTitle = 'Removing StepAway...';
  static const uninstallingSubtitle = 'Please keep this window open.';
  static const uninstallingSubtitleAdmin =
      'Please keep this window open and enter your password if asked.';
  static const uninstallDoneTitle = 'StepAway has been removed';
  static const uninstallDoneData =
      'The app, the service and all your data are gone from this computer.';
  static const uninstallDoneKept =
      'The app and the service are gone. Your paired devices and settings were kept.';
  static const uninstallFailedTitle = 'Could not finish removing StepAway';
  static const uninstallPhoneHint =
      'Also remove this computer from the StepAway app on your phone.';
  static const uninstallDeferredHint =
      'The app folder is deleted a few seconds after you close this window.';
  static const uninstallDevNote =
      'This is a development copy, so the app files will be left in place.';

  static String uninstallStep(UninstallStep s) => switch (s) {
    UninstallStep.stopService => 'Stopping the background service',
    UninstallStep.appFiles => 'Removing the app',
    UninstallStep.autostart => 'Removing the startup entry',
    UninstallStep.shortcuts => 'Removing shortcuts',
    UninstallStep.data => 'Deleting paired devices, settings and logs',
  };

  static const phoneUnlockedTitle = 'Only when my phone is unlocked';
  static const phoneUnlockedSubtitle =
      'Extra safety: the computer only unlocks while your phone screen is unlocked too, so a phone locked in a stranger\'s hand or pocket cannot open it.';

  // ---- health check ----
  static const healthTitle = 'Health check';
  static const healthAllGood = 'Everything is set up';
  static String healthIssues(int n) =>
      n == 1 ? '1 thing needs attention' : '$n things need attention';
  static const hServiceOk = 'Background service is running';
  static const hServiceBad = 'The background service is not running';
  static const hServiceFix =
      'Press "Start service" at the top, or restart StepAway.';
  static const hScanOk = 'Bluetooth is scanning';
  static const hScanBad = 'Bluetooth scanning is not active';
  static const hScanFix = 'Turn Bluetooth on, then restart StepAway.';
  static const hPairedOk = 'A device is paired';
  static const hPairedBad = 'No device is paired';
  static const hPairedFix = 'Open Devices and add your phone.';
  static const hSignalOk = "Your device's signal is being received";
  static const hSignalBad = 'No signal from your device';
  static const hSignalFix =
      'Open StepAway on the phone, switch protection on and keep Bluetooth on.';
  static const hCalibOk = 'Distance is calibrated';
  static const hCalibBad = 'Distance is not calibrated yet';
  static const hCalibFix = 'Run Calibrate once for accurate distances.';
  static const hActiveOk = 'Protection is active';
  static const hActiveBad = 'Protection is paused';
  static const hActiveFix = 'Press "Resume protection".';
  static const hUnlockReady = 'Unlock is ready';
  static const hUnlockOff = 'Unlock is switched off (lock only)';
  static const hUnlockOffFix =
      'Turn on unlock in Settings if you want the computer to open when you return.';
  static const hUnlockFirstLogin = 'Unlock waits until you have signed in once';
  static const hUnlockFirstLoginFix =
      'For safety StepAway never unlocks right after the computer starts. Sign in with your password once.';
  static const hUnlockNotOurLock = 'The screen was locked by something else';
  static const hUnlockNotOurLockFix =
      'StepAway only unlocks a lock it made itself. Sign in manually this time.';
  static const hUnlockTooFar = 'Your device is not close enough yet';
  static const hUnlockTooFarFix = 'Come within the "counts as back" distance.';
  static const hUnlockPhoneLocked = 'Waiting for you to unlock your phone';
  static const hUnlockPhoneLockedFix =
      'Unlock the phone screen so it can confirm it is you, or turn this safety rule off in Settings.';
  static const hUnlockGrace = 'Waiting a moment to be sure you are back';
  static const hUnlockGraceFix = 'Stay close for a second or two.';
  static const hUnlockAuth = 'Waiting for a fresh signed signal from the phone';
  static const hUnlockAuthFix =
      'The phone sends a new one every few seconds. If this stays, check that protection is on in the phone app.';
}
