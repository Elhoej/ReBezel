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

All options (bezel position and style, show on all screens, launch at login, hiding the
menu bar icon) live in the **Preferences…** window (⌘, from the menu).

The icon can be hidden with **Hide Menu Bar Icon…** in Preferences. To bring it back (or to quit), open
ReBezel again from Finder, Spotlight or Launchpad while it is running. When running from
Xcode, launch with the `--show-menu-bar-icon` argument instead (Edit Scheme → Run →
Arguments). The icon always
stays visible while the event tap is not running, so the Accessibility warning cannot be hidden.

## Debugging

```sh
log stream --predicate 'subsystem == "com.simonelhoej.ReBezel"' --level info
```

## Spike status

The first thing to validate is that swallowing the key events really stops the native
banner. If the banner still appears, change the tap location in `MediaKeyTap.swift`
from `.cgSessionEventTap` to `.cghidEventTap`.
