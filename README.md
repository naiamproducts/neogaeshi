```
█   █ █████  ███   ███   ███  █████ █████ █   █ █████
██  █ █     █   █ █     █   █ █     █     █   █   █
█ █ █ ████  █   █ █  ██ █████ ████  █████ █████   █
█  ██ █     █   █ █   █ █   █ █         █ █   █   █
█   █ █████  ███   ███  █   █ █████ █████ █   █ █████
```

# NeoGaeshi

**A blue-team SecOps profile for [OpenCode](https://opencode.ai).** Read-only
defensive analyst posture, violet-dark TUI branding, 39 curated defensive
security skills, and [Engram](https://github.com/Gentleman-Programming/engram)
persistent memory — as a CLI (`neogaeshi`) and as a profile you run from the
repo root.

- **Author:** Ignacio del Corro (Naiam)
- **License:** MIT
- **Scope:** defensive security only — practice and work on systems you own or
  are explicitly authorized to test

## Install (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/naiamproducts/neogaeshi/main/install.sh | bash
```

The installer is idempotent and walks you through everything: prerequisites,
engram, OpenCode V2 (system), an isolated OpenCode V1 (1.19.3) runtime, the
profile, and the `neogaeshi` CLI.

The one manual step afterwards: connect a model provider with
`neogaeshi auth login` (or `/connect` inside the TUI).

Options: `--with-auth` (reuse an existing `~/.local/share/opencode/auth.json`
in the isolated V1 profile), `--force` (replace a conflicting
`~/.local/bin/neogaeshi`), `--uninstall`, `--help`.

## What gets installed where

| Component | Location | Touched again? |
|---|---|---|
| NeoGaeshi repo copy (V2 profile root) | `~/.local/share/neogaeshi` | on re-install |
| V1 profile config (hermetic) | `~/.config/neogaeshi-v1` | on re-install |
| OpenCode V1 runtime (1.19.3, isolated) | `~/.local/share/opencode-v1` | on re-install |
| `neogaeshi` CLI | `~/.local/bin/neogaeshi` (symlink) | on re-install |
| engram | `~/.local/bin/engram` | no |
| OpenCode V2 (system) | `~/.opencode/bin/opencode` | no |
| Your global opencode config/data | `~/.config/opencode`, `~/.local/share/opencode` | **never** |

Your existing OpenCode setup is never read or written. The V1 line runs inside
its own XDG sandbox; the V2 line runs the system `opencode` binary from the
profile root.

## Usage — two lines

```
neogaeshi              # V1 line: TUI with the home-screen logo, hermetic
neogaeshi -c           # continue the most recent V1 session
neogaeshi -s <id>      # resume a V1 session by id
neogaeshi v2           # V2 line: system OpenCode V2 from the profile root
neogaeshi --version    # both lines' status
neogaeshi help         # full usage
```

- **V1 line** — isolated OpenCode 1.19.3 with the violet theme and the
  tiered home-screen logo (V1 exposes a `home_logo` slot V2 removed).
- **V2 line** — modern OpenCode, launched from the profile root so the
  repo's theme, titlebar plugin, skills, and engram MCP are auto-discovered,
  with the NeoGaeshi theme applied for that launch only.

Inside either TUI: `/neogaeshi-triage`, `/neogaeshi-hunt`,
`/neogaeshi-timeline`, `/neogaeshi-detection`, `/neogaeshi-status`.

## The 39 skills

Curated defensive-only skills, loaded on demand:

- **Threat hunting & detection engineering** — hunt hypothesis frameworks,
  Sigma rule authoring, MITRE ATT&CK coverage mapping, YARA rule development,
  false-positive reduction
- **Incident response & DFIR** — alert triage (Elastic, Splunk), incident
  playbooks, timelines (Timesketch), disk / memory (Volatility 3) / network
  (Wireshark) / Linux / endpoint forensics
- **Log analysis & SIEM** — SIEM use cases, log source onboarding, Linux audit
  logs, Windows event logs in Splunk, DNS exfiltration analysis
- **Defense & hardening** — blue-team defense, network security, vulnerability
  scanning, malware analysis, credential-dumping / lateral-movement /
  ransomware / suspicious-PowerShell detection, supply-chain security, threat
  intelligence, crypto analysis, CSOC automation

## Engram memory

The profile ships with engram as a local MCP server: incidents and findings
persist across sessions.

- Findings are saved under the topic key prefix `neogaeshi/incidents/<incident-id>`.
- One incident = one topic key: as an incident evolves the same key is updated
  (same-topic upsert), never duplicated.
- Each finding records a verdict (`CONFIRMED` / `SUSPICIOUS` /
  `INFORMATIONAL`), evidence references, and next steps.
- The engram project is the current working directory's project (auto-detected).

## Requirements

- Linux (x86_64 or aarch64)
- `git`, `curl`, `node`, `npm` — the installer detects and installs missing ones
- An account with a model provider (or free OpenCode Zen models)

## Uninstall

```bash
bash ~/.local/share/neogaeshi/install.sh --uninstall
```

Removes the CLI symlink, the hermetic V1 config, the V1 runtime, and the repo
copy. It never touches your global opencode config or data; engram and the
system OpenCode binary are general-purpose and stay unless you remove them.

## Security posture

- **Read-only by default.** Shell and edit tools require explicit approval
  (`ask` permissions); `rm -rf`, `git push`, and `sudo` are denied outright.
- **Defensive scope only.** No exploitation, C2, or payload authoring — the
  analyst refuses those and offers the defensive alternative.
- **No sensitive data in git.** Evidence, scans, and reports go to
  `workspace/` (gitignored). Real identifiers are redacted; documentation
  examples use RFC 5737 ranges (`192.0.2.0/24`, `198.51.100.0/24`,
  `203.0.113.0/24`).

## License & credits

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Ignacio del Corro (Naiam).

Skills curated from two public MIT projects —
[26zl/cybersec-toolkit](https://github.com/26zl/cybersec-toolkit) and
[Masriyan/claude-code-cybersecurity-skill](https://github.com/Masriyan/claude-code-cybersecurity-skill) —
plus [engram](https://github.com/Gentleman-Programming/engram) and
[OpenCode](https://github.com/anomalyco/opencode) (formerly `sst/opencode`).
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
