# DisableMainDisplay

DisableMainDisplay is a small macOS utility for using a MacBook with external
displays while keeping the built-in display out of the way.

It can mirror the built-in display onto an external display, set the built-in
display brightness to zero, and restore the built-in display when needed.

## App Behavior

The app has three mode options:

- **Keep main display off**: keeps the built-in display disabled, even without
  an external display.
- **Only while external is connected**: disables the built-in display when an
  external display is connected, and enables it when no external display is
  connected.
- **Manual only**: used after pressing Disable or Enable; no automatic changes.

The selected mode is saved and restored on the next launch (default is
**Only while external is connected**). After login/reboot, the saved automatic
mode is retried for several seconds while displays settle.

On quit, the app switches to **Only while external is connected** and applies
that policy before closing:

- If an external display is connected, the built-in display is left disabled.
- If no external display is connected, the built-in display is re-enabled.

### Window and menu bar

- The red close button hides the window; the app keeps running in the menu bar.
- Use **Quit** in the window, or **Quit DisableMainDisplay** in the menu bar
  menu, to exit.
- Clicking the Dock icon reopens the window.

### Open at Login

- **Open at Login** registers a macOS login item (on by default).
- For a stable login path after Xcode builds, open
  `/Applications/DisableMainDisplay.app` (the post-build symlink) once so the
  login item points at that location.
- macOS may require approval under System Settings → General → Login Items.

## Features

- Manual Disable and Enable buttons (switch mode to Manual only).
- Automatic mode policies, including hot-plug handling.
- Launch retries while external displays appear after reboot.
- Window placement on an external display when one is available.
- Menu bar status item; single-instance behavior.
- Open at Login via ServiceManagement.
- Xcode build post-action symlinks the app into Applications.
- App icon and plist packaging through shell scripts.

## Requirements

- macOS 13 Ventura or later.
- Apple Silicon Mac.
- Xcode command line tools for building or signing.

## Scripts

### Xcode post-action: `scripts/symlink-app-to-applications.sh`

After an Xcode build, the shared scheme runs this script to create:

```text
/Applications/DisableMainDisplay.app  →  (Xcode build product)
```

If `/Applications` is not writable, it uses `~/Applications` instead.

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

Both packaging scripts create the same app bundle name in the repo root:

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
open /Applications/DisableMainDisplay.app
```

or the repo bundle:

```bash
open DisableMainDisplay.app
```

On first launch, macOS may require right-clicking the app and choosing Open.
