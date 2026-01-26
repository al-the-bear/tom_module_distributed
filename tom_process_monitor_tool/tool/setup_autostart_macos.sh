#!/bin/bash
set -e

# setup_autostart_macos.sh
# Sets up ProcessMonitor as a macOS LaunchAgent.
# The main ProcessMonitor will automatically spawn the MonitorWatcher.
#
# Usage:
#   cd xternal/tom_module_distributed/tom_process_monitor_tool
#   ./tool/setup_autostart_macos.sh [--clean]
#
# Options:
#   --clean    Delete existing configuration before installation.

echo "Setting up Tom Process Monitor autostart..."

# Parse arguments
CLEAN=false
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN=true
            shift
            ;;
    esac
done

if ! command -v dart >/dev/null 2>&1; then
    echo "Error: dart not found in PATH."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PACKAGE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Compiling executables..."
# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    DART_ARCH="darwin_x64"
elif [ "$ARCH" == "arm64" ]; then
    DART_ARCH="darwin_arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi
INSTALL_BIN="$HOME/.tom/bin/$DART_ARCH"
mkdir -p "$INSTALL_BIN"

# Compile process_monitor as "Tom Process Monitor"
# This ensures it shows up with a user-friendly name in macOS background items list.
BINARY_NAME="Tom Process Monitor"
BINARY_PATH="$INSTALL_BIN/$BINARY_NAME"

echo "Compiling $BINARY_NAME..."
dart compile exe "$PACKAGE_ROOT/bin/process_monitor.dart" -o "$BINARY_PATH"

# Compile Ledger Server
echo "Compiling Ledger Server..."
LEDGER_TOOL_DIR="$PACKAGE_ROOT/../tom_dist_ledger_tool"
dart compile exe "$LEDGER_TOOL_DIR/bin/ledger_server.dart" -o "$INSTALL_BIN/Tom Ledger Server"

if [ "$CLEAN" = true ]; then
    echo "Cleaning old configuration..."
    rm -f "$HOME/.tom/process_monitor/processes_default.json"
    rm -rf "$HOME/.tom/process_monitor/logs"
    echo "Old configuration removed."

    echo "Creating initial configuration with standaloneMode=true..."
    mkdir -p "$HOME/.tom/process_monitor"
    cat > "$HOME/.tom/process_monitor/processes_default.json" <<EOF
{
  "version": 1,
  "instanceId": "default",
  "monitorIntervalMs": 5000,
  "standaloneMode": true,
  "alivenessServer": {
    "enabled": true,
    "port": 19883
  },
  "processes": {}
}
EOF
fi

# We don't need a separate monitor_watcher binary because process_monitor
# can act as a watcher when passed --instance=watcher, which is what the
# internal spawning logic does.

LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS"

# 1. Tom Process Monitor.plist
PM_PLIST="$LAUNCH_AGENTS/Tom Process Monitor.plist"
echo "Creating $PM_PLIST..."
cat > "$PM_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>Tom Process Monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
        <string>--foreground</string>
        <string>--directory</string>
        <string>$HOME/.tom/process_monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/tom_process_monitor.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tom_process_monitor.err</string>
</dict>
</plist>
EOF

# Unload old agents if they exist
echo "Unloading old agents..."
launchctl unload "$LAUNCH_AGENTS/com.tom.monitor_watcher.plist" 2>/dev/null || true
launchctl unload "$LAUNCH_AGENTS/com.tom.process_monitor.plist" 2>/dev/null || true
launchctl unload "$PM_PLIST" 2>/dev/null || true

# Kill existing processes
echo "Stopping existing processes..."
pkill -f "process_monitor" || true
pkill -f "Tom Process Monitor" || true

# Remove deprecated watcher plist if it exists
rm -f "$LAUNCH_AGENTS/com.tom.monitor_watcher.plist"
rm -f "$LAUNCH_AGENTS/com.tom.process_monitor.plist"

# Remove old binary names to avoid confusion
rm -f "$INSTALL_BIN/process_monitor"
rm -f "$INSTALL_BIN/monitor_watcher"

echo "Loading ProcessMonitor Agent (Label: Tom Process Monitor)..."
launchctl load "$PM_PLIST"

echo "Done! Executable installed to $BINARY_PATH"
echo "ProcessMonitor started via LaunchAgent."
echo "The OS sees the binary name '$BINARY_NAME', so it should appear correctly in settings."
echo "Check status with: tail -f /tmp/tom_process_monitor.out"
