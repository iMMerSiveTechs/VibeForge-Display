# VibeForge Display

**Shape your screens. Route your workspace.**

VibeForge Display is a macOS menu bar utility for inspecting Screens, saving Modes, creating utility Surfaces, and routing them to TVs, iPads, and external displays.

Part of the [VibeForge](https://github.com/iMMerSiveTechs) tool family.

---

## What It Does

- **Screens** — View connected displays, current layout, and key display details
- **Modes** — Save repeatable desk setups and switch back faster when your screen arrangement changes
- **Surfaces** — Create app-managed utility workspaces for notes, timers, checklists, and reference panels
- **Logs** — Track screen changes, Mode actions, and system events

## Terminology

| Term | Meaning |
|------|---------|
| Screen | Real detected display |
| Mode | Saved setup preset |
| Surface | App-managed pseudo-workspace window |
| Route | Where a Surface is sent *(Slice 2)* |
| Stream | Live delivery of a Surface *(Slice 2)* |

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16+
- Apple Silicon Mac (recommended)

## Setup

### Option A: Using XcodeGen (Recommended)

1. Install XcodeGen: `brew install xcodegen`
2. Clone this repo
3. Navigate to the project root
4. Run: `cd VibeForgeDisplay && xcodegen generate`
5. Open `VibeForgeDisplay.xcodeproj`
6. Build & Run (Cmd+R)

### Option B: Manual Xcode Setup

1. Open Xcode → File → New → Project → macOS → App
2. Product Name: `VibeForgeDisplay`
3. Bundle Identifier: `com.vibeforge.display`
4. Interface: SwiftUI, Language: Swift
5. Set deployment target to macOS 14.0
6. Delete the default ContentView.swift
7. Drag the `Sources/` and `Resources/` folders into the project
8. Replace the generated Info.plist with the one in this repo
9. Build & Run

## Project Structure

```
VibeForgeDisplay/
├── Sources/
│   ├── App/                    # App entry point, state, constants
│   ├── Core/
│   │   ├── Models/             # ScreenInfo, Mode, SurfaceConfig, etc.
│   │   ├── Services/           # ScreenService, ModeService, SurfaceService, LogService
│   │   └── Persistence/        # JSON file persistence
│   ├── Features/
│   │   ├── MenuBar/            # Menu bar dropdown
│   │   ├── Screens/            # Display inspector
│   │   ├── Modes/              # Profile save/load/delete
│   │   ├── Surfaces/           # Virtual workspace + widgets
│   │   └── Logs/               # Diagnostics and event log
│   └── UI/
│       ├── Components/         # Shared UI components
│       └── Theme/              # Colors, typography, spacing
├── Resources/
│   └── Assets.xcassets/        # App icon
├── Info.plist                  # LSUIElement=true (menu bar app)
└── project.yml                 # XcodeGen spec
```

## Tech Stack

- Swift 6 / SwiftUI / AppKit
- CoreGraphics (Quartz Display Services) for display enumeration
- `@Observable` / `@MainActor` patterns
- JSON persistence via `Codable`
- No third-party dependencies

## Honest Limits

- Surfaces are app-managed workspaces, **not** real hardware displays
- Uses public macOS APIs only
- No hardware bypass, fake clamshell, or driver-level overrides
- Streaming and routing are planned for Slice 2

## Roadmap

### Slice 1 (Current)
- [x] Menu bar app shell
- [x] Screen inspector with live refresh
- [x] Mode save/load/delete
- [x] Surface windows with widgets (notes, checklist, timer, links)
- [x] Event logging and diagnostics

### Slice 2 (Planned)
- [ ] Local streaming of Surface windows
- [ ] Receiver prototype (macOS)
- [ ] Mode presets (Desk, TV, iPad, Dual TV)
- [ ] Streaming stats and quality presets

### Slice 3 (Future)
- [ ] iPad/tvOS receiver
- [ ] Expanded Surface modules
- [ ] Automation/hotkeys

## License

Copyright © 2024 VibeForge. All rights reserved.
