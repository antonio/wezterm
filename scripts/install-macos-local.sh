#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build and install this checkout of WezTerm on macOS.

Usage:
  scripts/install-macos-local.sh [--dry-run] [--skip-build] [--app-dir DIR] [--bin-dir DIR]

Options:
  --dry-run     Print the commands without changing anything.
  --skip-build  Reuse an existing target/release build.
  --app-dir     Install the app bundle into this directory. Default: /Applications
  --bin-dir     Link CLI tools into this directory. Default: ~/.local/bin
  -h, --help    Show this help.
EOF
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

path_contains_dir() {
  local needle="$1"
  local path_entry
  IFS=':' read -r -a entries <<<"${PATH:-}"
  for path_entry in "${entries[@]}"; do
    if [[ "$path_entry" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

DRY_RUN=0
SKIP_BUILD=0
APP_DIR="/Applications"
BIN_DIR="$HOME/.local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --app-dir)
      APP_DIR="$2"
      shift
      ;;
    --bin-dir)
      BIN_DIR="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$OSTYPE" != darwin* ]]; then
  echo "this installer only supports macOS" >&2
  exit 1
fi

require_command cargo
require_command tic
require_command ditto
require_command install

if command -v brew >/dev/null 2>&1; then
  if brew list --cask wezterm >/dev/null 2>&1 || brew list --cask wezterm@nightly >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Homebrew still manages a WezTerm cask on this machine.
Uninstall it first so brew does not overwrite your local app bundle later:

  brew uninstall --cask wezterm
  brew uninstall --cask wezterm@nightly
EOF
    exit 1
  fi
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$REPO_ROOT/target/release"
APP_NAME="WezTerm.app"
DEST_APP="$APP_DIR/$APP_NAME"

if [[ "$DRY_RUN" -eq 1 ]]; then
  STAGING_ROOT="${TMPDIR:-/tmp}/wezterm-install-dry-run"
else
  STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-install.XXXXXX")"
  trap 'rm -rf -- "$STAGING_ROOT"' EXIT
fi
STAGED_APP="$STAGING_ROOT/$APP_NAME"

cd "$REPO_ROOT"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  run cargo build --release
fi

BINS=(wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes)

if [[ "$DRY_RUN" -eq 0 ]]; then
  for bin in "${BINS[@]}"; do
    if [[ ! -x "$TARGET_DIR/$bin" ]]; then
      echo "expected built binary at $TARGET_DIR/$bin" >&2
      echo "run without --skip-build or build it yourself first" >&2
      exit 1
    fi
  done
fi

run rm -rf "$STAGED_APP"
run /usr/bin/ditto "$REPO_ROOT/assets/macos/$APP_NAME" "$STAGED_APP"
run find "$STAGED_APP" -maxdepth 1 -name '*.dylib' -delete
run mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
run /usr/bin/ditto "$REPO_ROOT/assets/shell-integration" "$STAGED_APP/Contents/Resources/shell-integration"
run /usr/bin/ditto "$REPO_ROOT/assets/shell-completion" "$STAGED_APP/Contents/Resources/shell-completion"
run tic -xe wezterm -o "$STAGED_APP/Contents/Resources/terminfo" "$REPO_ROOT/termwiz/data/wezterm.terminfo"

for bin in "${BINS[@]}"; do
  run install -m 755 "$TARGET_DIR/$bin" "$STAGED_APP/Contents/MacOS/$bin"
done

run mkdir -p "$APP_DIR"
run rm -rf "$DEST_APP"
run /usr/bin/ditto "$STAGED_APP" "$DEST_APP"

run mkdir -p "$BIN_DIR"
for bin in "${BINS[@]}"; do
  run ln -sfn "$DEST_APP/Contents/MacOS/$bin" "$BIN_DIR/$bin"
done

cat <<EOF
Installed $DEST_APP
Linked CLI tools into $BIN_DIR
EOF

if ! path_contains_dir "$BIN_DIR"; then
  cat <<EOF

$BIN_DIR is not on your PATH.
Add this to your shell config if you want these binaries to win by default:

  export PATH="$BIN_DIR:\$PATH"
EOF
fi
