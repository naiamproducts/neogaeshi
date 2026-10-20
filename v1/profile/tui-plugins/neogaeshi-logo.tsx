// @ts-nocheck
/** @jsxImportSource @opentui/solid */
import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { useTerminalDimensions } from "@opentui/solid"
import { createMemo } from "solid-js"

// NeoGaeshi home-screen logo for the OpenCode V1 (1.x) TUI.
// V1 exposes a `home_logo` slot that V2 removed, so the V1 line gets a real
// home-screen replacement. Three tiers, chunky rounded wordmark in the
// OpenCode wordmark style:
//   - full:    64-col x 7-row "NeoGaeshi" block art  (width >= 66 && height >= 14)
//   - medium:  40-col x 3-row "NeoGaeshi" wordmark  (width >= 42 && height >= 10)
//   - compact: single "◈ NeoGaeshi" line            (anything smaller)

const id = "neogaeshi-logo"

// Two-tone WORD SPLIT (not a per-pixel shadow): "Neo" in dark blue,
// "Gaeshi" in bright violet. Hex is supported by @opentui; fall back to
// "blue"/"magenta" if a terminal or TUI build rejects the hex form.
const BLUE = "#2563eb"
const VIOLET = "#a855f7"

// --- Full tier -------------------------------------------------------------
// 7-row glyphs, OpenCode-wordmark anatomy: 2-cell strokes, half-block rounded
// corners (▄ on top rows, ▀ on bottom rows), open counters of >= 2 cells and a
// 1-2 column gap between letters (letters never touch). Caps (N, G), the h
// ascender and the i dot use all 7 rows; the lowercase x-height occupies rows
// 2-6, so rows 0-1 are empty above e/o/a/e/s.
const glyphN = ["███  ██", "████ ██", "████ ██", "██ ████", "██ ████", "██  ███", "██  ███"]
const glyphG = ["▄████▄", "██    ", "██    ", "██ ███", "██  ██", "██  ██", "▀████▀"]
const glyphH = ["██    ", "██    ", "█████▄", "██  ██", "██  ██", "██  ██", "██  ██"]
const glyphI = ["██", "  ", "██", "██", "██", "██", "██"]

// Lowercase: two empty rows above the x-height.
const lower = (rows) => ["      ", "      ", ...rows]
const glyphE = lower(["▄████▄", "██  ██", "██████", "██    ", "▀████ "]) // closed upper counter, open lower-right terminal
const glyphO = lower(["▄████▄", "██  ██", "██  ██", "██  ██", "▀████▀"]) // closed ring
const glyphA = lower([" ▄████", "    ██", "██████", "██  ██", "▀████▀"]) // open upper-left + closed bowl
const glyphS = lower(["▄████▄", "██    ", "██████", "    ██", "▀████▀"]) // alternating openings

const glyphs = [glyphN, glyphE, glyphO, glyphG, glyphA, glyphE, glyphS, glyphH, glyphI]

// Column gaps between the nine letters: 1 col where both neighbours show a
// straight vertical edge, 2 cols everywhere else. Total width is exactly 64
// columns, so the art fits a 66-column terminal with one column of margin.
const gaps = [1, 2, 1, 2, 2, 2, 1, 2]

const fullRows = Array.from({ length: 7 }, (_, row) => {
  const parts = []
  glyphs.forEach((glyph, i) => {
    parts.push(glyph[row])
    if (i < gaps.length) parts.push(" ".repeat(gaps[i]))
  })
  return parts.join("")
})

// Every row must carry the same column count or the centered rows drift apart.
const fullWidth = Math.max(...fullRows.map((row) => row.length))
const fullBody = fullRows.map((row) => row.padEnd(fullWidth, " "))

// The colour split lands on the G: everything left of it is "Neo" (blue),
// everything from the G on is "Gaeshi" (violet).
const SPLIT = glyphs.slice(0, 3).reduce((cols, glyph, i) => cols + glyph[0].length + gaps[i], 0)

// --- Medium tier -----------------------------------------------------------
// 3-row wordmark, 40 columns. Caps use all three rows, lowercase rows 2-3,
// the i dot is a half block in row 1. Single violet: at this size a second
// tone hurts legibility more than it adds style.
const mediumArt = [
  "◈ █ █           █▀▀                █   ▀",
  "  ███ █▀▀█ █▀▀█ █ ▄ █▀▄▄ █▀▀█ █▀▀▀ ███ █",
  "  █ █ ███▀ █▄▄█ █▄█ ▄▄██ ███▀ ▄▄▄█ █ █ █",
]

const compactArt = ["◈ NeoGaeshi"]

// --- Rendering --------------------------------------------------------------
// Each line becomes a row of same-color <text> segments. Segment widths are
// derived from the fixed-width grid, so columns always stay aligned: every
// row is exactly 64 columns (blue slice + violet slice), which keeps the
// centered rows on the same grid.
const fullLines = fullBody.map((line) => [
  { text: line.slice(0, SPLIT), color: BLUE },
  { text: line.slice(SPLIT), color: VIOLET },
])

const plainSegments = (line) => [{ text: line, color: VIOLET }]
const mediumLines = mediumArt.map(plainSegments)
const compactLines = compactArt.map(plainSegments)

const Logo = () => {
  const dim = useTerminalDimensions()
  const lines = createMemo(() => {
    const term = dim()
    if (term.width >= 66 && term.height >= 14) return fullLines
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
