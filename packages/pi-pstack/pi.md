# pstack in Pi

Read this binding once per session before following a pstack skill. The build has already translated
the executable Cursor tool names to Pi. Do not translate names again, and do not register aliases.

## Delegation

- Use the `subagent` tool. The routed skill names the generated `subagent_type`; do not substitute a
  different agent type because the Cursor spelling looks familiar. The profile names, bodies, tools,
  and worktree membership come from the Nix profile table; inspect `/subagents:settings` when needed.
- The generated `pstack-readonly` profile is a tool allowlist. It has `read`, `grep`, `find`, `ls`,
  and `codemode`; it has no shell, edit, write, or MCP. It is not an OS sandbox. Return review
  findings in the reply; use a writable profile such as `pstack-general-purpose` when a task needs a
  file artifact.
- Background work uses `run_in_background: true`. Resume a run through the `subagent` tool's native
  resume action and the agent ID it returned; do not paste a prior result in place of a resume when
  the run can still be resumed.
- `ask_parent` is available to children; `notify_parent` is available when mid-run updates are
  enabled. A blocked child ends its turn with `ask_parent`; answer it in the parent session, then
  resume the child.
- The parent session exclusively owns `ask_user_question` and the four todo tools (`TaskCreate`,
  `TaskGet`, `TaskList`, `TaskUpdate`). Children do not get them. A non-TUI session cannot ask the
  user through the questionnaire; report that interaction as blocked instead of inventing an answer.

## Models and thinking

- Workflows read `~/.pi/agent/pstack-models.md`. In dotnix, Home Manager publishes this as a read-only
  link from `modules/agents/pi/pstack-models.md`; setup edits the checkout source, not the runtime
  link or its store target. If the source checkout cannot be located, ask for it before writing.
  Source edits require repository validation, a system build, and user-approved activation before
  new sessions see them. Never replace the managed link with a writable copy.
- Role lines are `<role>: <provider>/<model> <thinking>`.
- Pass the first token as `model` and the second as `thinking`, unchanged. Configured levels are
  authoritative: do not raise, lower, or clamp them for workload or model capabilities. An unsupported
  level stops the workflow until the user confirms a configuration change. `auto` and `inherit-parent`
  mean omit both.
- Pi has no `-fast` speed variants and no Cursor model families. Use only model IDs that
  `pi --list-models` reports.
- `inherit-parent` and `auto` are valid only when the role line explicitly says so. They are not
  fallbacks for a missing file or line.
- Before a role spawn, check that `~/.pi/agent/pstack-models.md` and the required role line exist. If
  either is missing, stop and ask the user to run `/skill:setup-pstack`; do not choose a model or
  silently inherit the parent. If the subagent tool rejects a configured model ID, stop and report
  the rejection; do not guess another ID or thinking level.

## Workspace

- What pstack calls a cloud worker runs in a local git worktree through a worktree agent type. It is
  not a remote machine.
- A worktree child starts in its own worktree. Keep the working directory there, use relative paths,
  and do not `cd` to the parent checkout, create another worktree, or write into the parent checkout.
  If the task needs the parent checkout, stop and report it to the parent session. This is a
  working-directory rule, not an OS sandbox.
- `cloud_base_branch` is not a tool field. Put the requested base branch or commit in the brief and
  make the worker check it out in the isolated worktree before working. If the ref is missing or
  worktree creation fails, stop; never fall back to the shared checkout.
- A worktree run's workspace is removed when the run completes. Resume only while the workspace is
  live, such as when the child is waiting on `ask_parent`; after completion, use its result or rescue
  branch with a fresh agent.
- Worktree changes are saved to a rescue branch by the worktrees component, including a clean tree
  whose worker committed its own changes. Merge or discard them under the workflow's existing
  authorization.

## Skills, sessions, and host-only features

- Skill references resolve through Pi's native `read` of `SKILL.md`; `/skill:<name>` is the explicit
  user entry.
- Current and child conversations live in Pi session JSONL files under `~/.pi/agent/sessions/`. Use
  Obelisk for history instead of scanning unrelated project sessions.
- `deslop`, `control-cli`, and `control-ui` are bundled pstack skills. Use their `/skill:` entries;
  they are not Cursor-only steps.
- For skill authoring, read Pi's skill documentation and
  `poteto-mode/playbooks/authoring-a-skill.md`. Cursor's built-in `create-skill` is not a Pi tool.
- Cursor Automations, Bugbot, cloud dashboards, and the `make-bot-ui` webhook require Cursor
  services. Native timers (`/loop`), nested subagent coordination, and long-lived
  Orchestrate/Autopilot flows that need either capability are outside this Pi binding. Do not
  simulate any of them.
- If an unsupported step is optional and no later step depends on its result, say
  `Skipped in Pi: <step>. <reason>.` and continue. If later steps depend on it, stop and say
  `BLOCKED: <step> requires <missing capability>.`; do not report the workflow as successful.
- Authorization stays with the user and the repository's rules; a skipped or blocked step is not an
  approval.
