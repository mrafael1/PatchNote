@AGENTS.md

<!-- Thin pointer: AGENTS.md is the single source for every agent; this file imports it so
     Claude Code loads it too. On Windows use this @import, not a symlink (symlinks need
     Developer Mode, and Git checks them out as one-line text files). Verify what loaded with
     /context. HTML comments are stripped before injection. -->

## Claude Code only

- Use the PowerShell tool for `tools\*.ps1` and the Bash tool for `.check/*/gates.sh`.
- Run `check.ps1` with `timeout: 600000` or `run_in_background: true`. Run `check.ps1 -BotRuns`, gate scripts and `export.ps1` with `run_in_background: true` and wait for the completion notice (no sleep, no polling). Then read the log for `CHECK PASSED` and the `summary` lines.
- Open every capture PNG with the Read tool before describing it.
- godot-ai MCP: read-only use (`editor_screenshot`, `logs_read`, scene hierarchy). Never use `project_run` or `game_manage`: they boot the start screen on the owner's real save with no way to pass `--inert-save`. If the editor is live, do not edit a scene it has open; make file edits, then note in the report that the editor needs a reload. The CLI gates in AGENTS.md are the only proof.
- Auto memory may hold an owner decision newer than PLAN.md. If so, follow it and add the decision to PLAN.md in the same milestone, so PLAN.md stays the source for every agent.
