<p align="center">
 <img alt="Battery Toolkit logo" src="Resources/LogoCaption.png" width=500 align="center">
</p>

<p align="center">
  <b>Battery Toolkit for macOS 27 (Golden Gate) & Apple Silicon Macs</b><br>
  Control platform power state, battery charging thresholds, and adapter isolation on Apple Silicon (M1/M2/M3/M4).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-27.0%20(Golden%20Gate)-blue.svg" alt="macOS 27">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange.svg" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6.0-green.svg" alt="Swift 6">
  <img src="https://img.shields.io/badge/License-BSD--3--Clause-lightgrey.svg" alt="License">
</p>

<p align="center">
  <a href="#about-this-fork">About this Fork</a> &bull;
  <a href="#key-fixes--improvements">Key Improvements</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#installation--building">Installation & Build</a> &bull;
  <a href="#usage">Usage</a> &bull;
  <a href="#troubleshooting">Troubleshooting</a> &bull;
  <a href="#credits">Credits</a>
</p>

---

# About this Fork

This repository is a specialised fork of [Marvin Häuser's Battery Toolkit](https://github.com/mhaeuser/Battery-Toolkit), adapted and updated to run seamlessly on **macOS 27 (Golden Gate)** and Apple Silicon Macs (including **Apple M2, M3, and M4** chips).

The original project was designed for earlier macOS versions and encountered incompatibilities with Xcode 27 toolchains, macOS 27 SMC firmware key layouts, and `SMAppService` launchd changes. This fork resolves those issues, providing a stable, native, and responsive background battery manager.

---

# Key Fixes & Improvements

### 1. macOS 27 Firmware SMC Adaptation ("Machine is Unsupported" Fix)
- **Problem**: In macOS 27 on Apple Silicon M2, legacy SMC keys `CH0C` and `CHTE` are absent in firmware. In the original version, this caused `SMCComm.Power.supported()` to fail, logging `Machine is unsupported` and disabling all controls.
- **Solution**: Added support for hardware adapter control via **`CHIE`** (*Charger Inhibit Enable*), allowing macOS 27 M2 systems to be recognized and supported without crashing or throwing unsupported platform exceptions.

### 2. Elimination of Launch & XPC Deadlocks
- **Problem**: In macOS 27, unmanaged XPC calls during launchd service bootstrap could block indefinitely on unresponsive helpers, freezing `applicationDidFinishLaunching` and preventing the menu bar item from ever appearing.
- **Solution**: Wrapped all daemon XPC client interactions in [BTDaemonXPCClient.swift](BatteryToolkit/BTDaemonXPCClient.swift) with defensive `withTimeout` guards and thread-safe `SafeContinuation` wrappers.

### 3. Immediate Menu Bar Icon Display
- **Problem**: The status item (`NSStatusItem`) was previously deferred until after multiple asynchronous background service registrations completed.
- **Solution**: The status icon (battery with lightning bolt ⚡) is instantiated immediately upon launch in [BTAppDelegate.swift](BatteryToolkit/Views/Main/BTAppDelegate.swift), ensuring immediate visual feedback in the top menu bar.

### 4. SMAppService & Launchd Registration
- **Problem**: `SMAppService.daemon` failed on macOS 27 due to missing ownership associations.
- **Solution**: Configured `<key>AssociatedBundleIdentifiers</key>` in `me.mhaeuser.batterytoolkitd.plist` so that `launchd` and Background Task Management cleanly associate the background helper daemon with the front-end application.

### 5. Protected Continuous Charging Logic
- **Problem**: When charge gating was active on M2, turning off charging via `CHIE` cut off AC adapter power entirely, leaving the laptop discharging on battery while plugged into the wall.
- **Solution**: Separated power adapter hardware isolation from battery charge monitoring. Disabling the adapter only occurs when explicitly commanded by the user, and the daemon ensures the power adapter is actively drawing power upon connection.

### 6. Modern Toolchain Compatibility
- Updated `MACOSX_DEPLOYMENT_TARGET` from `11.0` to `13.0` (required by Xcode 27).
- Configured Swift 6 explicit module include paths (`NSXPCConnection+AuditToken`, `SMCParamStruct`).
- Configured code-signing entitlements for local Apple Developer certificates.

---

# Features

- **Upper Charge Limit**: Set a maximum battery percentage (e.g. 80%). Charging halts once this threshold is reached, reducing battery degradation.
- **Lower Discharge Limit / Hysteresis**: Configure a minimum threshold (e.g. 70–75%) below which charging will automatically re-engage.
- **Hardware Power Adapter Isolation**: Manually disable or enable the power adapter via SMC (`CHIE`) to discharge the battery for calibration without physically unplugging the cable.
- **Quick Menu Bar Extra**: Click the lightning battery icon (⚡) on your top menu bar for instant actions:
  - *Charge to Limit Now*
  - *Charge to Full Now (100%)*
  - *Disable Charging*
  - *Disable / Enable Power Adapter*
  - *Settings…*
  - *Pause / Resume Activity*
- **Background Daemon**: Operates as a lightweight, low-overhead system daemon (`me.mhaeuser.batterytoolkitd`) using IOPowerManagement notifications.

|<img alt="Menu Bar Commands" src="Resources/MenuBarCommands.png" width=260>|<img alt="Power Settings" src="Resources/PowerSettings.png" width=520>|
|:---:|:---:|
| *Menu Bar Extra (Quick Commands)* | *Settings Window* |

---

# Installation & Building

### Prerequisites
- Apple Silicon Mac (M1, M2, M3, M4 or later)
- macOS 13.0 or later (fully verified on **macOS 27.0 Golden Gate**)
- Xcode 15+ / Xcode 27+ with Command Line Tools

### Clone the Repository
```bash
git clone https://github.com/diegonoceli/Battery-Toolkit-MacOs-27.git
cd Battery-Toolkit-MacOs-27
```

### Build from Source
To build a signed Release binary with your local developer identity:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project "Battery Toolkit.xcodeproj" \
           -scheme "Battery Toolkit" \
           -configuration Release build
```

### Install to Applications Folder
```bash
# Safely replace any existing version to preserve code signatures
rm -rf "/Applications/Battery Toolkit.app"
cp -R ~/Library/Developer/Xcode/DerivedData/Battery_Toolkit-*/Build/Products/Release/"Battery Toolkit.app" /Applications/

# Open the app
open "/Applications/Battery Toolkit.app"
```

---

# Usage

1. **Open the App**: Launch `Battery Toolkit` from `/Applications`.
2. **Locate the Menu Bar Icon**: Look for the battery icon with a lightning bolt (⚡) in the top-right corner of your macOS menu bar (next to the clock and Control Centre).
3. **Turn off macOS Optimized Charging**:
   - Go to `System Settings` > `Battery`.
   - Click the **(i)** next to *Battery Health*.
   - Toggle **Optimized Battery Charging** to **Off** to prevent interference with Battery Toolkit's threshold controller.
4. **Access Settings**: Click the menu bar icon > **Settings…** to configure your preferred minimum and maximum charge percentages.

---

# Troubleshooting

### Duplicate Icon in Launchpad / Spotlight
If a previous Xcode build was indexed by macOS LaunchServices, clean up the duplicate registration by running:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Battery Toolkit.app"
killall Dock
```

### Machine shows "Discharging" when plugged into power
Click the Battery Toolkit icon in the menu bar and select **Enable Power Adapter** or **Charge to Full Now**. The app will immediately send `0x00` to SMC key `CHIE`, restoring wall power input.

### Uninstalling
To cleanly uninstall the application and its background helper daemon:
1. Open the Battery Toolkit menu from the menu bar.
2. Select **Disable Background Activity** (this de-registers the daemon from `launchd`).
3. Quit the app and drag `/Applications/Battery Toolkit.app` to the Trash.

---

# Credits & Acknowledgements

- Original author: **Marvin Häuser** ([@mhaeuser](https://github.com/mhaeuser)) & contributors.
- Original repository: [mhaeuser/Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit).
- macOS 27 Golden Gate port, Apple Silicon M2 firmware SMC updates, and launch stability by **Diego Noceli** ([@diegonoceli](https://github.com/diegonoceli)).

# License

Distributed under the [BSD 3-Clause License](LICENSE.txt).
