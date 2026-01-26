# Deployment Guide

## macOS Deployment

### Binary Location
Compiled binaries for `process_monitor` and `monitor_watcher` should be placed in `~/.tom/bin/darwin_arm64/` (for Apple Silicon) or the relevant architecture folder. 

### Autostart
Use the provided script in `tom_process_monitor_tool` to setup LaunchAgents. The main `process_monitor` is registered as a LaunchAgent and will automatically start the partner watcher instance.
