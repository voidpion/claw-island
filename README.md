# Claw Island

A macOS notch-area overlay that monitors and controls Claude Code sessions in real time. It receives hook events via a Unix domain socket, displays session status in the MacBook notch, and surfaces approval UI for permission requests.

## Features

- Real-time session monitoring in the notch area
- Permission request approval UI (Allow / Deny / Always Allow)
- AskUserQuestion panel for interactive prompts
- Multi-session support with status dots
- Screen selection for multi-monitor setups
- Sound effects for key events
- LSUIElement app (no dock icon)

## Requirements

- macOS 14.0+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## Install

1. Download `ClawIsland.dmg` from [Releases](https://github.com/voidpion/claw-island/releases).
2. Open the DMG and drag **ClawIsland.app** to the **Applications** folder.
3. Open Terminal and run:

   ```
   xattr -cr /Applications/ClawIsland.app
   ```

4. Launch from Applications.

The `xattr` step is needed because the app is not notarized. You only need to do it once.

## How It Works

On launch, Claw Island installs a bridge binary (`claw-bridge`) and registers 11 hook events in Claude Code's `settings.json`. When Claude Code triggers a hook, the bridge forwards the event to the app via a Unix domain socket at `/tmp/claw-island.sock`.

```
Claude Code hooks → claw-bridge (stdin JSON) → /tmp/claw-island.sock → Claw Island UI
```

## Build from Source

```bash
# Generate Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate

# Build
xcodebuild -project ClawIsland.xcodeproj -scheme ClawIsland build

# Package DMG
bash scripts/package.sh
```

## License

MIT
