// @ts-nocheck
/** @jsxImportSource @opentui/solid */
import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { useTerminalDimensions } from "@opentui/solid"
import { createMemo } from "solid-js"

// NeoGaeshi home-screen logo for the OpenCode V1 (1.x) TUI.
// V1 exposes a `home_logo` slot that V2 removed, so the V1 line gets a real
// home-screen replacement. Three tiers, all violet:
//   - full:    53-col x 5-row block art        (width >= 55 && height >= 13)
//   - medium:  36-col x 3-row wordmark         (width >= 42 && height >= 10)
//   - compact: single "NEOGAEshi" line         (anything smaller)

const id = "neogaeshi-logo"

// Full art: exactly 53 columns per row. Trailing spaces are significant.
const fullArt = [
  "█   █ █████  ███   ███   ███  █████ █████ █   █ █████",
  "██  █ █     █   █ █     █   █ █     █     █   █   █  ",
  "█ █ █ ████  █   █ █  ██ █████ ████  █████ █████   █  ",
  "█  ██ █     █   █ █   █ █   █ █         █ █   █   █  ",
  "█   █ █████  ███   ███  █   █ █████ █████ █   █ █████",
]

// Medium art: 3-row wordmark, 9 letters at 3 columns + 1-space separators,
// prefixed with the brand diamond. Widest row is 36 columns. Each letter is
// N E O G A E S H I, crafted and verified legible in tmux at 42-50 columns.
const mediumArt = [
  "◈ █ █ ▀▀▀ ▀▀▀ ▀▀▀ ▀  ▀▀▀ ▀▀▀ █ █ ▀▀▀",
  "  █▄▀ █▄  █ █ █▀▀ █▀█ █▄  ▀▀  ▀█▀  █",
  "  █ █ ▀▀▀ ▄▄▄ ▄▄▄ ███ ▀▀▀ ▄▄▄ █ █ ▄▄▄",
]

const compactArt = ["◈ NEOGAEshi"]

// Violet accent. Hex is supported by @opentui; fall back to "magenta" if a
// terminal or TUI build rejects the hex form.
const VIOLET = "#a855f7"

const Logo = () => {
  const dim = useTerminalDimensions()
  const lines = createMemo(() => {
    const term = dim()
    if (term.width >= 55 && term.height >= 13) return fullArt
    if (term.width >= 42 && term.height >= 10) return mediumArt
    return compactArt
  })

  return (
    <box flexDirection="column" alignItems="center">
      {lines().map((line) => (
        <text fg={VIOLET}>{line}</text>
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
