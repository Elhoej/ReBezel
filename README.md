# ReBezel

Brings the classic centred volume/brightness bezel back on macOS 26+ (Tahoe and later),
where Apple moved the indicator to a banner in the top-right corner.

## How it works

Since Tahoe the indicator is drawn by Control Center itself (not the old `OSDUIHelper`
process), so it cannot be killed or frozen the way SlimHUD used to. Instead, ReBezel:

1. Installs a `CGEventTap` for system-defined key events and **swallows** the volume,
   mute and brightness keys before Control Center ever sees them.
2. Applies the change itself: volume through CoreAudio, built-in display brightness
   through the private `DisplayServices` framework.
3. Draws its own bezel: a click-through panel centred near the bottom of the active screen.

Holding **Shift+Option** with a volume or brightness key moves in quarter-segment steps
(64 instead of 16), and the bezel fills the current segment a quarter at a time. Holding
just **Option** opens the Sound or Displays pane in System Settings, as it does natively.

Holding **Control** with a brightness key changes an external display instead, if macOS can
control it (Studio Display, Pro Display XDR, LG UltraFine; not third-party monitors over DDC).
It picks the external display under the cursor, or the first supported one, and shows the bezel
on that display. With no supported external display connected the key is passed to the system.

Keyboard backlight keys are currently passed through to the system untouched.

## Requirements

- macOS 26 or later
- Xcode 27
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project
- **Accessibility** permission (System Settings → Privacy & Security → Accessibility).
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

ReBezel is a menu bar app (no Dock icon). On first launch a short walkthrough lets you
pick a bezel style and position (previewed live) and then asks for Accessibility
permission. As soon as the permission is detected, a checkmark bezel saying "Voilá!"
confirms that everything works and the walkthrough closes. To see it again:

```sh
defaults delete com.simonelhoej.ReBezel didCompleteOnboarding
```

The menu bar icon shows a warning triangle until Accessibility permission is granted;
once it is, the event tap starts on its own and the icon changes back.

All options (bezel position and style, show on all screens, launch at login, automatic
update checks, hiding the menu bar icon) live in the **Preferences…** window (⌘, from the menu).

The icon can be hidden with **Hide Menu Bar Icon…** in Preferences. To bring it back (or to quit), open
ReBezel again from Finder, Spotlight or Launchpad while it is running. When running from
Xcode, launch with the `--show-menu-bar-icon` argument instead (Edit Scheme → Run →
Arguments). The icon always
stays visible while the event tap is not running, so the Accessibility warning cannot be hidden.

## Updates

ReBezel updates itself with [Sparkle](https://sparkle-project.org). The menu has **Check for
Updates…**, and Preferences has **Automatically check for updates**, which is on by default
(checked once a day). When an update is found, Sparkle's dialog shows the release notes and
lets the user install, skip or postpone it; nothing installs without asking.

The feed is `appcast.xml` on `main`, served from
`https://raw.githubusercontent.com/Elhoej/ReBezel/main/appcast.xml` (`SUFeedURL` in
`project.yml`). The zips it points to are assets of the GitHub releases, so the repository has
to be public. Debug builds never check on their own; **Check for Updates…** still works in them.

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

Users of a build from before Sparkle was added have to install one release by hand; after that
updates arrive through the app.

### One-time setup

- A **Developer ID Application** certificate in the keychain (Xcode → Settings → Accounts →
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
  **Back the private key up**; without it no update can reach existing users:

  ```sh
  build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
  ```

  Store that file in a password manager and delete it. On a new Mac, import it with
  `generate_keys -f sparkle-private-key.txt`.
- `gh auth login`, with access to push to and create releases in `Elhoej/ReBezel`.

Accessibility permission is tied to the code signature, so the Developer ID build needs it
granted again even if a debug build already has it. Updates are signed the same way, so they
keep it. If the entry gets stuck:
`tccutil reset Accessibility com.simonelhoej.ReBezel`.

## Debugging

```sh
log stream --predicate 'subsystem == "com.simonelhoej.ReBezel"' --level info
```

## Spike status

The first thing to validate is that swallowing the key events really stops the native
banner. If the banner still appears, change the tap location in `MediaKeyTap.swift`
from `.cgSessionEventTap` to `.cghidEventTap`.
