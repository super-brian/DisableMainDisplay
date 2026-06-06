# Display Control

A simple macOS app to disable the MacBook's built-in display when using external monitors. Useful if your laptop screen is broken or you simply prefer using only external displays with the lid open.

## How It Works

- **Mirrors** the built-in display onto an external display (removing it from the desktop arrangement)
- **Sets brightness to 0** via Apple's DisplayServices framework (turns off the backlight)
- **Restores everything** when you re-enable — removes mirroring and restores brightness

The external display keeps its native resolution and arrangement.

## Features

- **Disable / Enable buttons** for manual control
- **Two modes** (persistent between launches):
  - **Keep main display off** — always disables the built-in display; only the manual Enable button turns it back on
  - **Only while external display is connected** — auto-disables when an external is plugged in, auto-re-enables when all externals are removed
- **Auto-disable on launch** if an external display is connected
- **Handles hot-plug** — plugging/unplugging external monitors re-applies the correct state
- **Multiple external monitors** supported — mirrors onto whichever external is available
- **Window stays on external display** — never opens on the broken built-in screen
- **Single instance** — launching again brings the existing window to front
- **Safety** — re-enables built-in display when the app quits

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon Mac

## Build & Install

Just run:

```bash
zsh build_app.sh
```

This is the only command you need. It runs `swift build -c release`, creates `DisplayControl.app` with the icon and Info.plist, and ad-hoc signs it — all in one step.

If you only want the raw binary without the `.app` bundle:

```bash
swift build -c release
# Binary at .build/release/DisableMainDisplay
```

## Install

Copy `DisplayControl.app` to `/Applications` or anywhere you like. On first launch, right-click → Open → Open to bypass Gatekeeper.
