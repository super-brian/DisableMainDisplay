# DisableMainDisplay

DisableMainDisplay is a small macOS utility for using a MacBook with external
displays while keeping the built-in display out of the way.

It can mirror the built-in display onto an external display, set the built-in
display brightness to zero, and restore the built-in display when needed.

## App Behavior

The app has three radio options:

- **Keep main display off**: keeps the built-in display disabled, even without
  an external display.
- **Disable only while external display is connected**: disables the built-in
  display when an external display is connected, and enables it when no external
  display is connected.
- **Custom Mode**: used after pressing the manual Disable or Enable buttons.

On every launch, the app ignores the previously selected radio option and starts
in **Disable only while external display is connected** mode.

On quit, the app also applies that same mode before closing:

- If an external display is connected, the built-in display is left disabled.
- If no external display is connected, the built-in display is re-enabled.

This keeps the machine in a predictable state even if a different option was
selected during the last session.

## Features

- Manual Disable and Enable buttons.
- Automatic launch policy based on whether an external display is connected.
- Display hot-plug handling for external display changes.
- Window placement on an external display when one is available.
- Single-instance behavior: launching a second copy activates the existing app.
- App icon and plist packaging through shell scripts.

## Requirements

- macOS 13 Ventura or later.
- Apple Silicon Mac.
- Xcode command line tools for building or signing.

## Scripts

### `build_app.sh`

Builds a fresh release executable with SwiftPM and packages it as:

```text
DisableMainDisplay.app
```

Use this when you want a release app bundle:

```bash
cd /Users/hong/m/DisableMainDisplay
./build_app.sh
```

The script does the full release flow:

```text
swift build -c release
create DisableMainDisplay.app
copy Info.plist
copy AppIcon.icns
ad-hoc sign the app
```

You do not need to build in Xcode before running this script.

### `bundle_xcode_debug_app.sh`

Packages an existing Xcode Debug build into:

```text
DisableMainDisplay.app
```

This script does not compile. Build Debug in Xcode first, then run:

```bash
cd /Users/hong/m/DisableMainDisplay
./bundle_xcode_debug_app.sh
```

The script searches common Xcode DerivedData locations for the newest Debug
`DisableMainDisplay` executable. If it finds one, it deletes any existing
`DisableMainDisplay.app` in the repo root and creates a fresh app bundle.

You can also pass the Debug executable path explicitly:

```bash
./bundle_xcode_debug_app.sh /path/to/Build/Products/Debug/DisableMainDisplay
```

## App Bundle Name

Both scripts create the same app bundle:

```text
DisableMainDisplay.app
```

Running either script replaces any existing `DisableMainDisplay.app` in the
repo root.

The raw file named `DisableMainDisplay` is only the executable. It is not an app
bundle and will show Finder's generic executable icon.

## Launching

Open the app:

```bash
open DisableMainDisplay.app
```

On first launch, macOS may require right-clicking the app and choosing Open.
