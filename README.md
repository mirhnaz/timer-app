# Stopwatch

A minimal macOS menu-bar stopwatch and countdown timer, written in SwiftUI.

The app lives in the status bar (`LSUIElement`) — clicking the status item
opens a popover with the stopwatch and timer; preferences are available via
the standard Settings scene.

## Features

- Stopwatch and countdown timer in a single popover
- Duration entry via free-form text (see `DurationParser.swift`)
- Light / dark / system appearance preference
- Runs as a menu-bar-only app (no Dock icon)

## Project layout

- `Stopwatch/` — app sources (SwiftUI views, models, `AppDelegate`)
- `Stopwatch.xcodeproj/` — Xcode project
- `Tools/render-icon.swift` — helper script for generating the app icon

## Build & run

Open `Stopwatch.xcodeproj` in Xcode and run the `Stopwatch` scheme.

## Requirements

- macOS 26.0 (Tahoe) or later (`LSMinimumSystemVersion` in `Info.plist`)
- Xcode with a Swift toolchain that supports the project's deployment target
