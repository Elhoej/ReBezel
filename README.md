# Lumens

Brings the classic centred volume/brightness bezel back on macOS 26+ (Tahoe and later),
where Apple moved the indicator to a banner in the top-right corner.

## How it works

Since Tahoe the indicator is drawn by Control Center itself (not the old `OSDUIHelper`
process), so it cannot be killed or frozen the way SlimHUD used to. Instead, Lumens:

1. Installs a `CGEventTap` for system-defined key events and **swallows** the volume,
   mute and brightness keys before Control Center ever sees them.
2. Applies the change itself: volume through CoreAudio, built-in display brightness
   through the private `DisplayServices` framework.
3. Draws its own bezel: a click-through panel centred near the bottom of the active screen.

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
open Lumens.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Lumens.xcodeproj -scheme Lumens -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Lumens.app
```

If `xcodebuild` complains about the Command Line Tools, point it at Xcode:
`export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer`.

Lumens is a menu bar app (no Dock icon). The menu bar icon shows a warning triangle
until Accessibility permission is granted; use **Retry Event Tap** from its menu afterwards.

The icon can be hidden with **Hide Menu Bar Icon…**. To bring it back (or to quit), open
Lumens again from Finder, Spotlight or Launchpad while it is running. When running from
Xcode, launch with the `--show-menu-bar-icon` argument instead (Edit Scheme → Run →
Arguments). The icon always
stays visible while the event tap is not running, so the Accessibility warning cannot be hidden.

## Debugging

```sh
log stream --predicate 'subsystem == "com.simonelhoej.Lumens"' --level info
```

## Spike status

The first thing to validate is that swallowing the key events really stops the native
banner. If the banner still appears, change the tap location in `MediaKeyTap.swift`
from `.cgSessionEventTap` to `.cghidEventTap`.
