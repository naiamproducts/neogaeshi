#!/usr/bin/env bash
# NeoGaeshi — one-liner bootstrap installer (Linux).
#
# Installs the complete NeoGaeshi blue-team profile:
#   1. prerequisites (git, curl, node, npm — via your package manager if needed)
#   2. engram (local persistent memory, MCP server)
#      https://github.com/Gentleman-Programming/engram
#   3. OpenCode V2 (system, official installer -> ~/.opencode/bin)
#      https://github.com/anomalyco/opencode (formerly sst/opencode)
#   4. OpenCode V1 runtime 1.19.3 (isolated, ~/.local/share/opencode-v1)
#   5. this repo -> ~/.local/share/neogaeshi (the V2 profile root)
#   6. the hermetic V1 profile + the `neogaeshi` CLI (~/.local/bin/neogaeshi)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/naiamproducts/neogaeshi/main/install.sh | bash
#   bash install.sh [--with-auth] [--force] [--uninstall] [--help]
#
# Flags:
#   --with-auth    copy an existing ~/.local/share/opencode/auth.json into the
#                  isolated V1 profile (OFF by default; never touches the original)
#   --force        back up and replace a conflicting ~/.local/bin/neogaeshi entry
#   --uninstall    remove NeoGaeshi (symlink, profile config, V1 runtime, repo
#                  copy). Never touches your global opencode config or data,
#                  and leaves the general-purpose engram/opencode binaries alone
#   --help         show this help
#
# Environment (mostly for testing):
#   NEOGAESHI_ROOT            install location of the repo copy
#                             (default: ~/.local/share/neogaeshi)
#   NEOGAESHI_SOURCE          local directory to copy instead of git-cloning
#                             (for pre-release testing; the default is the
#                             GitHub repo above)
#   NEOGAESHI_SKIP_ENGRAM=1   skip the engram download (expects it already present)
#   NEOGAESHI_SKIP_OPENCODE=1 skip the OpenCode V2 install (expects opencode on PATH)
#   NEOGAESHI_SKIP_RUNTIME=1  skip the isolated OpenCode V1 runtime install
set -euo pipefail

REPO_URL="https://github.com/naiamproducts/neogaeshi"
NEOGAESHI_ROOT="${NEOGAESHI_ROOT:-$HOME/.local/share/neogaeshi}"
V1_VERSION="1.19.3"
V1_PREFIX="$HOME/.local/share/opencode-v1"
BIN_DIR="$HOME/.local/bin"
CONFIG_ROOT="$HOME/.config/neogaeshi-v1"

# Make user-local bins visible inside this run (installed tools must be
# verifiable even when ~/.local/bin is not on PATH yet).
export PATH="$BIN_DIR:$HOME/.opencode/bin:$PATH"

# --- Presentation -----------------------------------------------------------
VIOLET=$'\033[38;5;141m'
MUTED=$'\033[38;5;245m'
BOLD=$'\033[1m'
RED=$'\033[38;5;203m'
RESET=$'\033[0m'
info() { printf '  %s•%s %s\n' "$VIOLET" "$RESET" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$VIOLET" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$RED" "$RESET" "$*" >&2; }
fail() { printf '\n%s✘ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

usage() {
  awk 'NR>1 && /^set -euo pipefail/{exit} NR>1{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"
}

# --- Flags ------------------------------------------------------------------
WITH_AUTH=0
FORCE=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --with-auth) WITH_AUTH=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf '%sUnknown option: %s (see --help)%s\n' "$RED" "$arg" "$RESET" >&2; exit 1 ;;
  esac
done

# --- Sudo helper (only ever used for the required packages) -----------------
SUDO_OK=0
need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then SUDO_OK=0; return; fi  # 0 = run directly
  if command -v sudo >/dev/null 2>&1; then
    info "This step needs root to install missing packages via the system package manager"
    sudo -v || fail "sudo authentication failed"
    SUDO_OK=1
    return
  fi
  fail "Missing required tools and no sudo available. Install them manually, then re-run:
  - git, curl, node (>=18), npm
  Debian/Ubuntu:  sudo apt-get install -y git curl nodejs npm
  Fedora:         sudo dnf install -y git curl nodejs npm
  Arch:           sudo pacman -S --noconfirm git curl nodejs npm
  openSUSE:       sudo zypper -n install git curl nodejs npm"
}
as_root() {
  if [[ "$SUDO_OK" == "1" ]]; then sudo "$@"; else "$@"; fi
}

# --- 1. Preflight -----------------------------------------------------------
preflight() {
  printf '\n%sNeoGaeshi installer%s — blue-team profile for OpenCode\n\n' "$VIOLET" "$RESET"

  [[ "$(uname -s)" == "Linux" ]] || fail "NeoGaeshi currently supports Linux only (detected: $(uname -s))."

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) fail "Unsupported architecture: $(uname -m) (supported: x86_64, aarch64)" ;;
  esac
  ARCH="$arch"

  local pkgmgr=""
  for m in apt-get dnf pacman zypper; do
    if command -v "$m" >/dev/null 2>&1; then pkgmgr="$m"; break; fi
  done
  PKGMGR="$pkgmgr"
  info "Platform: linux/$ARCH (pkg manager: ${pkgmgr:-none detected})"

  # Ensure required tools; install missing ones via the pkg manager.
  local missing=() c
  for c in git curl node npm; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    info "Missing required tools: ${missing[*]}"
    need_sudo
    local pkgs=()
    for c in "${missing[@]}"; do
      case "$c" in
        node|npm) pkgs+=(nodejs npm) ;;
        *) pkgs+=("$c") ;;
      esac
    done
    # shellcheck disable=SC2207
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    info "Installing via $PKGMGR: ${pkgs[*]}"
    case "$PKGMGR" in
      apt-get) as_root apt-get update -qq && as_root apt-get install -y "${pkgs[@]}" ;;
      dnf)     as_root dnf install -y "${pkgs[@]}" ;;
      pacman)  as_root pacman -S --noconfirm --needed "${pkgs[@]}" ;;
      zypper)  as_root zypper -n install "${pkgs[@]}" ;;
      *) fail "No supported package manager found to install: ${pkgs[*]}" ;;
    esac
    for c in "${missing[@]}"; do
      command -v "$c" >/dev/null 2>&1 || fail "'$c' is still missing after installation. Install it manually and re-run."
    done
  fi
  ok "Prerequisites present: git, curl, node ($(node --version 2>/dev/null || true)), npm"
}

# --- 2. engram --------------------------------------------------------------
install_engram() {
  printf '\n%s[1/5]%s engram (persistent memory)\n' "$VIOLET" "$RESET"

  if [[ -x "$BIN_DIR/engram" ]] && "$BIN_DIR/engram" --version >/dev/null 2>&1; then
    ok "engram already present ($("$BIN_DIR/engram" --version 2>/dev/null | head -1)), skipping download"
    ENGRAM_BIN="$BIN_DIR/engram"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_ENGRAM:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_ENGRAM=1 set but no engram at $BIN_DIR/engram; falling back to PATH"
    ENGRAM_BIN="$(command -v engram || true)"
    [[ -n "$ENGRAM_BIN" ]] || fail "NEOGAESHI_SKIP_ENGRAM=1 but engram was not found on PATH"
    return
  fi

  info "Resolving latest engram release from GitHub..."
  local api asset version
  api="$(curl -fsSL https://api.github.com/repos/Gentleman-Programming/engram/releases/latest)" \
    || fail "Could not reach the engram GitHub releases API. Check your network (or set NEOGAESHI_SKIP_ENGRAM=1 if engram is already installed)."
  version="$(printf '%s' "$api" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
  [[ -n "$version" ]] || fail "Could not parse the latest engram release tag from the GitHub API"
  # Asset naming: engram_<version>_linux_<amd64|arm64>.tar.gz
  asset="$(printf '%s' "$api" | grep -o '"browser_download_url": *"[^"]*linux_'"$ARCH"'\.tar\.gz"' | head -1 | cut -d'"' -f4)"
  [[ -n "$asset" ]] || fail "No linux/$ARCH binary asset in engram release $version"
  info "Downloading engram $version (linux/$ARCH)..."

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  curl -fsSL "$asset" -o "$tmp/engram.tar.gz" || fail "Download of $asset failed"
  tar -xzf "$tmp/engram.tar.gz" -C "$tmp" || fail "Could not extract $asset"
  [[ -f "$tmp/engram" ]] || fail "Archive did not contain an 'engram' binary"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$tmp/engram" "$BIN_DIR/engram"
  "$BIN_DIR/engram" --version >/dev/null 2>&1 || fail "Installed engram binary does not run"
  ENGRAM_BIN="$BIN_DIR/engram"
  ok "engram installed: $("$BIN_DIR/engram" --version 2>/dev/null | head -1) ($BIN_DIR/engram)"
}

# --- 3. OpenCode V2 (system) ------------------------------------------------
install_opencode_v2() {
  printf '\n%s[2/5]%s OpenCode V2 (system)\n' "$VIOLET" "$RESET"

  local cur=""
  if command -v opencode >/dev/null 2>&1; then
    cur="$(opencode --version 2>/dev/null || true)"
  fi
  if [[ "$cur" == v2.* ]]; then
    ok "OpenCode V2 already present ($cur), skipping install"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_OPENCODE:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_OPENCODE=1 set; skipping OpenCode V2 install (neogaeshi v2 needs it on PATH)"
    return
  fi

  # NOTE: https://opencode.ai/install installs OpenCode *1*; OpenCode 2 has its
  # own official installer (verified 2026-10).
  info "Installing OpenCode V2 via the official installer (-> ~/.opencode/bin)..."
  curl -fsSL https://opencode.ai/v2/install | bash || fail "The OpenCode V2 installer failed. Check your network, or install manually: curl -fsSL https://opencode.ai/v2/install | bash"

  cur=""
  if command -v opencode >/dev/null 2>&1; then
    cur="$(opencode --version 2>/dev/null || true)"
  fi
  if [[ "$cur" != v2.* ]]; then
    fail "opencode V2 not runnable after install (reported: '${cur:-not found}'). Open a new shell so ~/.opencode/bin is on PATH, then re-run."
  fi
  ok "OpenCode V2 ready: $cur"
  case ":$PATH:" in
    *":$HOME/.opencode/bin:"*) : ;;
    *) info "NOTE: add ~/.opencode/bin to your PATH (the installer usually wires this into your shell rc)" ;;
  esac
}

# --- 4. OpenCode V1 runtime (isolated) --------------------------------------
install_v1_runtime() {
  printf '\n%s[3/5]%s OpenCode V1 %s (isolated runtime)\n' "$VIOLET" "$RESET" "$V1_VERSION"

  local v1_bin="$V1_PREFIX/node_modules/.bin/opencode"
  if [[ -x "$v1_bin" ]] && [[ "$("$v1_bin" --version 2>/dev/null || true)" == 1.* ]]; then
    ok "OpenCode V1 runtime already present ($("$v1_bin" --version 2>/dev/null)), skipping install"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_RUNTIME:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_RUNTIME=1 set; skipping the V1 runtime install"
    return
  fi

  info "npm install --prefix $V1_PREFIX opencode-ai@$V1_VERSION"
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
  [[ -x "$v1_bin" ]] || fail "V1 binary missing at $v1_bin after install"
  local ver
  ver="$("$v1_bin" --version 2>/dev/null || true)"
  [[ "$ver" == 1.* ]] || fail "Installed runtime reports '$ver', expected 1.x"
  ok "OpenCode V1 runtime ready: version $ver"
}

# --- 5. NeoGaeshi repo copy -------------------------------------------------
acquire_source() {
  printf '\n%s[4/5]%s NeoGaeshi profile\n' "$VIOLET" "$RESET"

  if [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    ok "NeoGaeshi already installed at $NEOGAESHI_ROOT (reusing; delete it to force a fresh copy)"
    return
  fi

  mkdir -p "$NEOGAESHI_ROOT"
  if [[ -n "${NEOGAESHI_SOURCE:-}" ]]; then
    [[ -d "$NEOGAESHI_SOURCE" ]] || fail "NEOGAESHI_SOURCE=$NEOGAESHI_SOURCE is not a directory"
    info "Copying from local source $NEOGAESHI_SOURCE"
    (cd "$NEOGAESHI_SOURCE" && tar --exclude=.git --exclude=workspace --exclude=journal -cf - .) \
      | (cd "$NEOGAESHI_ROOT" && tar -xf -)
  else
    info "Cloning $REPO_URL -> $NEOGAESHI_ROOT"
    git clone --depth 1 "$REPO_URL" "$NEOGAESHI_ROOT" \
      || fail "git clone failed. For pre-release testing, set NEOGAESHI_SOURCE=<local checkout>."
  fi
  [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]] || fail "Repository copy looks incomplete (missing v1/bin/neogaeshi)"
  ok "NeoGaeshi profile in place at $NEOGAESHI_ROOT"
}

# --- 6. Profile config + CLI ------------------------------------------------
install_profile() {
  # Substitute the engram binary path into the V2 profile config at the repo
  # root (the committed file carries an __ENGRAM_BIN__ placeholder).
  sed -i "s|__ENGRAM_BIN__|$ENGRAM_BIN|g" "$NEOGAESHI_ROOT/opencode.json"
  if grep -q "__ENGRAM_BIN__" "$NEOGAESHI_ROOT/opencode.json"; then
    fail "Placeholder substitution failed in $NEOGAESHI_ROOT/opencode.json"
  fi

  # v1/install.sh: hermetic V1 profile (substitutes __NEOGAESHI_ROOT__,
  # __ENGRAM_BIN__, __NEOGAESHI_CONFIG__), runtime if still missing, CLI symlink.
  local extra=()
  if [[ "$WITH_AUTH" == "1" ]]; then extra+=(--with-auth); fi
  if [[ "$FORCE" == "1" ]]; then extra+=(--force); fi
  export NEOGAESHI_ROOT ENGRAM_BIN
  bash "$NEOGAESHI_ROOT/v1/install.sh" "${extra[@]+"${extra[@]}"}"
}

# --- 7. Uninstall -----------------------------------------------------------
uninstall() {
  printf '\n%sNeoGaeshi uninstaller%s\n\n' "$VIOLET" "$RESET"

  local cli="$BIN_DIR/neogaeshi"
  if [[ -L "$cli" ]] && [[ "$(readlink "$cli")" == "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    rm "$cli"; ok "Removed $cli"
  else
    info "No NeoGaeshi symlink at $cli (nothing to remove)"
  fi

  if [[ -d "$CONFIG_ROOT" ]]; then
    rm -rf "$CONFIG_ROOT"; ok "Removed V1 profile config ($CONFIG_ROOT)"
  fi
  if [[ -d "$V1_PREFIX" ]]; then
    rm -rf "$V1_PREFIX"; ok "Removed isolated V1 runtime ($V1_PREFIX)"
  fi
  if [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    rm -rf "$NEOGAESHI_ROOT"; ok "Removed NeoGaeshi copy ($NEOGAESHI_ROOT)"
  fi

  printf '\n%sNote:%s engram and the system OpenCode binaries were left in place\n  (general-purpose tools; remove them yourself if unwanted).\n  Your global opencode config/data (~/.config/opencode, ~/.local/share/opencode)\n  was never touched.\n\n' "$MUTED" "$RESET"
}

# --- 8. Sanity + next steps -------------------------------------------------
finish() {
  printf '\n%s[5/5]%s Sanity check\n' "$VIOLET" "$RESET"
  local v_engram v_ng v_oc
  v_engram="$(engram --version 2>/dev/null | head -1 || echo 'NOT RUNNABLE')"
  v_ng="$(neogaeshi --version 2>/dev/null | head -1 || echo 'NOT RUNNABLE')"
  v_oc="$(opencode --version 2>/dev/null | head -1 || echo 'NOT RUNNABLE')"
  printf '  engram     %s\n' "$v_engram"
  printf '  neogaeshi  %s\n' "$v_ng"
  printf '  opencode   %s\n' "$v_oc"

  case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) printf '\n%sNOTE:%s add %s to your PATH to run neogaeshi/engram directly\n' "$MUTED" "$RESET" "$BIN_DIR" ;;
  esac

  cat <<EOF

${VIOLET}✔ NeoGaeshi installed.${RESET}

${BOLD}Next steps${RESET}
  1. Connect a model provider (the one manual step):
       neogaeshi auth login        # inside the isolated V1 profile
     or run /connect inside the TUI. Re-run this installer with --with-auth to
     reuse an existing ~/.local/share/opencode/auth.json instead.
  2. Start the V1 line:     ${BOLD}neogaeshi${RESET}   (TUI with home logo, hermetic)
     Continue a session:    ${BOLD}neogaeshi -c${RESET}   Resume by id: ${BOLD}neogaeshi -s <id>${RESET}
  3. Start the V2 line:     ${BOLD}neogaeshi v2${RESET}  (system OpenCode V2 from the profile root)

${MUTED}Inside the TUI: /neogaeshi-triage /neogaeshi-hunt /neogaeshi-timeline
/neogaeshi-detection /neogaeshi-status — 39 curated defensive skills + engram memory.${RESET}

EOF
}

# --- Run --------------------------------------------------------------------
if [[ "$UNINSTALL" == "1" ]]; then
  uninstall
  exit 0
fi

preflight
install_engram
install_opencode_v2
install_v1_runtime
acquire_source
install_profile
finish
