# Developing ReBezel

## How it works

Since Tahoe the indicator is drawn by Control Center itself (not the old `OSDUIHelper`
process), so it cannot be killed or frozen the way SlimHUD used to. Instead, ReBezel:

1. Installs a `CGEventTap` for system-defined key events and swallows the volume,
   mute and brightness keys before Control Center ever sees them.
2. Applies the change itself: volume through CoreAudio, built-in display brightness
   through the private `DisplayServices` framework.
3. Draws its own bezel: a click-through panel on the active screen, with either an
   `NSVisualEffectView` (Classic) or an `NSGlassEffectView` (Liquid Glass) behind it.

Holding Shift+Option with a volume or brightness key moves in quarter-segment steps
(64 instead of 16). Holding just Option opens the Sound or Displays pane in System Settings.

Control with a brightness key changes an external display that macOS can control itself.
ReBezel picks the external display under the cursor, or the first supported one. With no
supported external display connected the key is passed to the system.

Keyboard backlight keys are passed through to the system untouched.

### Touch Bar

A Mac with a Touch Bar has no volume or brightness keys. The Control Strip
(`/System/Library/CoreServices/ControlStrip.app`) sets the levels itself, through CoreAudio and
`DisplayServicesSetBrightnessWithType(display, value, 1)`, and asks `SystemBanner` for the
banner directly, so the event tap never sees a key and the banner can't be suppressed.
`LevelChangeObserver` watches the levels instead: CoreAudio property listeners on the default
output device for volume and mute, and `DisplayServicesRegisterForBrightnessChangeNotifications`
for the primary display.

Auto-brightness notifies about every 10 ms in steps of ~0.00015, and the system's type 2 sets
in steps under ~0.0025. A type 1 set (the Control Strip, the keys) arrives as one notification.
So a brightness change shows the bezel when it moves at least 0.004 in one notification, or at
least 0.001 within a second of such a change (a slow slider drag). Changes are ignored while the
displays sleep, for 3 seconds after they wake, and after 30 seconds without any input (dimming
before display sleep).

This runs when Show for Touch Bar controls is on. Its default is on when
`com.apple.controlstrip` is running, which it only does on Macs with a Touch Bar. Changes ReBezel
makes from a key come back through the observer too and show the same level again.

## Requirements

- macOS 26 or later
- Xcode 27
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project
- Accessibility permission (System Settings → Privacy & Security → Accessibility).
  The event tap cannot be created without it.

## Building

The Xcode project is generated from `project.yml`:

```sh
xcodegen generate
open ReBezel.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project ReBezel.xcodeproj -scheme ReBezel -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/ReBezel.app
```

If `xcodebuild` complains about the Command Line Tools, point it at Xcode:
`export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer`.

To see the first-run walkthrough again:

```sh
defaults delete com.simonelhoej.ReBezel didCompleteOnboarding
```

When running from Xcode, the hidden menu bar icon can be brought back by launching with the
`--show-menu-bar-icon` argument (Edit Scheme → Run → Arguments). The icon always stays
visible while the event tap is not running, so the Accessibility warning cannot be hidden.

## Updates

ReBezel updates itself with [Sparkle](https://sparkle-project.org). The feed is `appcast.xml`
on `main`, served from `https://raw.githubusercontent.com/Elhoej/ReBezel/main/appcast.xml`
(`SUFeedURL` in `project.yml`). The zips it points to are assets of the GitHub releases, so the
repository has to be public. Debug builds never check on their own; Check for Updates… still
works in them.

## Releasing

Write the release notes in Markdown as `release-notes/<version>.md` and commit them, then:

```sh
Scripts/release.sh 1.2.0
```

From a clean `main` that is up to date with `origin`, this:

1. sets `MARKETING_VERSION` to the given version and raises `CURRENT_PROJECT_VERSION` by one
   in `project.yml` (and runs `xcodegen generate`),
2. archives a Release build, signs it with the Developer ID certificate, and notarizes and
   staples both the app and a DMG, then makes a zip of the app,
3. signs the zip with the Sparkle key and adds it to the top of `appcast.xml`, with the release
   notes embedded,
4. commits everything as `Release 1.2.0 (<build>)`, tags it `v1.2.0`, pushes the tag, creates the
   GitHub release with the DMG and zip, and finally pushes `main`, which is when the update
   goes live.

If anything fails before the commit, the version bump and appcast change are undone. If it
fails after, the error says which commands are left to run.

Without a version, `Scripts/release.sh` only builds the current version into `build/release/`
(`ReBezel-<version>.dmg` and `.zip`) and changes or publishes nothing.
`SKIP_NOTARIZE=1 Scripts/release.sh` signs and packages without uploading to Apple.

### One-time setup

- A Developer ID Application certificate in the keychain (Xcode → Settings → Accounts →
  Manage Certificates).
- Notarization credentials stored under the `rebezel-notary` keychain profile, using an
  app-specific password from appleid.apple.com:

  ```sh
  xcrun notarytool store-credentials rebezel-notary --apple-id <apple-id> --team-id SPRLQ9JET8
  ```

- The Sparkle EdDSA signing key in the login keychain. Its public half is `SUPublicEDKey` in
  `project.yml`, and the script refuses to publish if the two don't match. Sparkle's tools are
  in `build/SourcePackages/artifacts/sparkle/Sparkle/bin` once packages are resolved
  (`Scripts/release.sh` does this, or
  `xcodebuild -resolvePackageDependencies -scheme ReBezel -clonedSourcePackagesDirPath build/SourcePackages`).
  Back the private key up; without it no update can reach existing users:

  ```sh
  build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
  ```

  Store that file in a password manager and delete it. On a new Mac, import it with
  `generate_keys -f sparkle-private-key.txt`.
- `gh auth login`, with access to push to and create releases in `Elhoej/ReBezel`.

Accessibility permission is tied to the code signature, so the Developer ID build needs it
granted again even if a debug build already has it. Updates are signed the same way, so they
keep it.

## README images

The images in `docs/images` are real bezels captured on screen by
`Scripts/capture-readme-image.swift`; its header has the commands. It needs Screen Recording
permission for the terminal.

## Debugging

```sh
log stream --predicate 'subsystem == "com.simonelhoej.ReBezel"' --level info
```

If the native banner ever shows up next to the bezel, change the tap location in
`MediaKeyTap.swift` from `.cgSessionEventTap` to `.cghidEventTap`, which sits earlier in the
event stream.
