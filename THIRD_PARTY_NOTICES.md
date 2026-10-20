# Third-Party Notices

NeoGaeshi bundles or installs components from the following projects. All are
used under their respective open-source licenses.

## Bundled skills

The 39 curated defensive-security skills under `skills/` are derived from two
public repositories, both MIT-licensed:

- **[26zl/cybersec-toolkit](https://github.com/26zl/cybersec-toolkit)** — MIT.
  Source of the descriptively named defensive skills (e.g.
  `performing-alert-triage-with-elastic-siem`,
  `building-detection-rules-with-sigma`, `performing-memory-forensics-with-volatility3`).
  Each derived skill directory retains its upstream `LICENSE` file.
- **[Masriyan/claude-code-cybersecurity-skill](https://github.com/Masriyan/claude-code-cybersecurity-skill)** — MIT.
  Source of the numbered category skills (e.g. `06-threat-hunting`,
  `07-incident-response`, `12-log-analysis`, `15-blue-team-defense`).

Modifications: documentation examples in the bundled skills were rewritten to
use [RFC 5737](https://www.rfc-editor.org/rfc/rfc5737) documentation IP
ranges instead of private LAN addresses, so no example can be mistaken for a
real network. No functional content was changed.

## Installed at setup time (not bundled)

The installer downloads these; they are not vendored in this repository:

- **[engram](https://github.com/Gentleman-Programming/engram)** — MIT.
  Local persistent memory for AI agents, used as the profile's MCP memory
  server (`engram mcp --tools=agent`).
- **[OpenCode](https://github.com/anomalyco/opencode)** (formerly
  `sst/opencode`) — MIT. The agent CLI this whole profile is built on.
  - The V2 line uses the system OpenCode install (official installer).
  - The V1 line installs `opencode-ai@1.19.3` from npm (same project, older
    major line) into an isolated prefix.
