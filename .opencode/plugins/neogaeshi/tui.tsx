import { Plugin } from "@opencode/plugin/tui"

// NeoGaeshi titlebar — compact single-line branding pinned to the top of the
// TUI. The built-in centered home logo has no documented replacement slot
// (verified against the cli.json schema and the slot list), so branding lives
// here: an intentional chrome row, not floating art.
const STATUS = " · SECOPS · READ-ONLY · AUDIT ON"

export default Plugin.define({
  id: "neogaeshi.tui",
  setup(context) {
    const Titlebar = () => (
      <box flexDirection="row">
        <text fg={context.theme.text.base}>NEOGAESHI</text>
        <text fg={context.theme.text.muted}>{STATUS}</text>
      </box>
    )

    // Prepend at app level so the row sits above every screen (home and
    // sessions) without replacing any built-in content.
    const unregister = context.ui.slot({
      prepend: "app",
      render: () => <Titlebar />,
    })

    return () => unregister()
  },
})
