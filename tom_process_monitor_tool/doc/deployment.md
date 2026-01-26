# Deployment Guide

## macOS Autostart Setup

The `setup_autostart_macos.sh` script automates the deployment process.

### Binaries
Executables are compiled to `~/.tom/bin/darwin_arm64/` (for Apple Silicon). 
Two binaries are generated:
- `process_monitor` (as "Tom Process Monitor"): The main process manager.
- `ledger_server` (as "Tom Ledger Server"): The distributed ledger server.

### LaunchAgent
A single LaunchAgent (`com.tom.process_monitor.plist`) is registered to start "Tom Process Monitor" on login. The main process will then spawn the watcher instance automatically using its internal configuration.
