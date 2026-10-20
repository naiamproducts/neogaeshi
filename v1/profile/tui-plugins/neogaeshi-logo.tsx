// @ts-nocheck
/** @jsxImportSource @opentui/solid */
import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { useTerminalDimensions } from "@opentui/solid"
import { createMemo } from "solid-js"

// NeoGaeshi home-screen logo for the OpenCode V1 (1.x) TUI.
// V1 exposes a `home_logo` slot that V2 removed, so the V1 line gets a real
// home-screen replacement. Three tiers, mixed-case two-tone pixel art:
//   - full:    58-col x 5-row "NeoGaeshi" block art  (width >= 60 && height >= 13)
//   - medium:  40-col x 3-row "NeoGaeshi" wordmark  (width >= 42 && height >= 10)
//   - compact: single "◈ NeoGaeshi" line            (anything smaller)

const id = "neogaeshi-logo"

// Brand violet pair: bright body plus a deep-violet drop shadow. Hex is
// supported by @opentui; fall back to "magenta"/"blue" if a terminal or TUI
// build rejects the hex form.
const VIOLET = "#a855f7"
const SHADOW = "#6d28d9"

// --- Full tier -------------------------------------------------------------
// Mixed-case glyphs, 5 rows. Caps (N, G) and the h ascender use all five
// rows; lowercase x-height occupies rows 2-5; the i dot is a half block in
// row 1 so its empty lower half keeps the dot separated from the stem.
const glyphN = ["█   █", "██  █", "█ █ █", "█  ██", "█   █"]
const glyphE = ["     ", "▄███▄", "█   █", "█████", "▀███ "]
const glyphO = ["     ", "▄███▄", "█   █", "█   █", "▀███▀"]
const glyphG = ["▄███▀", "█   █", "█ ███", "█   █", "▀███▀"]
const glyphA = ["     ", "▄████", "█   █", "▀████", "    █"]
const glyphS = ["     ", "▄████", "█▄▄▄▄", "    █", "▀████"]
const glyphH = ["█    ", "█    ", "█████", "█   █", "█   █"]
const glyphI = ["▀", "█", "█", "█", "█"]

const glyphs = [glyphN, glyphE, glyphO, glyphG, glyphA, glyphE, glyphS, glyphH, glyphI]

// Exactly 58 columns per row (a trailing column so the i stem keeps its
// shadow); trailing spaces are significant.
const fullBody = Array.from({ length: 5 }, (_, row) => glyphs.map((g) => g[row]).join("  ") + " ")

// Two-tone pixel effect: every empty cell directly right of an ink cell
// mirrors that ink shape in the shadow tone — a one-cell drop shadow (a
// pixel-art extrusion to the right; the bottom row has no row below it).
const fullShadow = fullBody.map((line) => {
  const cells = line.split("")
  return cells
    .map((ch, c) => (ch === " " && cells[c - 1] !== " " ? cells[c - 1] : " "))
    .join("")
})

// --- Medium tier -----------------------------------------------------------
// 3-row wordmark, 40 columns. Caps use all three rows, lowercase rows 2-3,
// the i dot is a half block in row 1. Single violet: at this size the
// extrusion hurts legibility more than it adds style.
const mediumArt = [
  "◈ █ █           █▀▀                █   ▀",
  "  ███ █▀▀█ █▀▀█ █ ▄ █▀▄▄ █▀▀█ █▀▀▀ ███ █",
  "  █ █ ███▀ █▄▄█ █▄█ ▄▄██ ███▀ ▄▄▄█ █ █ █",
]

const compactArt = ["◈ NeoGaeshi"]

// --- Rendering --------------------------------------------------------------
// Each line becomes a row of same-color <text> segments. Segment widths are
// derived from the fixed-width grid, so columns always stay aligned.
const plainSegments = (line) => [{ text: line, color: VIOLET }]

const shadedSegments = (line, shade) => {
  const segments = []
  let tone = ""
  let buffer = ""
  for (let c = 0; c < line.length; c++) {
    const next = shade[c] !== " " ? "shadow" : "body"
    if (buffer !== "" && next !== tone) {
      segments.push({ text: buffer, color: tone === "shadow" ? SHADOW : VIOLET })
      buffer = ""
    }
    tone = next
    buffer += tone === "shadow" ? shade[c] : line[c]
  }
  if (buffer !== "") segments.push({ text: buffer, color: tone === "shadow" ? SHADOW : VIOLET })
  return segments
}

const fullLines = fullBody.map((line, row) => shadedSegments(line, fullShadow[row]))
const mediumLines = mediumArt.map(plainSegments)
const compactLines = compactArt.map(plainSegments)

const Logo = () => {
  const dim = useTerminalDimensions()
  const lines = createMemo(() => {
    const term = dim()
    if (term.width >= 60 && term.height >= 13) return fullLines
    if (term.width >= 42 && term.height >= 10) return mediumLines
    return compactLines
  })

  return (
    <box flexDirection="column" alignItems="center">
      {lines().map((line) => (
        <box flexDirection="row">
          {line.map((segment) => (
            <text fg={segment.color}>{segment.text}</text>
          ))}
        </box>
      ))}
    </box>
  )
}

const tui: TuiPlugin = async (api) => {
  api.slots.register({
    id,
    order: 100,
    slots: {
      home_logo() {
        return <Logo />
      },
    },
  })
}

const plugin = { id, tui }
export default plugin
