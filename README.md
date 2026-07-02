# VibeForge Display

**Shape your screens. Route your workspace.**

VibeForge Display is a macOS menu bar utility that helps you create virtual screens, inspect connected displays, save setup Modes, and build utility Surfaces. It's designed for Mac users with broken screens, multi-TV setups, and anyone who needs more display flexibility.

Part of the [VibeForge](https://github.com/iMMerSiveTechs) tool family.

---

## The Problem It Solves

If you have an M1 Mac that only supports 1 external display, VibeForge Display creates **virtual screens** that macOS treats as real monitors. This lets you:
- Use 2+ TVs as extended displays on hardware-limited Macs
- Keep working when your built-in screen is broken
- Save and restore multi-display setups with one click

---

## Features

### Virtual Screens (Core Feature)
- Create virtual displays that appear in macOS System Settings > Displays
- Configure resolution (720p to 4K), refresh rate, and HiDPI scaling
- Auto-create on app launch so your setup is ready immediately
- Activate/deactivate virtual screens on demand

### Screens
- View connected displays and their current configuration
- See resolution, refresh rate, scale factor, and available modes
- Auto-refreshes when displays change

### Modes
- Save repeatable desk setups as named presets
- Switch back faster when your screen arrangement changes
- Partial restore with clear reporting of what's available vs. what needs manual action

### Surfaces
- Create app-managed utility workspaces with notes, timers, checklists, and link cards
- Borderless, resizable windows with opacity control and always-on-top
- Widget data persists across app restarts

### Logs
- Track screen changes, virtual display events, and system activity
- Diagnostics cards showing system health at a glance

---

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16+**
- **Apple Silicon Mac** (M1, M2, M3, M4)

---

## Setup — Step by Step (for Xcode beginners)

### 1. Install Xcode (if you haven't already)

Open the **App Store** on your Mac, search for **Xcode**, and install it. It's free but large (~12 GB). After installation, open Xcode once and accept the license agreement.

### 2. Install Homebrew (if you haven't already)

Open **Terminal** (find it in Applications > Utilities) and paste:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the prompts. When it finishes, it may tell you to run two more commands — run those too.

### 3. Install XcodeGen

In Terminal, run:

```bash
brew install xcodegen
```

### 4. Clone this repo

In Terminal, navigate to where you want the project and run:

```bash
git clone https://github.com/iMMerSiveTechs/VibeForge-Display.git
cd VibeForge-Display
```

### 5. Generate the Xcode project

```bash
cd VibeForgeDisplay
xcodegen generate
```

You should see: `Generated project VibeForgeDisplay.xcodeproj`

### 6. Open in Xcode

```bash
open VibeForgeDisplay.xcodeproj
```

Or double-click the `.xcodeproj` file in Finder.

### 7. Set up code signing

In Xcode:
1. Click on **VibeForgeDisplay** in the left sidebar (the blue project icon at the top)
2. Click the **Signing & Capabilities** tab
3. Check **"Automatically manage signing"**
4. Under **Team**, select your Apple ID (or click "Add Account" to sign in with your Apple ID)
5. If you see "Sign to Run Locally" — that's fine for development

### 8. Build and Run

1. Make sure the target at the top says **VibeForgeDisplay** and **My Mac**
2. Press **Cmd+R** (or click the Play button)
3. The app will build and a menu bar icon will appear (top-right of your screen)
4. Click the menu bar icon to see the dropdown
5. Click "Open VibeForge Display" to see the full app window

### 9. Using Virtual Screens

1. Go to the **Virtual Screens** tab
2. Click **Add Virtual Screen**
3. Choose a resolution (1080p is a good start for TVs)
4. Click **Create & Activate**
5. Open **System Settings > Displays** — you should see the new virtual display
6. Arrange it next to your TV, and your desktop extends to it

### Troubleshooting

- **"VibeForgeDisplay" cannot be opened because the developer cannot be verified**: Go to System Settings > Privacy & Security, scroll to the bottom, and click "Open Anyway" (the old right-click → Open trick was removed in macOS Sequoia). Since you build it yourself in Xcode, you normally won't hit this.
- **Screen Recording permission prompt**: Routes (streaming) needs Screen Recording permission. Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch the app.
- **Build errors about signing**: Make sure you selected a Team in Signing & Capabilities
- **No menu bar icon**: The app runs as a menu bar app (no dock icon). Look in the top-right of your screen
- **Virtual display doesn't appear**: Make sure you're running macOS 14+ (check Apple menu > About This Mac)

---

## Project Structure

```
VibeForgeDisplay/
├── Sources/
│   ├── App/                          # App entry point, state, constants
│   ├── Bridge/                       # Objective-C bridging header for CGVirtualDisplay
│   ├── Core/
│   │   ├── Models/                   # ScreenInfo, Mode, VirtualScreenConfig, etc.
│   │   ├── Services/                 # Screen, Mode, Surface, VirtualDisplay, Log services
│   │   └── Persistence/             # JSON file persistence
│   ├── Features/
│   │   ├── MenuBar/                  # Menu bar dropdown
│   │   ├── Screens/                  # Physical display inspector
│   │   ├── VirtualDisplays/         # Virtual screen creation and management
│   │   ├── Modes/                    # Profile save/load/delete
│   │   ├── Surfaces/                # Utility workspace windows + widgets
│   │   └── Logs/                    # Diagnostics and event log
│   └── UI/
│       ├── Components/              # Shared UI components
│       └── Theme/                   # Colors, typography, spacing
├── Resources/
│   └── Assets.xcassets/             # App icon
├── Info.plist                       # Menu bar app config (LSUIElement=true)
└── project.yml                      # XcodeGen project specification
```

## Tech Stack

- Swift / SwiftUI / AppKit
- CoreGraphics (CGVirtualDisplay for virtual screens, Quartz Display Services for enumeration)
- `@Observable` / `@MainActor` patterns (Swift 6)
- JSON persistence via `Codable`
- No third-party dependencies

---

## How It Works

### Virtual Screens
VibeForge Display uses macOS's `CGVirtualDisplay` API to create virtual monitors. These appear to macOS as real displays — they show up in System Settings > Displays, and you can arrange them, set resolutions, and extend your desktop to them. This is the same approach used by tools like BetterDisplay and FreeDisplay.

### Limitations
- Virtual screens are created via macOS display APIs, not hardware drivers
- Whether they bypass M1's 1-display limit depends on your specific macOS version
- This is NOT a hardware hack — it works within macOS capabilities
- **Routes streams over VibeForge's own transport (LL-HLS), not Apple AirPlay.** AirPlay's sender protocol is closed and single-target; no third-party app can emit AirPlay to multiple TVs. Routes achieves the same result (wireless, different content per TV) a different way.

---

## Routes — streaming a screen to a TV

The **Routes** tab streams a virtual screen over your local network so any TV can show it:

1. Create a **Virtual Screen** (Virtual Screens tab).
2. In **Routes**, add a route pointing at that virtual screen, pick a quality, and press **Start**.
3. On the TV/phone, either open the shown link in a browser or scan the QR code.

Two kinds of receiver:
- **Any browser device** (phones, laptops, smart TVs, Fire/Google TV sticks): just open the link — nothing to install.
- **Apple TV** (no browser): install the **VibeForge Receiver** tvOS app (below). It auto-finds your Mac via Bonjour and plays the stream with AVPlayer.

### Building the Apple TV receiver

The tvOS receiver is a second target in the same project.

1. Run `xcodegen generate` (it now creates both the Mac app and `VibeForge Receiver`).
2. In Xcode, select the **VibeForge Receiver** scheme and your Apple TV as the run destination (pair the Apple TV via Xcode → Devices, or run in the tvOS Simulator first).
3. Set your signing Team on the receiver target (needs an Apple Developer account for install on real Apple TV hardware).
4. Run. On the Apple TV, pick your Mac, then the stream.

> Requires the Mac and Apple TV on the same Wi-Fi/LAN. The receiver talks plain HTTP on the local network (allowed via `NSAllowsLocalNetworking`).

---

## Roadmap

### Slice 1 (Done)
- [x] Menu bar app shell
- [x] Screen inspector with live refresh
- [x] Mode save/load/delete
- [x] Surface windows with widgets
- [x] Event logging and diagnostics

### Slice 1.5 (Done)
- [x] Virtual Screen creation via CGVirtualDisplay
- [x] Resolution presets (720p to 4K)
- [x] Auto-create on launch (with black-screen crash guard)

### Slice 2 (In progress)
- [x] Local streaming of virtual screens (LL-HLS over LAN)
- [x] Browser (web) receiver — any device with a browser
- [x] Apple TV (tvOS) receiver app with Bonjour discovery
- [x] Quality presets (Low / Balanced / High)
- [ ] Per-route live stats (fps / bitrate / dropped frames)
- [ ] Wall Presets (snapshot routes as one-click layouts)

### Slice 3 (Future)
- [ ] Window / Surface as a stream source (App-Store-safe, no private API)
- [ ] WebRTC transport for sub-second latency
- [ ] Audio streaming
- [ ] Automation / hotkeys

---

## License

Copyright 2025 VibeForge. All rights reserved.
