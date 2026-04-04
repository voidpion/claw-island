# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claw Island is a macOS notch-area overlay that monitors and controls Claude Code sessions in real time. It receives hook events via a Unix domain socket, displays session status in the MacBook notch, and surfaces approval UI for permission requests.

## Build Commands

```bash
# Regenerate Xcode project (after modifying project.yml)
xcodegen generate

# Build the app
xcodebuild -project ClawIsland.xcodeproj -scheme ClawIsland build

# Build the bridge binary
xcodebuild -project ClawIsland.xcodeproj -scheme ClawBridge build

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/ClawIsland-*/Build/Products/Debug/ClawIsland.app

# Kill running instance
pkill -f ClawIsland
```

No test targets exist. No linting is configured.

## Architecture

Two targets defined in `project.yml`:

- **ClawIsland** (macOS app, Swift 6.0, macOS 14+) — notch overlay UI
- **ClawBridge** (CLI binary) — glue between Claude Code hooks and the app; embedded in `Contents/Resources/` of the app bundle

### Data Flow

```
Claude Code hooks (settings.json)
  → ~/.claw-island/bin/claw-bridge (stdin JSON)
    → /tmp/claw-island.sock (length-prefixed: [4-byte BE length][JSON])
      → SocketServer → SessionManager.handle()
        → Session @Published properties → SwiftUI re-render
```

### Key Components

**SessionManager** (`Services/SessionManager.swift`) — Central event router. Receives decoded `HookEvent` from SocketServer, manages session lifecycle (create/update/remove), handles approval flow via `CheckedContinuation`. All mutations are `@MainActor`.

**SocketServer** (`Services/SocketServer.swift`) — POSIX BSD sockets over Unix domain socket at `/tmp/claw-island.sock`. The `accept()` loop runs on a real OS thread (`Thread.detachNewThread`), NOT in Swift concurrency — putting it in `Task.detached` blocks the cooperative thread pool.

**HookInstaller** (`Services/HookInstaller.swift`) — Copies ClawBridge from app bundle to `~/.claw-island/bin/claw-bridge`, registers 11 hook events in `~/.claude/settings.json`. Called on every app launch via `AppDelegate.installBridgeIfNeeded()`.

**NotchWindowController** (`UI/NotchWindowController.swift`) — AppKit window management. Creates a borderless, non-activating panel at `.statusBar` level. Hover detection via `NSEvent.addGlobalMonitorForEvents` with spring animations for expand/collapse. Window is hidden when no sessions exist (`alphaValue = 0` → `orderFrontRegardless`).

### Session Status Machine

Status transitions are documented in `ARCH.md`. Key rules:

- `post_tool_use` does NOT reset to idle — stays `.running` until `stop`
- `user_prompt_submit` enters `.running("thinking")` (not idle)
- Only `session_start` enters `.idle`; nothing else returns to idle
- `session_end` removes the session row after a 5-second delay
- Title is frozen after the first `user_prompt_submit`

### SwiftUI + AppKit Integration

- `ClawIslandApp` uses `@NSApplicationDelegateAdaptor` → `AppDelegate`
- `NotchHostingView` (NSHostingView subclass) overrides `acceptsFirstMouse` — required for button clicks in non-activating panels
- State injected via `@EnvironmentObject`: `SessionManager` and `NotchViewModel`

### Debug Logging

Both `SocketServer` and `NotchWindowController` write to `/tmp/claw-island.log`. Check this file when diagnosing connection or visibility issues.

## Conventions

- Swift 6.0 strict concurrency: `@MainActor`, `Sendable`, `@unchecked Sendable` used throughout
- App is `LSUIElement` (no dock icon, no main menu)
- UI text and code comments are in Chinese
- Commit messages are in English with Chinese ARCH.md
