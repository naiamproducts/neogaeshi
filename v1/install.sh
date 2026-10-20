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
# Flags:
#   --force       back up and replace a conflicting ~/.local/bin/neogaeshi entry
#   --with-auth   copy the global auth.json into the profile (see below)
#   --update-config   config re-sync only (run by `neogaeshi update`): skip the
#                     runtime, auth and CLI steps, and back up every installed
#                     config file that differs from the incoming template (as
#                     <file>.bak.<timestamp>) before replacing it
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
UPDATE_CONFIG=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --with-auth) WITH_AUTH=1 ;;
    --update-config) UPDATE_CONFIG=1 ;;
    *) printf 'Unknown option: %s (supported: --force, --with-auth, --update-config)\n' "$arg" >&2; exit 1 ;;
  esac
done

info() { printf '  \033[38;5;141m•\033[0m %s\n' "$*"; }
ok()   { printf '  \033[38;5;141m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[38;5;203m!\033[0m %s\n' "$*" >&2; }
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
# Renders v1/profile/ into the hermetic config dir, rewriting the placeholders
# so they point at the INSTALLED locations rather than the repo checkout.
# In --update-config mode (run by `neogaeshi update`) every installed file
# that differs from the incoming template is backed up to
# <file>.bak.<timestamp> before being replaced, so local edits survive.
install_config() {
  if [[ "$UPDATE_CONFIG" == "1" ]]; then
    info "Re-syncing profile into $CONFIG_DIR (backing up changed files first)"
  else
    info "Installing profile into $CONFIG_DIR"
  fi
  mkdir -p "$CONFIG_DIR"

  # Render the profile tree into a staging dir first:
  #   tui.json:       __NEOGAESHI_CONFIG__  -> installed config dir (plugin path)
  #   opencode.json:  __NEOGAESHI_ROOT__    -> repo root (skills path)
  #                   __ENGRAM_BIN__        -> absolute engram binary path
  local staging src rel dst
  staging="$(mktemp -d)"
  while IFS= read -r -d '' src; do
    rel="${src#"$PROFILE_SRC"/}"
    dst="$staging/$rel"
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

  # Commit the staged files into the config dir, backing up local edits first.
  local ts backups=()
  ts="$(date +%Y%m%d%H%M%S)"
  while IFS= read -r -d '' src; do
    rel="${src#"$staging"/}"
    dst="$CONFIG_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    if [[ "$UPDATE_CONFIG" == "1" && -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
      cp -p "$dst" "$dst.bak.$ts"
      backups+=("$dst.bak.$ts")
    fi
    cp "$src" "$dst"
  done < <(find "$staging" -type f -print0)
  rm -rf "$staging"

  [[ -f "$CONFIG_DIR/opencode.json" ]] || fail "opencode.json missing after copy"
  [[ -f "$CONFIG_DIR/tui.json" ]] || fail "tui.json missing after copy"
  [[ -f "$CONFIG_DIR/themes/neogaeshi-v1.json" ]] || fail "theme missing after copy"
  [[ -f "$CONFIG_DIR/agent/blue-team-analyst.md" ]] || fail "blue-team-analyst agent missing after copy"
  if grep -q "__NEOGAESHI_ROOT__\|__ENGRAM_BIN__" "$CONFIG_DIR/opencode.json"; then
    fail "placeholders not fully substituted in opencode.json"
  fi
  ok "Profile installed (opencode.json, tui.json, logo plugin, theme, agent)"

  if [[ "$UPDATE_CONFIG" == "1" ]]; then
    if [[ "${#backups[@]}" -gt 0 ]]; then
      info "Backed up local edits before overwrite:"
      local b
      for b in "${backups[@]}"; do printf '      %s\n' "$b"; done
      info "Your custom edits live in those .bak files — re-apply them on top if you want them back"
    else
      ok "No local config edits to back up"
    fi
  fi
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

  # Shadow detection: resolve what the USER'S shell would actually run, not
  # what this process sees. The root install.sh prepends $BIN_DIR to PATH for
  # the whole run, which would mask a foreign 'neogaeshi' that outranks
  # ~/.local/bin in the user's own environment — NEOGAESHI_USER_PATH is the
  # caller's PATH as-is when set, and stands in for $PATH otherwise.
  local lookup_path="${NEOGAESHI_USER_PATH:-$PATH}"
  local shadow shadow_real target_real kind verb remedy
  shadow="$( (PATH="$lookup_path"; command -v neogaeshi) 2>/dev/null || true)"
  [[ "$shadow" == /* ]] || shadow=""   # only a real path can shadow a file
  if [[ -n "$shadow" ]]; then
    shadow_real="$(readlink -f "$shadow" 2>/dev/null || true)"
    target_real="$(readlink -f "$CLI_TARGET" 2>/dev/null || true)"
    if [[ -n "$shadow_real" && -n "$target_real" && "$shadow_real" != "$target_real" ]]; then
      if [[ -L "$shadow" ]]; then
        kind="symlink -> $(readlink "$shadow")"
        verb="Repoint it at the installed launcher, e.g.:"
        remedy="ln -sf $CLI_TARGET $shadow"
      else
        kind="regular file"
        verb="Remove it, e.g.:"
        remedy="mv $shadow $shadow.old"
      fi
      warn "WARNING: another 'neogaeshi' shadows the installed one:"
      printf '      %s  (%s)\n' "$shadow" "$kind" >&2
      printf '    Your commands would run that copy instead. %s\n' "$verb" >&2
      printf '      %s\n' "$remedy" >&2
    fi
  fi

  # PATH status from the user's own shell perspective (same lookup as above).
  case ":$lookup_path:" in
    *":$BIN_DIR:"*) ok "\$HOME/.local/bin is on PATH" ;;
    *) info "NOTE: add $BIN_DIR to your PATH to run 'neogaeshi' directly" ;;
  esac
}

# --- Run --------------------------------------------------------------------
if [[ "$UPDATE_CONFIG" == "1" ]]; then
  printf '\n\033[38;5;141mNeoGaeshi V1 config re-sync\033[0m\n\n'
  install_config
  printf '\n\033[38;5;141m✔ Config re-synced.\033[0m\n\n'
  exit 0
fi

printf '\n\033[38;5;141mNeoGaeshi V1 installer\033[0m (OpenCode %s, isolated)\n\n' "$V1_VERSION"
install_runtime
install_config
install_auth
install_cli
printf '\n\033[38;5;141m✔ Done.\033[0m Run \033[1mneogaeshi\033[0m to start, or \033[1mneogaeshi help\033[0m for usage.\n\n'
