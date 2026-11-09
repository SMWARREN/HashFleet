#!/bin/bash
set -euo pipefail

LABEL="app.hashfleet.menubar"
APP_PATH="${HASH_FLEET_MENU_APP:-/Applications/Hash Fleet Menu Bar.app}"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Hash Fleet Menu Bar"
AGENT_PATH="${HASH_FLEET_LAUNCH_AGENT:-$HOME/Library/LaunchAgents/$LABEL.plist}"
LOG_DIR="${HASH_FLEET_LOG_DIR:-$HOME/Library/Logs}"
DOMAIN="gui/$(id -u)"

usage() {
    cat <<'EOF'
Usage: Scripts/hash-fleet-menu-bar.sh <install|status|uninstall|render>

Commands:
  install    Refused. The companion is retired; use the integrated native Mac app.
  status     Print LaunchAgent and process status.
  uninstall  Stop the LaunchAgent and remove its plist. The app is not deleted.
  render     Print the generated LaunchAgent plist without changing the system.

Optional environment overrides:
  HASH_FLEET_MENU_APP       Installed app path.
  HASH_FLEET_LAUNCH_AGENT  LaunchAgent plist path.
  HASH_FLEET_LOG_DIR        stdout/stderr directory.
EOF
}

render_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXECUTABLE_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/HashFleetMenuBar.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/HashFleetMenuBar.error.log</string>
</dict>
</plist>
EOF
}

print_status() {
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        launchctl print "$DOMAIN/$LABEL" \
            | grep -E 'state =|pid =|runs =|last exit code|program =' || true
        return 0
    fi

    echo "$LABEL is not loaded in $DOMAIN" >&2
    return 1
}

install_agent() {
    echo "The separate Hash Fleet Menu Bar companion is retired." >&2
    echo "Build/install HashFleetMac using Scripts/package-hashfleet-mac.sh and Scripts/install-hashfleet-mac.sh." >&2
    echo "The native app owns both the workspace and menu bar. No LaunchAgent is needed." >&2
    return 64
}

uninstall_agent() {
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    for _ in {1..30}; do
        if ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        echo "LaunchAgent is still loaded after bootout: $DOMAIN/$LABEL" >&2
        exit 1
    fi

    if [[ -f "$AGENT_PATH" ]]; then
        rm "$AGENT_PATH"
        echo "Removed $AGENT_PATH"
    else
        echo "LaunchAgent plist was already absent: $AGENT_PATH"
    fi
}

case "${1:-}" in
    install)
        install_agent
        ;;
    status)
        print_status
        ;;
    uninstall)
        uninstall_agent
        ;;
    render)
        render_plist
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
