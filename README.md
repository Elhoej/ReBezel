<p align="center">
  <img src="docs/images/bezel.png" alt="ReBezel's volume bezel in Liquid Glass, centered over a colorful desktop" width="720">
</p>

# ReBezel

The volume and brightness bezel from before macOS Tahoe, redrawn in Liquid Glass to match macOS 26.

Tahoe replaced the old bezel with a small banner in the top-right corner. ReBezel brings back the
square in the middle of the screen, with the large glyph and 16-segment level bar, made of the same
glass as the rest of the system.

**[Download ReBezel](https://github.com/Elhoej/ReBezel/releases/latest)** (macOS 26 or later)

<a href='https://ko-fi.com/W7W0NZDCC' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi6.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

## Styles

<p align="center">
  <img src="docs/images/styles.png" alt="The three bezel styles side by side: Classic, Liquid Glass Regular and Liquid Glass Clear" width="720">
</p>

From left: Classic, Liquid Glass (Regular) and Liquid Glass (Clear). Regular is frosted and follows
the Liquid Glass tint set in System Settings. Clear is the transparent glass Control Center uses.
Classic is the dark bezel from macOS 11 to 15.

The bezel sits near the bottom of the screen by default and can move to the center or top. It shows
on the screen with the pointer, or on every screen.

## Keys and shortcuts

The volume, mute and brightness keys work as before, and the old modifiers are back:

- Shift+Option with a volume or brightness key changes the level in quarter steps.
- Option with a volume or brightness key opens Sound or Displays settings.
- Control with a brightness key changes the brightness of a connected Apple Studio Display, Pro
  Display XDR or LG UltraFine.

DDC monitors and the keyboard backlight keys aren't supported.

On a Mac with a Touch Bar, the bezel also shows for the Touch Bar's volume and brightness controls,
and for volume changes made elsewhere, such as in Control Center. macOS still shows its banner for
those, so you'll see both. Turn this off in Settings under Show for Touch Bar controls.

When AirPods or other Bluetooth headphones connect and the sound moves to them, the bezel shows
their name. macOS shows its banner for this too. Turn this off in Settings under Show when
headphones connect.

ReBezel runs from the menu bar with no Dock icon. It can start at login, and you can hide the menu bar
icon; open the app again from Finder or Spotlight to get it back.

## Setup

1. [Download the DMG](https://github.com/Elhoej/ReBezel/releases/latest) and drag ReBezel into
   Applications.
2. Open it. A short walkthrough previews each style and position.
3. Grant Accessibility access when asked.

Control Center draws the Tahoe banner and has no setting to turn it off. Accessibility access lets
ReBezel catch the volume and brightness keys first, change the level itself and show its own bezel.
Until you grant it, the menu bar icon shows a warning triangle. Choose Settings… (⌘,) from the menu
bar icon to change the bezel.

## Troubleshooting

If you used a build older than 1.1.0, install the latest DMG by hand and grant Accessibility access
again. Later updates install from inside the app and keep the permission.

If ReBezel's entry in the Accessibility list gets stuck, reset it and grant access again:

```sh
tccutil reset Accessibility com.simonelhoej.ReBezel
```

## Building from source

Build instructions, how key interception works and the release process are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

<a href='https://ko-fi.com/W7W0NZDCC' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi6.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
