#!/usr/bin/env bash
# NeoGaeshi V1 profile installer.
#
# Installs an ISOLATED OpenCode V1 (1.19.3) runtime, the NeoGaeshi V1 profile,
# and the `neogaeshi` CLI launcher. Idempotent: safe to re-run.
#
# The user's global OpenCode V2 (~/.config/opencode, ~/.local/share/opencode,
# the global `opencode` binary) is never read or written.
#
# Normally invoked by the repo-root install.sh, which also installs the
# prerequisites (engram, OpenCode V2). It can run standalone.
#
# Environment:
#   ENGRAM_BIN   absolute path to the engram binary (default: found on PATH)
set -euo pipefail

V1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEOGAESHI_ROOT="${NEOGAESHI_ROOT:-$(cd "$V1_DIR/.." && pwd)}"
PROFILE_SRC="$V1_DIR/profile"

V1_PREFIX="$HOME/.local/share/opencode-v1"
V1_BIN="$V1_PREFIX/node_modules/.bin/opencode"
V1_VERSION="1.19.3"

CONFIG_ROOT="$HOME/.config/neogaeshi-v1"
CONFIG_DIR="$CONFIG_ROOT/opencode"   # XDG_CONFIG_HOME=$CONFIG_ROOT -> config dir is $CONFIG_ROOT/opencode

BIN_DIR="$HOME/.local/bin"
CLI_LINK="$BIN_DIR/neogaeshi"
CLI_TARGET="$V1_DIR/bin/neogaeshi"

# Where the installer should point the profile at the engram binary.
ENGRAM_BIN="${ENGRAM_BIN:-$(command -v engram || true)}"
if [[ -z "${ENGRAM_BIN:-}" ]]; then
  if [[ -x "$HOME/.local/bin/engram" ]]; then
    ENGRAM_BIN="$HOME/.local/bin/engram"
  else
    printf 'engram binary not found. Install it first (the repo-root install.sh does this),\nor set ENGRAM_BIN to its absolute path.\n' >&2
    exit 1
  fi
fi

FORCE=0
WITH_AUTH=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --with-auth) WITH_AUTH=1 ;;
    *) printf 'Unknown option: %s (supported: --force, --with-auth)\n' "$arg" >&2; exit 1 ;;
  esac
done

info() { printf '  \033[38;5;141m•\033[0m %s\n' "$*"; }
ok()   { printf '  \033[38;5;141m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[38;5;203m✘\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. Isolated OpenCode V1 runtime ---------------------------------------
install_runtime() {
  # Skip the (large) download if a working 1.x runtime is already present.
  if [[ -x "$V1_BIN" ]]; then
    local cur
    cur="$("$V1_BIN" --version 2>/dev/null || true)"
    if [[ "$cur" == 1.* ]]; then
      ok "OpenCode V1 runtime already present (version $cur), skipping install"
      return
    fi
  fi

  info "Installing OpenCode V1 $V1_VERSION into $V1_PREFIX"
  # npm's optional-dependency libc detection can flake on a cold cache (it may
  # pick the musl binary on a glibc host). Retry once; it resolves on reify.
  local attempt
  for attempt in 1 2; do
    if npm install --prefix "$V1_PREFIX" "opencode-ai@$V1_VERSION" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" == "2" ]]; then
      fail "npm install of opencode-ai@$V1_VERSION failed twice. Check your network/npm."
    fi
    info "npm install flaked (libc-detection), retrying once..."
  done

  # Verify it is present and reports 1.x.
  [[ -x "$V1_BIN" ]] || fail "V1 binary missing at $V1_BIN after install"
  local ver
  ver="$("$V1_BIN" --version 2>/dev/null || true)"
  [[ "$ver" == 1.* ]] || fail "Installed runtime reports '$ver', expected 1.x"
  ok "OpenCode V1 runtime ready (version $ver)"
}

# --- 2. Profile config ------------------------------------------------------
install_config() {
  info "Installing profile into $CONFIG_DIR"
  mkdir -p "$CONFIG_DIR"

  # Copy the profile tree, rewriting the placeholders so they point at the
  # INSTALLED locations rather than the repo checkout:
  #   tui.json:       __NEOGAESHI_CONFIG__  -> installed config dir (plugin path)
  #   opencode.json:  __NEOGAESHI_ROOT__    -> repo root (skills path)
  #                   __ENGRAM_BIN__        -> absolute engram binary path
  local src dst
  while IFS= read -r -d '' src; do
    dst="$CONFIG_DIR/${src#"$PROFILE_SRC"/}"
    mkdir -p "$(dirname "$dst")"
    case "$src" in
      */tui.json)
        sed "s|__NEOGAESHI_CONFIG__|$CONFIG_DIR|g" "$src" >"$dst"
        ;;
      */opencode.json)
        sed -e "s|__NEOGAESHI_ROOT__|$NEOGAESHI_ROOT|g" \
            -e "s|__ENGRAM_BIN__|$ENGRAM_BIN|g" "$src" >"$dst"
        ;;
      *)
        cp "$src" "$dst"
        ;;
    esac
  done < <(find "$PROFILE_SRC" -type f -print0)

  [[ -f "$CONFIG_DIR/opencode.json" ]] || fail "opencode.json missing after copy"
  [[ -f "$CONFIG_DIR/tui.json" ]] || fail "tui.json missing after copy"
  [[ -f "$CONFIG_DIR/themes/neogaeshi-v1.json" ]] || fail "theme missing after copy"
  [[ -f "$CONFIG_DIR/agent/blue-team-analyst.md" ]] || fail "blue-team-analyst agent missing after copy"
  if grep -q "__NEOGAESHI_ROOT__\|__ENGRAM_BIN__" "$CONFIG_DIR/opencode.json"; then
    fail "placeholders not fully substituted in opencode.json"
  fi
  ok "Profile installed (opencode.json, tui.json, logo plugin, theme, agent)"
}

# --- 2b. Optional provider auth ---------------------------------------------
# The hermetic profile starts with NO provider credentials. With --with-auth,
# copy the user's existing global auth.json (V2 data dir) into the V1
# profile's data dir. OFF by default; the alternative is 'neogaeshi auth
# login' (or '/connect' in-TUI) inside the profile.
install_auth() {
  local src_auth="$HOME/.local/share/opencode/auth.json"
  local dst_auth="$CONFIG_ROOT/data/opencode/auth.json"
  if [[ "$WITH_AUTH" != "1" ]]; then
    info "No provider auth in the profile (run 'neogaeshi auth login', or re-run with --with-auth to reuse ~/.local/share/opencode/auth.json)"
    return
  fi
  [[ -f "$src_auth" ]] || fail "--with-auth: no auth.json at $src_auth to copy"
  mkdir -p "$(dirname "$dst_auth")"
  cp "$src_auth" "$dst_auth"
  ok "Provider auth copied into the profile ($dst_auth)"
}

# --- 3. CLI launcher symlink ------------------------------------------------
install_cli() {
  info "Linking CLI: $CLI_TARGET -> $CLI_LINK"
  mkdir -p "$BIN_DIR"

  # Collision guard: refuse to clobber anything that is not our own symlink.
  if [[ -e "$CLI_LINK" || -L "$CLI_LINK" ]]; then
    if [[ -L "$CLI_LINK" && "$(readlink "$CLI_LINK")" == "$CLI_TARGET" ]]; then
      ok "neogaeshi already linked correctly"
    elif [[ "$FORCE" == "1" ]]; then
      local backup
      backup="$CLI_LINK.bak.$(date +%Y%m%d%H%M%S)"
      mv "$CLI_LINK" "$backup"
      info "Existing entry moved to $backup"
      ln -s "$CLI_TARGET" "$CLI_LINK"
      ok "neogaeshi linked (previous entry backed up)"
    else
      fail "$CLI_LINK exists and is not the neogaeshi launcher. Re-run with --force to back it up and replace it."
    fi
  else
    ln -s "$CLI_TARGET" "$CLI_LINK"
    ok "neogaeshi linked"
  fi

  chmod +x "$CLI_TARGET"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ok "\$HOME/.local/bin is on PATH" ;;
    *) info "NOTE: add $BIN_DIR to your PATH to run 'neogaeshi' directly" ;;
  esac
}

# --- Run --------------------------------------------------------------------
printf '\n\033[38;5;141mNeoGaeshi V1 installer\033[0m (OpenCode %s, isolated)\n\n' "$V1_VERSION"
install_runtime
install_config
install_auth
install_cli
printf '\n\033[38;5;141m✔ Done.\033[0m Run \033[1mneogaeshi\033[0m to start, or \033[1mneogaeshi help\033[0m for usage.\n\n'
