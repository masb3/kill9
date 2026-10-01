# Kill9

**Free your ports.** A tiny macOS menu-bar app that shows what's listening on which TCP port — and kills it in one click.
It's a friendly GUI for `kill -9 $(lsof -ti tcp:8000)`.

## Features
- Live list of listening TCP ports **and bound UDP ports** (refreshes every 3s while open), merged IPv4/IPv6
- Filter All / TCP / UDP, and switch between a flat list and **grouped by app** (helper processes roll up into their parent .app)
- Process name, protocol, PID, user, app icon, and whether it's localhost-only
- **Type a port + Return** → kills everything on that port
- Kill button: SIGTERM first, auto SIGKILL after 1.5s if it won't die
- Right-click: Force Kill (`-9`), Open in Browser, Copy PID / kill command, Reveal in Finder
- Launch at login, no Dock icon

## Build & run (macOS 13+, Xcode Command Line Tools)
```bash
./build-app.sh
open build/Kill9.app
# optional: cp -R build/Kill9.app /Applications/
```
For quick dev iteration: `swift run`

Or open `Package.swift` in Xcode and press ⌘R.

## Notes
- Only processes owned by your user can be killed; root-owned ones show a `sudo kill -9 <pid>` hint.
- Shortcuts in the popover: ⌘R refresh, ⌘Q quit.
