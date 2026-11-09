#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="${HASH_FLEET_PACKAGE_DIR:-$ROOT_DIR/dist/hashfleet-mac}"
APP_SOURCE="$PACKAGE_DIR/Hash Fleet.app"
APP_DEST="${HASH_FLEET_APP_DEST:-/Applications/Hash Fleet.app}"
CLI_DIR="${HASH_FLEET_CLI_DIR:-$HOME/bin}"
CLI_DEST="$CLI_DIR/hashfleet"
VALIDATOR="$ROOT_DIR/Scripts/validate-native-mac-app.sh"
DITTO="${DITTO:-/usr/bin/ditto}"
INSTALL="${INSTALL:-/usr/bin/install}"

canonicalize_path() {
    local candidate="$1" name parent
    [[ "$candidate" == /* ]] || candidate="$ROOT_DIR/$candidate"
    [[ "$candidate" != / ]] || { printf '/\n'; return; }
    candidate="${candidate%/}"
    name="${candidate##*/}"
    parent="${candidate%/*}"
    [[ -n "$parent" ]] || parent="/"
    while [[ ! -d "$parent" && "$parent" != / ]]; do
        name="${parent##*/}/$name"
        parent="${parent%/*}"
        [[ -n "$parent" ]] || parent="/"
    done
    [[ -d "$parent" ]] || return 1
    parent="$(cd -P "$parent" && pwd)"
    printf '%s/%s\n' "${parent%/}" "$name"
}

APP_DEST="$(canonicalize_path "$APP_DEST")" || { echo "Cannot resolve app destination parent." >&2; exit 1; }
CLI_DIR="$(canonicalize_path "$CLI_DIR")" || { echo "Cannot resolve CLI directory parent." >&2; exit 1; }
CLI_DEST="$CLI_DIR/hashfleet"
[[ "$APP_DEST" == */"Hash Fleet.app" && ! -L "$APP_DEST" ]] || { echo "Refusing unsafe app destination: $APP_DEST" >&2; exit 1; }
[[ "$CLI_DEST" != "$APP_DEST" && "$CLI_DEST" != "$APP_DEST"/* ]] || { echo "CLI destination cannot be inside the app bundle." >&2; exit 1; }
[[ ! -L "$CLI_DEST" || -e "$CLI_DEST" ]] || { echo "Refusing dangling CLI symlink: $CLI_DEST" >&2; exit 1; }
[[ -d "$APP_SOURCE" ]] || { echo "Native package app is missing: $APP_SOURCE" >&2; exit 1; }
bash "$VALIDATOR" "$APP_SOURCE"

APP_PARENT="$(dirname "$APP_DEST")"
APP_BACKUP_DIR="$APP_PARENT/.hashfleet-backups.noindex"
[[ ! -L "$APP_BACKUP_DIR" ]] || { echo "Refusing symlinked app backup directory." >&2; exit 1; }
mkdir -p "$APP_PARENT" "$CLI_DIR"
APP_STAGE="$(mktemp -d "$APP_PARENT/.hashfleet-install.XXXXXX")"
APP_STAGE_BUNDLE="$APP_STAGE/Hash Fleet.app"
APP_BACKUP=""
CLI_BACKUP=""
CLI_TEMP="$CLI_DIR/.hashfleet-cli.$$.${RANDOM}"
APP_INSTALLED=0
CLI_CHANGED=0
INSTALL_COMMITTED=0
cleanup() {
    local status=$?
    if (( status != 0 && ! INSTALL_COMMITTED )); then
        if (( CLI_CHANGED )); then
            rm -f "$CLI_DEST"
            if [[ -n "$CLI_BACKUP" && ( -e "$CLI_BACKUP" || -L "$CLI_BACKUP" ) ]]; then mv "$CLI_BACKUP" "$CLI_DEST" || echo "WARNING: CLI backup remains at $CLI_BACKUP" >&2; fi
        fi
        if (( APP_INSTALLED )); then rm -rf "$APP_DEST"; fi
        if [[ -n "$APP_BACKUP" && -e "$APP_BACKUP" ]]; then mv "$APP_BACKUP" "$APP_DEST" || echo "WARNING: app backup remains at $APP_BACKUP" >&2; fi
    fi
    rm -f "$CLI_TEMP"
    [[ -z "$APP_STAGE" || ! -e "$APP_STAGE" ]] || rm -rf "$APP_STAGE"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$DITTO" "$APP_SOURCE" "$APP_STAGE_BUNDLE"
bash "$VALIDATOR" "$APP_STAGE_BUNDLE"
"$INSTALL" -m 755 "$APP_STAGE_BUNDLE/Contents/MacOS/hashfleet" "$CLI_TEMP"
[[ -x "$CLI_TEMP" ]] || { echo "Staged CLI is not executable." >&2; exit 1; }
if [[ -e "$CLI_DEST" || -L "$CLI_DEST" ]]; then
    CLI_BACKUP="$CLI_DIR/.hashfleet-cli-backup.$$.${RANDOM}"
    mv "$CLI_DEST" "$CLI_BACKUP"
    CLI_CHANGED=1
fi
if [[ -e "$APP_DEST" ]]; then
    # Never leave another application-shaped package beside the installed app.
    # Hidden, nonindexed rollback storage is not a second Applications entry.
    mkdir -p "$APP_BACKUP_DIR"
    APP_BACKUP="$APP_BACKUP_DIR/Hash Fleet.backup.$$.${RANDOM}"
    mv "$APP_DEST" "$APP_BACKUP"
fi
mv "$APP_STAGE_BUNDLE" "$APP_DEST"
APP_INSTALLED=1
ln -s "$APP_DEST/Contents/MacOS/hashfleet" "$CLI_DEST"
CLI_CHANGED=1
[[ -x "$CLI_DEST" && "$(readlink "$CLI_DEST")" == "$APP_DEST/Contents/MacOS/hashfleet" ]] || { echo "CLI link verification failed." >&2; exit 1; }
bash "$VALIDATOR" "$APP_DEST"

# Verify the exact rollback bundle before authorizing its deletion. Unknown or
# non-native contents remain protected by the still-active rollback transaction.
if [[ -n "$APP_BACKUP" ]]; then
    [[ ! -L "$APP_BACKUP_DIR" && ! -L "$APP_BACKUP" &&
       "$(dirname "$APP_BACKUP")" == "$APP_BACKUP_DIR" ]] || {
        echo "Refusing unsafe superseded app backup: $APP_BACKUP" >&2
        exit 1
    }
    bash "$VALIDATOR" "$APP_BACKUP"
fi
rm -rf "$APP_STAGE"
APP_STAGE=""

# No rollback may occur after deletion starts: a partially deleted old bundle
# must never replace the validated installation, including on failure or signal.
INSTALL_COMMITTED=1
if [[ -n "$APP_BACKUP" ]]; then
    if ! rm -rf -- "$APP_BACKUP"; then
        echo "Installation validated, but superseded app cleanup failed: $APP_BACKUP" >&2
        exit 1
    fi
    APP_BACKUP=""
fi
printf 'Installed native Hash Fleet at %s\n' "$APP_DEST"
printf 'Linked bundled CLI at %s\n' "$CLI_DEST"
[[ -z "$CLI_BACKUP" ]] || printf 'Previous CLI entry retained at %s\n' "$CLI_BACKUP"
printf 'If %s is not on PATH, add: export PATH="%s:$PATH"\n' "$CLI_DIR" "$CLI_DIR"
