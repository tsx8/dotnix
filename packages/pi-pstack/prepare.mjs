#!/usr/bin/env node
import { createHash } from "node:crypto";
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { spawnSync } from "node:child_process";

const [, , srcRoot, outDir] = process.argv;
if (!srcRoot || !outDir) {
  console.error("usage: prepare.mjs <cursor-plugins-src> <out-dir>");
  process.exit(2);
}

const pstackRoot = process.env.PSTACK_ROOT;
if (!pstackRoot) {
  console.error("PSTACK_ROOT must name the installed pstack package directory");
  process.exit(2);
}

const HARNESS = join(srcRoot, "harness", "pstack", "claude-code");
const SKILL_PATH = `${pstackRoot}/skills/poteto-mode/SKILL.md`;
const SKILL_READ_PREFIX = `cat ${pstackRoot}/skills/`;

// The Nix agent-profile table is the only source for these names and the Cursor-to-profile mapping.
// Refuse to build from an independent fallback table; the package passes both values from Nix.
const profileMapJson = process.env.PSTACK_PROFILE_MAP;
const agentTypesJson = process.env.PSTACK_AGENT_TYPES;
if (!profileMapJson || !agentTypesJson) {
  console.error("PSTACK_PROFILE_MAP and PSTACK_AGENT_TYPES must come from the Nix profile table");
  process.exit(2);
}
const PROFILE = JSON.parse(profileMapJson);
const AGENT_TYPES = agentTypesJson.split(",").map((name) => name.trim()).filter(Boolean);
if (AGENT_TYPES.length === 0) {
  console.error("PSTACK_AGENT_TYPES is empty");
  process.exit(2);
}
for (const key of ["generalPurpose", "readonly", "cloud", "local"]) {
  if (typeof PROFILE[key] !== "string" || !AGENT_TYPES.includes(PROFILE[key])) {
    console.error(`PSTACK_PROFILE_MAP '${key}' does not name a PSTACK_AGENT_TYPES entry`);
    process.exit(2);
  }
}

// Exact literals from pstack 0.15.26. Counts are part of the contract; see the check below.
const RULES = [
  {
    name: "adapter-line",
    re: /In Claude Code, read \[the Claude Code adapter\]\(\.\.\/\.\.\/docs\/harness\/claude-code\.md\) once per session before you follow this skill\. It maps the Cursor names in pstack skills to Claude Code\./g,
    to: "In Pi, read [the Pi binding](../../pi.md) once per session before you follow this skill. It records the harness differences that this skill does not state itself.",
    expect: 21,
  },
  {
    name: "model-file-path",
    re: /~\/\.cursor\/rules\/pstack-models\.mdc/g,
    to: "~/.pi/agent/pstack-models.md",
    expect: 8,
  },
  {
    name: "model-file-name",
    re: /pstack-models\.mdc/g,
    to: "pstack-models.md",
    expect: 4,
  },
  {
    name: "ask-question-token",
    re: /`AskQuestion`/g,
    to: "`ask_user_question`",
    expect: 4,
  },
  {
    name: "task-token",
    re: /`Task`/g,
    to: "`subagent`",
    expect: 9,
  },
  {
    name: "ask-question-word",
    re: /\bAskQuestion\b/g,
    to: "ask_user_question",
    expect: 2,
  },
  {
    name: "omit-task-model",
    re: /omit Task `model`/g,
    to: "omit `model` and `thinking`",
    expect: 1,
  },
  {
    name: "setup-file-wording",
    re: /always-applied rule that sets|when the rule records one\. With no rule|rule shape shown in step 5|the rule or the line is missing|`\/skill:setup-pstack` rule/g,
    to: (m) => ({
      "always-applied rule that sets": "model preference file that sets",
      "when the rule records one. With no rule": "when the file records one. With no file",
      "rule shape shown in step 5": "file shape shown in step 5",
      "the rule or the line is missing": "the file or the line is missing",
      "`/skill:setup-pstack` rule": "`/skill:setup-pstack` file",
    })[m],
    expect: 4,
  },
  {
    name: "model-rule-file",
    re: /`pstack-models\.md` rule/g,
    to: "`pstack-models.md` file",
    expect: 4,
  },
  {
    name: "slug-words",
    re: /\bslugs\b/g,
    to: "model IDs",
    expect: 1,
  },
  {
    name: "slug-word",
    re: /(?<![<\w-])\bslug\b(?![>\w-])/g,
    to: "model ID",
    expect: 20,
  },
  {
    name: "reasoning-speed",
    re: /reasoning level and fast or standard speed/g,
    to: "thinking level",
    expect: 24,
  },
  {
    name: "task-compounds",
    re: /\bTask (tool|call|calls|spawn|subagent|schema|response|prompts?)\b/g,
    to: "subagent $1",
    expect: 11,
  },
  {
    name: "general-purpose-type",
    re: /subagent_type: generalPurpose/g,
    to: `subagent_type: ${PROFILE.generalPurpose}`,
    expect: 5,
  },
  {
    name: "readonly-prose",
    re: /agent mode \((?:`?readonly: false`?|readonly strips MCPs?)\)/g,
    to: `agent mode (\`${PROFILE.generalPurpose}\`, which keeps MCP)`,
    expect: 3,
  },
  {
    name: "readonly-true",
    re: /`readonly: true`/g,
    to: `\`subagent_type: ${PROFILE.readonly}\``,
    expect: 2,
  },
  {
    name: "readonly-false",
    re: /`readonly: false`/g,
    to: `\`subagent_type: ${PROFILE.generalPurpose}\``,
    expect: 1,
  },
  {
    name: "cloud-environment",
    re: /`environment: "cloud"`/g,
    to: `\`subagent_type: ${PROFILE.cloud}\``,
    expect: 2,
  },
  {
    name: "local-environment",
    re: /`environment: "local"`/g,
    to: `\`subagent_type: ${PROFILE.local}\``,
    expect: 1,
  },
  {
    name: "claude-adapter-readme",
    re: /claude code prefixes plugin commands and agents, so `\/poteto-mode` is `\/pstack:poteto-mode`\. the \[claude code adapter\]\(\.\/docs\/harness\/claude-code\.md\) maps every other cursor name\. in claude code, `\/pstack:setup-pstack` writes your model choices to `~\/\.claude\/rules\/pstack-models\.md`, and a step that needs a cursor-only feature, such as bugbot or automations, is skipped with a one-line note\./g,
    to: "pi loads this package natively. pi has no plugin prefix: use `/skill:poteto-mode` and read [the pi binding](./pi.md) once per session. `/skill:setup-pstack` configures your role models using the editable source described in the binding, and a step that needs a cursor-only feature, such as bugbot or automations, is skipped with a one-line note.",
    expect: 1,
  },
  {
    name: "poteto-agent-search",
    re: /Use the absolute path your parent gave you\. With no path, before any other work, search `~\/\.cursor\/plugins\/` for a file whose path ends in `skills\/poteto-mode\/SKILL\.md`\. If more than one file matches, use the copy whose `\.cursor-plugin\/plugin\.json` has the highest `version`\. Your skill catalog hides this skill, so a missing catalog entry does not mean pstack is absent\. If no such file exists, stop and tell your parent\./g,
    to: `Read \`${SKILL_PATH}\` in full before any work when your parent gives no path. If that file is missing, stop and tell your parent.`,
    expect: 1,
  },
  {
    name: "create-skill-authoring",
    re: /1\. Use the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)\./g,
    to: "1. Read Pi's skill format documentation (`pi` docs `skills.md`) and follow the authoring shape in this playbook. Pi has no separate skill-authoring command.",
    expect: 1,
  },
  {
    name: "create-skill-default-policy",
    re: /Agent-facing prose also follows the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)\./g,
    to: "Agent-facing prose also follows Pi's skill format documentation.",
    expect: 1,
  },
  {
    name: "automate-create-skill-description",
    re: /via create-skill \+ unslop/g,
    to: "via the Pi skill authoring playbook + unslop",
    expect: 1,
  },
  {
    name: "automate-create-skill-orchestration",
    re: /Cursor's built-in `create-skill` \(authoring\)/g,
    to: "Pi's skill authoring playbook `poteto-mode/playbooks/authoring-a-skill.md` (authoring)",
    expect: 1,
  },
  {
    name: "automate-create-skill-use",
    re: /Use Cursor's built-in `create-skill` skill to author the skill\./g,
    to: "Use Pi's skill authoring playbook (`poteto-mode/playbooks/authoring-a-skill.md`) to author the skill.",
    expect: 1,
  },
  {
    name: "automate-create-skill-yaml",
    re: /follow `create-skill`'s YAML rules/g,
    to: "follow Pi's skill YAML rules (`pi` docs `skills.md`)",
    expect: 1,
  },
  {
    name: "automate-create-skill-guidelines",
    re: /Apply the \*\*unslop\*\* skill and `create-skill`'s writing guidelines/g,
    to: "Apply the **unslop** skill and Pi's skill authoring guidelines",
    expect: 1,
  },
  {
    name: "automate-create-skill-benchmark",
    re: /A `create-skill`-style test\/iterate benchmark loop/g,
    to: "A skill-authoring test/iterate benchmark loop",
    expect: 1,
  },
  {
    name: "automate-create-skill-alone",
    re: /`create-skill` alone/g,
    to: "the Pi skill authoring playbook alone",
    expect: 1,
  },
  {
    name: "reflect-create-skill-substantive",
    re: /hand to Cursor's built-in `create-skill` skill and run its draft \/ test \/ iterate loop/g,
    to: "follow Pi's skill authoring playbook (`poteto-mode/playbooks/authoring-a-skill.md`) and run its draft / test / iterate loop",
    expect: 1,
  },
  {
    name: "reflect-create-skill-tune",
    re: /hand to `create-skill` and run its description-optimization loop/g,
    to: "follow Pi's skill authoring playbook and run its description-optimization loop",
    expect: 1,
  },
  {
    name: "reflect-create-skill-new",
    re: /`new skill via create-skill: <kebab-name>`: hand creation to `create-skill`\./g,
    to: "`new skill: <kebab-name>`: create it with Pi's skill authoring playbook.",
    expect: 1,
  },
  {
    name: "synthesizer-create-skill-token",
    re: /new skill via create-skill:/g,
    to: "new skill:",
    expect: 2,
  },
  {
    name: "synthesizer-create-skill-draft",
    re: /<draft a new skill via create-skill>/g,
    to: "<draft a new skill with Pi's authoring playbook>",
    expect: 1,
  },
  {
    name: "poteto-help-create-skill",
    re: /`\/loop` and `\/create-skill` are Cursor built-ins\./g,
    to: "`/loop` and Cursor's skill authoring are Cursor built-ins. Pi has no timer command; use the bundled skill-authoring playbook.",
    expect: 1,
  },
  {
    name: "why-mcp-environment",
    re: /Before spawning investigators, list the available MCPs from the Cursor environment\. Use the available-tools map when present\. Otherwise inspect the `mcps\/` directory Cursor exposes for enabled MCP servers\./g,
    to: "Before spawning investigators, list the MCP tools available in this Pi session from the tool declarations. Do not look for a Cursor `mcps/` directory.",
    expect: 1,
  },
  {
    name: "cursor-team-kit-plugin",
    re: /the `cursor-team-kit` plugin/g,
    to: "the bundled pstack package",
    expect: 5,
  },
  {
    name: "cursor-team-kit-from",
    re: /from `cursor-team-kit`/g,
    to: "from the bundled pstack package",
    expect: 7,
  },
  {
    name: "cursor-team-kit-publishes",
    re: /`cursor-team-kit` publishes/g,
    to: "The bundled pstack package includes",
    expect: 1,
  },
  {
    name: "worktree-cleanup-cursor-path",
    re: /`\.cursor\/worktrees\/myrepo\/x`/g,
    to: "a project-local worktree directory",
    expect: 1,
  },
  {
    name: "cloud-base-branch",
    re: /When a worker must start from a non-default pushed branch, pass `cloud_base_branch`\./g,
    to: "When a worker must start from a non-default pushed branch, name that base branch or commit in its brief and require it to check the ref out in the isolated worktree before working.",
    expect: 1,
  },
  {
    name: "transcripts-root",
    re: /~\/\.cursor\/projects/g,
    to: "~/.pi/agent/sessions",
    expect: 6,
  },
  {
    name: "agent-transcripts",
    re: /agent-transcripts/g,
    to: "session records",
    expect: 10,
  },
  {
    name: "global-skills-path",
    re: /~\/\.cursor\/skills/g,
    to: "~/.pi/agent/skills",
    expect: 5,
  },
  {
    name: "project-skills-path",
    re: /\.cursor\/skills/g,
    to: ".pi/skills",
    expect: 14,
  },
  {
    name: "cursor-plugins-path",
    re: /~\/\.cursor\/plugins|\.cursor-plugin/g,
    to: "the pstack package directory",
    expect: 3,
  },
  {
    name: "principle-command",
    re: /\/principle-<name>/g,
    to: "/skill:principle-<name>",
    expect: 1,
  },
  {
    name: "plan-installed-bundled-reads",
    re: /git show origin\/main:pstack\/skills\//g,
    to: SKILL_READ_PREFIX,
    expect: 4,
  },
  {
    name: "plan-installed-control-read",
    re: /git show origin\/main:(<control skill path>)/g,
    to: "cat $1",
    expect: 1,
  },
  {
    name: "plan-installed-skill-paths",
    re: /(?<![\w/.-])pstack\/skills\//g,
    to: `${pstackRoot}/skills/`,
    expect: 6,
  },
  {
    name: "plan-resolved-read-wording",
    re: /Read these from trunk at program start\./g,
    to: "Read these resolved skill files at program start.",
    expect: 1,
  },
  {
    name: "plan-installed-tick-read",
    re: /Re-read the execution playbook from trunk\./g,
    to: "Re-read the installed execution playbook.",
    expect: 1,
  },
];

const sourceSkills = readdirSync(join(HARNESS, "skills")).filter((name) =>
  existsSync(join(HARNESS, "skills", name, "SKILL.md")),
);
const COMMANDS = [...new Set([...sourceSkills, "deslop", "control-cli", "control-ui"])];
const commandPattern = COMMANDS.map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
const bareCommandPattern = new RegExp(`(?<![./\\w])/(?:${commandPattern})\\b`);
const COMMAND_RULE = {
  name: "skill-command",
  re: new RegExp(`(^|[^/.\\w])/(${COMMANDS.join("|")})\\b`, "g"),
  to: "$1/skill:$2",
  expect: 482,
};


// setup-pstack is rewritten from Claude Code's rule-file model to Pi's `pi --list-models` and
// `provider/model + thinking` semantics. These blocks are the only semantic rewrites in this port.
const SETUP_REWRITES = [
  {
    name: "setup-description",
    re: /Configure which models pstack uses per role and at what reasoning budget\. Detects your available models and writes an always-applied rule that overrides the skill defaults\./,
    to: "Configure which models pstack uses per role and at what thinking budget. Detects your available models and writes the model preference file that overrides the skill defaults.",
  },
  {
    name: "setup-role-shape",
    re: /The default role-to-model mapping is the rule shape shown in step 5 below\./,
    to: "The role list and ordering are the shape shown in step 5 below; its values are placeholders until you choose detected models.",
  },
  {
    name: "setup-budget-default",
    re: /With no rule, say that `large` matches the skill defaults\./,
    to: "With no file, say that `large` targets xhigh.",
  },
  {
    name: "setup-role-default",
    re: /Otherwise start from those defaults\./,
    to: "Otherwise start from the role list and choose detected models.",
  },
  {
    name: "setup-detect",
    re: /Enumerate the model slugs you can pass to a `Task` subagent in this session\. That is the dependable source\. If Cursor also exposes a models API or CLI that lists the user's entitled models, prefer it for completeness\. If you cannot detect any, ask the user to paste the slugs they have access to\. Never write a real slug you have not confirmed is available\. The aliases `inherit-parent` and `auto` are always valid even though they are not detected slugs\./,
    to: "Run `pi --list-models` with the Pi executable that hosts this session and use only the `provider/model` entries it prints. The thinking level is a separate value, not part of the model ID. If the command fails, ask the user which model IDs they want to use. Never write a real model ID you have not confirmed is available. The aliases `inherit-parent` and `auto` are always valid even though they are not detected model IDs.",
  },
  {
    name: "setup-budget",
    re: /\*\*\(b\) Apply it\.\*\*[\s\S]*?`grok-4\.7-medium-fast`\./,
    to: "**(b) Apply it.** Start from the role list in step 5 and assign detected models to roles by workload; the listed values are placeholders, not defaults. On a re-run keep any role you changed by model family, list, or alias (`inherit-parent`, `auto`). `unlimited`, `large`, `medium`, and `small` set the thinking value of every real entry, panel entries included, to `max`, `xhigh`, `high`, or `medium`, on the ladder `max` > `xhigh` > `high` > `medium` > `low`. If a model does not offer that level, use the highest level it reports at or below the target, else mark the role as needing a choice. `inherit-parent` and `auto` do not change. Use only model IDs from step 1, never a Cursor model ID or a fast speed suffix. If you cannot choose a model for a role, propose `inherit-parent` and use it only after the user confirms it in the confirmation.",
  },
  {
    name: "setup-write",
    re: /### 5\. Write the rule[\s\S]*?```\n\n(?=### 6\.)/,
    to: `### 5. Write the file

Write the editable source selected in step 2 with a \`# budget\` line naming the chosen label and its target thinking level, and one line per role, using the same labels poteto-mode uses. Write no frontmatter. Replace every placeholder with a model ID detected in step 1. Overwrite the whole editable source so re-runs stay idempotent; never replace a Nix-managed runtime link or write into \`/nix/store\`. Shape:

\`\`\`
# pstack model configuration. One line per required role. A missing line stops a workflow until setup fills it.
# \`inherit-parent\` or \`auto\` as an explicit value: the role runs on the parent model (omit \`model\` and \`thinking\`). Alias entries in a panel list still count toward its fan-out.
# budget: large (xhigh)
feature, refactoring: provider/model-a high
bug-fix: provider/model-a high
perf-issue: provider/model-a high
hillclimb: provider/model-a high
judgment and prose: provider/model-b xhigh
hardest tasks: provider/model-b xhigh
how explorer: provider/model-a high
how explainer: provider/model-b xhigh
why investigators: provider/model-a high
why synthesizer: provider/model-b xhigh
reflect tooling: provider/model-a high
reflect judgment, divergent, synthesizer: provider/model-b xhigh
arena runners: provider/model-b xhigh, provider/model-a high
arena cross-judge pool: provider/model-b xhigh, provider/model-a high
swarm workers: provider/model-a high
architect runners: provider/model-b xhigh, provider/model-a high
interrogate reviewers: provider/model-b xhigh, provider/model-a high
\`\`\`

Each value is \`<provider>/<model> <thinking>\`; a panel entry is one such value per comma.

`,
  },
  {
    name: "poteto-default-models",
    re: /configurable via `\/setup-pstack`\. Defaults `grok-4\.7-xhigh-fast` for code, `claude-opus-5-5-xhigh` for prose and judgment\)/,
    to: "configurable via `/skill:setup-pstack`; its file supplies real Pi model IDs. Without a configured line, use the parent model)",
  },
  {
    name: "poteto-hardest-default",
    re: /go to your strongest judgment model \(`claude-opus-5-5-xhigh`\)/,
    to: "go to your strongest judgment model (the configured `hardest tasks` line, or the parent model when that line is absent)",
  },
  {
    name: "poteto-match-model",
    re: /\*\*Match the model to the job\.\*\*[\s\S]*?If the Task tool rejects the adjusted slug, do not try another adjusted slug\. Use the role's line or default and say so\./,
    to: "**Use the configured model and thinking level.** Before each spawn, read the required role or panel entry and pass its provider/model and thinking level unchanged. Do not raise, lower, or clamp the configured level for task complexity, judgment, urgency, or model capabilities. If the model or thinking level is unsupported or rejected, stop and report it; do not guess another value. Change preferences only through setup and user confirmation. Verification uses the `swarm workers` entry. A role on `auto` or `inherit-parent` stays on the parent model: omit both `model` and `thinking`.",
  },
  {
    name: "setup-confirm",
    re: /Tell the user the rule was written and that it applies to new sessions\. Re-running this skill updates it\./,
    to: "Tell the user which editable source was written. For dotnix-managed preferences, the runtime file changes only after repository validation, a system build, and user-approved activation; do not activate automatically or create a writable runtime copy. New sessions then read the published preferences. For an unmanaged home file, the edit applies to new sessions directly. Re-running this skill updates the selected editable source.",
  },
];


// Applied after the generic rewrites, against their converted wording.
const POST_REWRITES = [
  {
    name: "setup-runtime-path",
    re: /Write `~\/\.pi\/agent\/pstack-models\.md`, an model preference file that sets pstack's model per role\./g,
    to: "Configure pstack's per-role models. Workflows read `~/.pi/agent/pstack-models.md`; setup edits the source selected in step 2.",
  },
  {
    name: "setup-editable-source",
    re: /### 2\. Load current state\n\n/g,
    to: "### 2. Load current state\n\nSelect the editable source before loading or changing preferences:\n\n- Look in the working directory and its ancestors for a dotnix checkout containing both `flake.nix` and `modules/agents/pi/pstack-models.md`, or use a checkout explicitly supplied by the user. When found, use that repository file even if the runtime file is absent or belongs to an older generation.\n- Otherwise inspect `~/.pi/agent/pstack-models.md`. If it is a symlink resolving into `/nix/store/`, stop and ask for the source checkout before writing. Never edit the store, unlink or replace the managed runtime path, or create a writable copy there.\n- Only when no repository source or Nix-managed runtime file is found, use `~/.pi/agent/pstack-models.md` as the editable source.\n\nUse the selected editable source for both the current choices and the final write.\n\n",
  },
  {
    name: "setup-load-editable-source",
    re: /If `~\/\.pi\/agent\/pstack-models\.md` already exists, read it and treat its/g,
    to: "If the selected editable source already exists, read it and treat its",
  },
  {
    name: "why-agent-mode",
    re: new RegExp(`\`generalPurpose\` with \`subagent_type: ${PROFILE.generalPurpose}\``, "g"),
    to: `\`${PROFILE.generalPurpose}\``,
  },
  {
    name: "why-readonly",
    re: /\*\*Do not use readonly\/Ask mode\.\*\* It strips MCP access/g,
    to: `**Do not use the \`${PROFILE.readonly}\` profile.** It strips MCP access`,
  },
  {
    name: "recall-paths",
    re: /Transcripts live at `~\/.pi[\s\S]*?Every line is one chat message\./g,
    to: "Pi sessions live at `~/.pi/agent/sessions/--<workspace-slug>--/<timestamp>_<session-id>.jsonl`, where `<workspace-slug>` is the workspace path with the leading slash dropped and each \"/\" turned into \"-\" (so `/home/you/proj` becomes `home-you-proj`). Every line is one session record. Use Obelisk for history across sessions and workspaces.",
  },
  {
    name: "session-dir-phrases",
    re: /(?:the active workspace's|the workspace's|this run's transcript under the active workspace's) `session records\/` directory/g,
    to: "this workspace's Pi session directory under `~/.pi/agent/sessions/`",
    expect: 4,
  },
  {
    name: "session-records-dir",
    re: /`session records\/`/g,
    to: "`~/.pi/agent/sessions/`",
    expect: 2,
  },
  {
    name: "session-records-ls",
    re: /<session records>\/\*\.jsonl <session records>\/\*\/\*\.jsonl <session records>\/\*\/subagents\/\*\.jsonl/g,
    to: "~/.pi/agent/sessions/*/*.jsonl",
  },
  {
    name: "reflect-active-session",
    re: /Before fanning out, find this conversation's transcript[\s\S]*?If none matches, pass a tight digest of the session instead\./g,
    to: "Before fanning out, use the current Pi session file from `$PI_SESSION_FILE`, the absolute path the Pi bash tool exposes. If it is unset (an ephemeral session), pass a tight digest of the conversation instead of searching other sessions. Do not glob across `~/.pi/agent/sessions/*/`; that crosses workspace boundaries and reads private chats from unrelated projects. Use Obelisk only for explicitly scoped history.",
    expect: 1,
  },
  {
    name: "readme-install",
    re: /## install\n\n[\s\S]*?\n\n## get started/g,
    to: "## install\n\npi loads this package natively through its `packages` setting. There is no marketplace or plugin install. `/skill:setup-pstack` configures role preferences using the editable source described in [the Pi binding](./pi.md). A step that needs a cursor-only feature, such as bugbot or automations, follows that binding's skip/blocked rules.\n\n## get started",
    expect: 1,
  },
  {
    name: "readme-model-defaults",
    re: /out of the box the mode splits work by model strength: code delegates \(feature, refactoring, bug fix, perf, hillclimb\) go to grok, while the hardest changes, prose, and judgment go to opus 5\.5\. the default panel is opus 5\.5 \/ grok\. \[`\/skill:setup-pstack`\]\(\.\/skills\/setup-pstack\/SKILL\.md\) changes any of it\./g,
    to: "role models come only from `/skill:setup-pstack` and `~/.pi/agent/pstack-models.md`; no role has an implicit default. [`/skill:setup-pstack`](./skills/setup-pstack/SKILL.md) configures the role list.",
    expect: 1,
  },
  {
    name: "readme-extras",
    re: /## not shipped here[\s\S]*?\n\n## why are there no planning skills\?/g,
    to: "## bundled extras\n\n`deslop`, `control-cli`, and `control-ui` are bundled with pstack in this Pi package; no separate plugin install is required. Cursor's `/create-skill` and `/autopilot` are Cursor built-ins with no Pi equivalent. Use Pi's skill authoring playbook for skills, and the [babysit playbook](./skills/poteto-mode/playbooks/babysit.md) for PR-status requests.\n\n## why are there no planning skills?",
    expect: 1,
  },
  {
    name: "help-custom-mode-mention",
    re: /mention once that a Custom Mode keeps it on/g,
    to: "mention once that each new task can start with `/skill:poteto-mode`",
    expect: 1,
  },
  {
    name: "help-no-config",
    re: /- No `~\/\.pi\/agent\/pstack-models\.md` means `\/skill:setup-pstack` hasn't run for this user, so every role uses its default model\./g,
    to: "- No `~/.pi/agent/pstack-models.md` means `/skill:setup-pstack` has not run; role-based workflows stop until it does.",
    expect: 1,
  },
  {
    name: "help-role-default",
    re: /- Later: answer their question, and add one line saying every role keeps its default model until they run `\/skill:setup-pstack`\./g,
    to: "- Later: answer their question, and add one line saying every role requires setup before role-based workflows.",
    expect: 1,
  },
  {
    name: "guide-install-heading",
    re: /## Install the plugin/g,
    to: "## Load the package",
    expect: 1,
  },
  {
    name: "guide-worktree-heading",
    re: /## Give parallel work its own machine\n\nIf you run several agents/g,
    to: "## Give parallel work its own worktree\n\nIf you run several agents",
    expect: 1,
  },
  {
    name: "guide-worktree-duplicate",
    re: /\n\nWhen the work has to stay local, ask for a worktree up front:/g,
    to: "",
    expect: 1,
  },
  {
    name: "guide-worktree-isolation",
    re: /If you run several agents against one repository on one computer, they will fight over the working tree, the ports, and the build output\. The cleanest isolation is a \[cloud subagent\]\(https:\/\/cursor\.com\/docs\/subagents#cloud-subagents\)\. Each one gets its own VM and branch, so it can install dependencies, run your app, and record video of the result without touching your machine\. Type `\/in-cloud` before the task, or ask the parent chat to hand work to cloud subagents\./g,
    to: "If you run several agents against one repository on one computer, they will fight over the working tree, the ports, and the build output. Pi uses an independent local git worktree, not a remote VM: each worker gets its own branch and working tree, can install dependencies and run the app on this machine, and never touches the parent checkout. Ask for a worktree up front:",
    expect: 1,
  },
  {
    name: "help-cloud-workers",
    re: /\| Run parallel checks over slices, or race workers, as cloud agents \|/g,
    to: "| Run parallel checks over slices, or race workers, in isolated worktrees |",
    expect: 1,
  },
  {
    name: "help-cloud-worktrees",
    re: /\| Parallel agents overwrote each other \| Give each agent its own worktree, or run them as cloud agents, which each get their own machine\. \|/g,
    to: "| Parallel agents overwrote each other | Give each agent its own local git worktree. |",
    expect: 1,
  },
  {
    name: "guide-cloud-worktrees",
    re: /- \*\*Parallel agents in one worktree\.\*\* They overwrite each other, and nobody can tell which agent changed what\. Run them as cloud agents, or say "own worktree per attempt"\./g,
    to: "- **Parallel agents in one worktree.** They overwrite each other, and nobody can tell which agent changed what. Give each attempt its own local git worktree.",
    expect: 1,
  },
  {
    name: "readme-custom-mode",
    re: /to keep \[`\/skill:poteto-mode`\]\(\.\/skills\/poteto-mode\/SKILL\.md\) on across turns, pick it from the `\/` menu and press option\+enter \(mac\) or alt\+enter \(windows\) instead of enter\. that makes it a \[custom mode\]\(https:\/\/cursor\.com\/docs\/skills#using-a-skill-as-a-custom-mode\), which cursor offers in the agents window and the cli\. it stays in context every turn until you exit the mode\. plain enter attaches it to one message only\./g,
    to: "pi applies [`/skill:poteto-mode`](./skills/poteto-mode/SKILL.md) to one message. start each task with that explicit entry; there is no persistent mode.",
    expect: 1,
  },
  {
    name: "readme-loop",
    re: /\[`\/skill:poteto-mode`\]\(\.\/skills\/poteto-mode\/SKILL\.md\) works extremely well with cursor's `\/loop` command\. you can make cursor work for many hours without sacrificing rigor\./g,
    to: "pi has no native timer loop. an autonomous run that needs one is BLOCKED under the binding; do not simulate it.",
    expect: 1,
  },
  {
    name: "readme-one-message",
    re: /pick `\/skill:poteto-mode` from the `\/` menu before you type your task, so cursor attaches the skill to the message\./g,
    to: "start each task with `/skill:poteto-mode`; Pi applies it to one message.",
    expect: 1,
  },
  {
    name: "readme-create-skill",
    re: /Cursor's `\/create-skill` and `\/autopilot` are Cursor built-ins with no Pi equivalent\./g,
    to: "Cursor's skill authoring and autopilot are built-ins with no Pi equivalent.",
    expect: 1,
  },
  {
    name: "readme-plan-mode",
    re: /cursor already has a great plan mode which works great with pstack\. but personally, i don't believe in planning\./g,
    to: "a plan is optional. but personally, i don't believe in planning.",
    expect: 1,
  },
  {
    name: "readme-benny",
    re: /pstack also ships a dormant \[benny automation pack\]\(https:\/\/github\.com\/cursor\/plugins\/tree\/main\/pstack\/automations\/benny\)\. benny triages slack issue reports, then reproduces and fixes confirmed bugs with real ui evidence\. its files are not registered as slash skills\.\n\nto set it up, point cursor at \[`FOR_AGENTS\.md`\]\(https:\/\/github\.com\/cursor\/plugins\/blob\/main\/pstack\/automations\/benny\/FOR_AGENTS\.md\)\. setup copies the pack into the target repository at `\.cursor\/automations\/benny\/`, enables pstack there for shared skills, and keeps user configuration outside the copied pack\. benny runs on cursor automations, so it is cursor-only\./g,
    to: "A dormant [benny automation pack](https://github.com/cursor/plugins/tree/main/pstack/automations/benny) exists upstream. Pi does not support Cursor automations, so the pack is not installed and no Cursor-specific files are used.",
    expect: 1,
  },
  {
    name: "help-cursor-docs",
    re: /Link \[Cursor's skills docs\]\(https:\/\/cursor\.com\/docs\/skills\) when this comes up\./g,
    to: "Link the Pi skills documentation when this comes up.",
    expect: 1,
  },
  {
    name: "help-overnight",
    re: /\| An overnight run moved but finished nothing \| `\/loop` needs a check that can pass or fail, not a duration\. See \[guide page 7\]\(\.\.\/\.\.\/docs\/guide\/07-overnight\.md\)\. \|/g,
    to: "| An overnight run moved but finished nothing | Pi has no timer loop; a run that needs one is BLOCKED under the binding. Give it a check that can pass or fail, and use an external scheduler if needed. See [guide page 7](../../docs/guide/07-overnight.md). |",
    expect: 1,
  },
  {
    name: "guide-overnight-isolation",
    re: /an isolated worktree or cloud agent/g,
    to: "an isolated local worktree",
    expect: 1,
  },
  {
    name: "guide-overnight-loop-command",
    re: /\n\/loop until done\. if you're truly stuck after a few hours, stop and write up why\./g,
    to: "\nif you're truly stuck after a few hours, stop and write up why.",
    expect: 1,
  },
  {
    name: "guide-overnight-loop-boundary",
    re: /- `\/loop` is Cursor's built-in wake mechanism, not a pstack skill\. The \[Autonomous run playbook\]\(\.\.\/\.\.\/skills\/poteto-mode\/playbooks\/autonomous-run\.md\) uses it to re-check the finish condition on events or a heartbeat\./g,
    to: "- Pi has no timer loop. A run that depends on Cursor's `/loop` is BLOCKED under the binding; do not simulate it. The [Autonomous run playbook](../../skills/poteto-mode/playbooks/autonomous-run.md) can re-check the finish condition on events or a heartbeat only when an external scheduler provides them.",
    expect: 1,
  },
  {
    name: "guide-overnight-restart",
    re: /or that you're about to go offline or restart Cursor\./g,
    to: "or that you're about to go offline or restart Pi.",
    expect: 1,
  },
  {
    name: "guide-overnight-projects",
    re: /A \[Cursor Project\]\(https:\/\/cursor\.com\/blog\/projects\) gives one coordinator agent a persistent thread\. The coordinator doesn't write code\. It directs subagents, which run in the cloud by default, so the work continues when your laptop is closed\. That's the shape the Orchestrate playbook expects\. Start your prompts to the coordinator with `\/skill:poteto-mode`, and the subagents it spawns follow the playbooks\.\n\nA few habits help:\n\n- Give each body of work its own Project, such as a feature, a migration, a perf push, or a tech-debt cleanup\. Several can run side by side\.\n- Drag related chats into the Project, finished ones included\. They become context for every agent in it\.\n- Give each PR a verification swarm before it merges, and let Autopilot-stack or Autopilot-full carry the queue\.\n- Ask the coordinator for a plan backed by data, and have it answer open questions with prototypes before it asks you\./g,
    to: "Pi has no Cursor Projects and no remote workers. Use one parent session as the coordinator; it can direct local worktree subagents, but they stop when the parent stops. The Orchestrate and Autopilot paths that require timers or nested delegation are BLOCKED under the binding; do not substitute a flat workflow. The local parts below still apply. Start your prompts to the coordinator with `/skill:poteto-mode`, and the subagents it spawns follow the playbooks.\n\nA few habits help:\n\n- Give each body of work its own parent session or worktree, such as a feature, a migration, a perf push, or a tech-debt cleanup.\n- Keep the plan and decision log in the parent session; a fresh session resumes from the handoff note.\n- Give each PR a verification swarm before it merges. The parts of Autopilot-stack or Autopilot-full that need timers or nested delegation are BLOCKED; do not substitute a flat workflow.\n- Ask the coordinator for a plan backed by data, and have it answer open questions with prototypes before it asks you.",
    expect: 1,
  },
  {
    name: "guide-overnight-schedule",
    re: /Every loop above still waits for you to start it\. A scheduled or event-driven automation removes that step\. Software maintenance splits into stages that suit this well:/g,
    to: "Every loop above still waits for you to start it. A scheduled or event-driven automation removes that step. Pi has no scheduler, so a run that depends on one is BLOCKED under the binding; do not simulate it. Software maintenance splits into stages that suit this well:",
    expect: 1,
  },
  {
    name: "guide-overnight-project-prompt",
    re: /One prompt can carry a whole Project, from research through execution:/g,
    to: "One prompt can carry a whole local coordination task, from research through execution:",
    expect: 1,
  },
  {
    name: "guide-overnight-benny",
    re: /pstack ships this as a dormant \[automation pack\]\(https:\/\/github\.com\/cursor\/plugins\/blob\/main\/pstack\/automations\/benny\/README\.md\) for Slack issue reports\. One automation triages each report\. The other reproduces confirmed bugs and may prepare a small draft fix\. Point an agent at its \[`FOR_AGENTS\.md`\]\(https:\/\/github\.com\/cursor\/plugins\/blob\/main\/pstack\/automations\/benny\/FOR_AGENTS\.md\) and name the target repository to set it up\./g,
    to: "pstack also has an upstream [automation pack](https://github.com/cursor/plugins/blob/main/pstack/automations/benny/README.md) for Slack issue reports. It requires Cursor Automations and Cursor-specific files, so this Pi package does not install or configure it. Treat its setup as upstream-only and BLOCKED here.",
    expect: 1,
  },
  {
    name: "guide-bot-heading",
    re: /## Build a bot UI with `\/skill:make-bot-ui`/g,
    to: "## Build a bot UI (upstream-only)",
    expect: 1,
  },
  {
    name: "guide-bot-body",
    re: /One situational skill is for Grok Bot users\. \[`\/skill:make-bot-ui`\]\(\.\.\/\.\.\/skills\/make-bot-ui\/SKILL\.md\) builds a small page whose buttons wake a bot over a webhook routine\. For example, you could swipe through a review queue and have each swipe ask the bot to act on that item\. A server on your machine holds the webhook's sender key, so the key never reaches the browser or the chat\. The skill also covers exposing the page on Tailscale\./g,
    to: "The `make-bot-ui` workflow requires Cursor Grok Bot webhook routines (`update_state`, `SendToUser`, and routine panels), which this Pi binding excludes. Treat it as upstream-only and BLOCKED; do not follow its setup here.",
    expect: 1,
  },
  {
    name: "help-bot-row",
    re: /\| Build a page whose buttons wake a Grok Bot over a webhook \| \[`\/skill:make-bot-ui`\]\(\.\.\/make-bot-ui\/SKILL\.md\) \|/g,
    to: "| Bot UI webhook workflow | Upstream-only and BLOCKED in Pi; requires Cursor Grok Bot routines |",
    expect: 1,
  },
  {
    name: "help-orchestrate-routing",
    re: /The Orchestrate playbook runs a program that spans days and many PRs\./g,
    to: "The Orchestrate playbook is upstream-only where it needs timer wakes or nested coordinators; those paths are BLOCKED in Pi.",
    expect: 1,
  },
  {
    name: "help-cursor-skill",
    re: /Without `\/skill:poteto-mode`, a phrase such as "babysit this pr" can start Cursor's own skill for the same job instead\./g,
    to: "Without `/skill:poteto-mode`, Pi does not start another skill for that phrase.",
    expect: 1,
  },
  {
    name: "help-cursor-plan",
    re: /pstack has no planning skill\. Cursor's Plan Mode works alongside it\./g,
    to: "pstack has no planning skill. Pi has no Cursor Plan Mode.",
    expect: 1,
  },
  {
    name: "readme-orchestrate-row",
    re: /\| \[orchestrate\]\(\.\/skills\/poteto-mode\/playbooks\/orchestrate\.md\) \| a standing project handed to one coordinator chat: multi-day, many stacked prs, fleets of subagents\. \|/g,
    to: "| [orchestrate](./skills/poteto-mode/playbooks/orchestrate.md) | a standing project handed to one coordinator chat: multi-day, many stacked prs, fleets of subagents. Upstream-only where it needs timers or nested coordinators; those paths are BLOCKED in Pi. |",
    expect: 1,
  },
  {
    name: "readme-autopilot-full-row",
    re: /\| \[autopilot-full\]\(\.\/skills\/poteto-mode\/playbooks\/autopilot-full\.md\) \| run independent prs to merged with one owner per pr\. a swarm verifies each code-ready head, and every later change to the patch gets a fresh check\. \|/g,
    to: "| [autopilot-full](./skills/poteto-mode/playbooks/autopilot-full.md) | run independent prs to merged with one owner per pr. a swarm verifies each code-ready head, and every later change to the patch gets a fresh check. Upstream-only where it needs a timer; that path is BLOCKED in Pi. |",
    expect: 1,
  },
  {
    name: "readme-autopilot-stack-row",
    re: /\| \[autopilot-stack\]\(\.\/skills\/poteto-mode\/playbooks\/autopilot-stack\.md\) \| build and verify one linear base-branch stack for the operator to review and land\. \|/g,
    to: "| [autopilot-stack](./skills/poteto-mode/playbooks/autopilot-stack.md) | build and verify one linear base-branch stack for the operator to review and land. Upstream-only where it inherits the timer-dependent root; that path is BLOCKED in Pi. |",
    expect: 1,
  },
  {
    name: "readme-bot-row",
    re: /\| \[`\/skill:make-bot-ui`\]\(\.\/skills\/make-bot-ui\/SKILL\.md\) \| you want a page or dashboard whose buttons wake a Grok Bot over a webhook, including the sender-key handoff and Tailscale\. \|/g,
    to: "| [`/skill:make-bot-ui`](./skills/make-bot-ui/SKILL.md) | upstream-only and BLOCKED in Pi: requires Cursor Grok Bot webhook routines. |",
    expect: 1,
  },
  {
    name: "bot-skill-banner",
    re: /# How to make a bot UI\n\nIn Pi, read/g,
    to: "# How to make a bot UI\n\n> BLOCKED in Pi: this workflow requires Cursor Grok Bot routines (`update_state`, `SendToUser`, and routine panels). Read `pi.md` and stop; do not execute the steps below.\n\nIn Pi, read",
    expect: 1,
  },
  {
    name: "guide-overnight-autopilot-full",
    re: /\[Autopilot-full\]\(\.\.\/\.\.\/skills\/poteto-mode\/playbooks\/autopilot-full\.md\) runs a queue of independent PRs to merged\./g,
    to: "[Autopilot-full](../../skills/poteto-mode/playbooks/autopilot-full.md) is an upstream playbook whose timer-dependent path is BLOCKED in Pi. Its local parts run a queue of independent PRs to merged.",
    expect: 1,
  },
  {
    name: "guide-overnight-autopilot-stack",
    re: /\[Autopilot-stack\]\(\.\.\/\.\.\/skills\/poteto-mode\/playbooks\/autopilot-stack\.md\) runs the same owner loop but ships nothing\./g,
    to: "[Autopilot-stack](../../skills/poteto-mode/playbooks/autopilot-stack.md) is upstream-only where it inherits Autopilot-full's timer-dependent root; that path is BLOCKED in Pi. Its local parts run the same owner loop but ship nothing.",
    expect: 1,
  },
  {
    name: "guide-overnight-orchestrate",
    re: /\[Orchestrate\]\(\.\.\/\.\.\/skills\/poteto-mode\/playbooks\/orchestrate\.md\) is for a program that outlives any single agent:/g,
    to: "[Orchestrate](../../skills/poteto-mode/playbooks/orchestrate.md) is upstream-only where it needs timer wakes or nested coordinators; those paths are BLOCKED in Pi. Its local parts are for a program that outlives any single agent:",
    expect: 1,
  },
  {
    name: "guide-overnight-autopilot-full-command",
    re: /\/skill:poteto-mode full autopilot on this queue\. each item is independent\. i want them merged by morning\./g,
    to: "/skill:poteto-mode take only the local, single-parent parts of this queue. stop with BLOCKED if the run needs a timer or nested delegation.",
    expect: 1,
  },
  {
    name: "guide-overnight-autopilot-stack-command",
    re: /\/skill:poteto-mode autopilot these five changes but stack them, don't ship\. i'll land the stack in the morning\./g,
    to: "/skill:poteto-mode prepare a local stack of these five changes and stop before any unsupported shipping step.",
    expect: 1,
  },
  {
    name: "guide-overnight-orchestrate-command",
    re: /\/skill:poteto-mode orchestrate the store migration\. own it until every package is converted and merged\. i'll check in twice a day\./g,
    to: "/skill:poteto-mode plan the local parts of the store migration; stop with BLOCKED if it needs timer wakes or nested coordinators.",
    expect: 1,
  },
  {
    name: "help-overnight-autopilot-recipes",
    re: /- `\/skill:poteto-mode full autopilot on this queue\. each item is independent\.`\n- `\/skill:poteto-mode autopilot these changes but stack them, don't ship\. i'll land the stack\.`/g,
    to: "- Autopilot-full and Autopilot-stack are upstream-only. Pi blocks the parts that need a timer or nested delegation; do not run them as written.\n- For the local parts, ask `/skill:poteto-mode` to stop with BLOCKED before any timer-dependent step.",
    expect: 1,
  },
  {
    name: "help-overnight-autopilot-routing",
    re: /- "full autopilot on this queue" runs Autopilot-full\. "stack them, don't ship" runs Autopilot-stack\./g,
    to: "- Autopilot-full and Autopilot-stack are upstream-only; their timer- or nested-delegation-dependent paths are BLOCKED in Pi. Use only local parts that stop with BLOCKED at those boundaries.",
    expect: 1,
  },
  {
    name: "guide-overnight-project-run",
    re: /once i approve it, run it with autopilot-stack or autopilot-full, and ask me which\./g,
    to: "once i approve it, run only the local parts that do not need a timer or nested delegation, and stop with BLOCKED otherwise.",
    expect: 1,
  },
  {
    name: "guide-overnight-predicate",
    re: /gives `\/loop` nothing to check\. Give a command or artifact that can pass or fail\./g,
    to: "gives the run nothing to check. Give a command or artifact that can pass or fail.",
    expect: 1,
  },
  {
    name: "guide-overnight-predicate-2",
    re: /Give `\/loop` a predicate that can pass or fail\./g,
    to: "Give the run a predicate that can pass or fail.",
    expect: 1,
  },
  {
    name: "guide-overnight-image",
    re: /\/skill:tdd, and \/loop above the counter/g,
    to: "/skill:tdd, and a timer loop above the counter",
    expect: 1,
  },
  {
    name: "help-overnight-recipe",
    re: / keep a decision log\. don't ask me before committing\. \/loop until done\. if you're truly stuck/g,
    to: " keep a decision log. don't ask me before committing. if you're truly stuck",
    expect: 1,
  },
  {
    name: "help-overnight-prompting",
    re: /and give `\/loop` that predicate\./g,
    to: "and give the run that predicate.",
    expect: 1,
  },
  {
    name: "help-install",
    re: /1\. Install with `\/add-plugin pstack` in chat, or from Customize in the sidebar\./g,
    to: "1. This package is loaded by the system's Pi packages; no plugin install is needed.",
    expect: 1,
  },
  {
    name: "help-cursor-intro",
    re: /pstack is built for Cursor\. Its skills use the Agent Skills format, so other tools can read them\. But most workflow skills, including `\/skill:poteto-mode`, `\/skill:how`, `\/skill:why`, and `\/skill:teach`, spawn Cursor subagents with per-role models, and Custom Modes and `\/loop` are Cursor features, so those parts may not work there\./g,
    to: "pstack is built for Cursor. This Pi package supplies native Pi subagents; Custom Modes and `/loop` are Cursor features with no Pi equivalent. Read the Pi binding for the exact boundaries.",
    expect: 1,
  },
  {
    name: "help-custom-mode",
    re: /- Option\+Enter on Mac or Alt\+Enter on Windows, or Use as Mode from the skill entry, makes it a Custom Mode\. It stays in context every turn until the user exits the mode, and it stays out of casual turns\./g,
    to: "- Pi applies `/skill:poteto-mode` to one message. Start each new task with that explicit entry; Pi has no Custom Mode.",
    expect: 1,
  },
  {
    name: "help-custom-mode-docs",
    re: /- Cursor's docs list Custom Modes in the Agents Window and the CLI\. Elsewhere, start each new task with `\/skill:poteto-mode`\./g,
    to: "- Start each new task with `/skill:poteto-mode`; Pi has no Custom Mode.",
    expect: 1,
  },
  {
    name: "help-custom-mode-troubleshoot",
    re: /\| The mode stopped applying after a few turns \| It was started with Enter\. Start it as a Custom Mode, or start each task with `\/skill:poteto-mode`\. \|/g,
    to: "| The mode stopped applying after a few turns | It applied to one message. Start each task with `/skill:poteto-mode`. |",
    expect: 1,
  },
  {
    name: "guide-install",
    re: /```text\n\/add-plugin pstack\n```\n\nCursor confirms the plugin is installed\./g,
    to: "This package is loaded by the system's Pi packages; there is no install command.",
    expect: 1,
  },
  {
    name: "guide-model-defaults",
    re: /The defaults run at `xhigh` reasoning, the same as the `large` budget\. `unlimited` lifts each model to its highest tier, up to `max`\. Opus goes to `max`\. Grok tops out at `xhigh`, so it stays there\./g,
    to: "`large` targets `xhigh` reasoning. `unlimited` lifts each model to its highest supported tier, up to `max`.",
    expect: 1,
  },
  {
    name: "guide-role-defaults",
    re: /You only override what you care about\. A role with no line in the rule keeps the skill's default\. To restore a default, delete that role's line\. A rerun of `\/skill:setup-pstack` keeps any role whose model differs from the default\. When a default changes, a rule written before the change still pins the old default, so delete those role lines, or delete the file, then run `\/skill:setup-pstack` again\./g,
    to: "Every role is required. To change a role, edit it or rerun `/skill:setup-pstack`; a missing role stops workflows until setup fills it.",
    expect: 1,
  },
  {
    name: "guide-swarm-default",
    re: /Setup also configures `swarm workers`, the default model for every `\/skill:swarm` worker unless a race names a model for each arm\./g,
    to: "Setup also configures `swarm workers`, the model for every `/skill:swarm` worker unless a race names a model for each arm.",
    expect: 1,
  },
  {
    name: "guide-custom-mode",
    re: /To keep `\/skill:poteto-mode` on for the whole chat, pick it from the `\/` menu with Option\+Enter \(Mac\) or Alt\+Enter \(Windows\) instead of Enter\. That makes it a \[Custom Mode\]\(https:\/\/cursor\.com\/docs\/skills#using-a-skill-as-a-custom-mode\), which stays in context on every turn until you exit it\. Custom Modes are available in the Agents Window and the CLI\. Plain Enter attaches the skill to one message, and it fades as the chat moves on\./g,
    to: "Pi applies `/skill:poteto-mode` to one message. Start each task with that explicit entry; Pi has no Custom Mode.",
    expect: 1,
  },
  {
    name: "guide-custom-mode-02",
    re: /Short works because the playbook holds the structure, and a Custom Mode keeps `\/skill:poteto-mode` in context on every turn\. \[Set up pstack\]\(\.\/01-setup\.md#run-your-first-task\) shows how to start one\./g,
    to: "Short works because the playbook holds the structure, and an explicit `/skill:poteto-mode` entry starts each task. [Set up pstack](./01-setup.md#run-your-first-task) shows how.",
    expect: 1,
  },
  {
    name: "guide-authoring-create-skill",
    re: /through Cursor's built-in `create-skill` flow/g,
    to: "through Pi's skill authoring playbook",
    expect: 1,
  },
  {
    name: "guide-authoring-playbook",
    re: /which routes through Cursor's built-in `create-skill`, validates the frontmatter and links/g,
    to: "which uses Pi's skill format documentation, validates the frontmatter and links",
    expect: 1,
  },
  {
    name: "readme-model-fallback",
    re: /models are configurable too\. type \[`\/skill:setup-pstack`\]\(\.\/skills\/setup-pstack\/SKILL\.md\)\. it detects the models you have access to and writes a small always-applied rule mapping each role \(code, judgment, the review panels\) to a model\. every skill reads it and falls back to sensible defaults when the rule is absent, so you override only what you want\./g,
    to: "models are configurable too. run [`/skill:setup-pstack`](./skills/setup-pstack/SKILL.md); it detects the models you have access to and writes the role preferences. every skill reads that file, and a missing role line stops the workflow until setup fills it.",
    expect: 1,
  },
  {
    name: "agent-body-links",
    re: /\]\(((?:\.\.\/)+|\.\/)agents\/(poteto-agent|comment-sicko)\.md\)/g,
    to: "]($1agents/$2.body.md)",
    expect: 4,
  },
]

// Resolve host combinations that the generic token rewrites split into two conflicting fields.
// These run after the generic rewrites so a known upstream phrase becomes one valid Pi call.
const SUBAGENT_REWRITES = [
  {
    name: "how-subagent-type",
    re: new RegExp(`Every spawn is a subagent subagent with \`subagent_type: ${PROFILE.generalPurpose}\` and \`subagent_type: ${PROFILE.readonly}\`\\.`, "g"),
    to: `Every spawn uses \`subagent_type: ${PROFILE.readonly}\`.`,
  },
  {
    name: "interrogate-subagent-type",
    re: new RegExp(`Each reviewer gets \`subagent_type: ${PROFILE.generalPurpose}\`, \`subagent_type: ${PROFILE.readonly}\`, and \`model\``, "g"),
    to: `Each reviewer gets \`subagent_type: ${PROFILE.readonly}\`, and \`model\``,
  },
  {
    name: "swarm-subagent-type",
    re: new RegExp(`\`subagent_type: ${PROFILE.generalPurpose}\`, \`subagent_type: ${PROFILE.cloud}\`, \`run_in_background: true\``, "g"),
    to: `\`subagent_type: ${PROFILE.cloud}\`, \`run_in_background: true\``,
  },
  {
    name: "reflect-readonly-prose",
    re: /and readonly strips MCPs\./g,
    to: `while the ${PROFILE.readonly} profile strips MCPs.`,
    expect: 2,
  },
  {
    name: "interrogate-table-header",
    re: /\| Subagent \| Default model \|/g,
    to: "| Subagent | Setup-selected model |",
  },
  {
    name: "reflect-table-header",
    re: /\| Lens \| Role line \| Default `model` \| Prompt template \|/g,
    to: "| Lens | Role line | Setup-selected `model` | Prompt template |",
  },
  {
    name: "arena-readonly-judge",
    re: /Spawn one readonly judge subagent on that model\./g,
    to: `Spawn one judge with \`subagent_type: ${PROFILE.readonly}\` on that model.`,
  },
  {
    name: "model-reject-common",
    re: /If the subagent tool rejects a model ID, use the default and say so\. If it rejects the default, use the closest valid model ID of the same family from its error message\./g,
    to: "If the subagent tool rejects the configured model ID, stop and report it; do not try another model.",
    expect: 4,
  },
  {
    name: "arena-reject",
    re: /If the subagent tool rejects a configured entry, run that seat on its family's default and say so\. Families go by prefix: `claude-\*`, and `grok-\*` with `cursor-grok-\*` and `composer-\*`\. A refused `composer-\*` entry runs on `grok-4\.7-xhigh-fast`\. With no family match, use `claude-opus-5-5-xhigh`\. If it rejects a default, use the closest valid model ID of the same family from its error message\./g,
    to: "If the subagent tool rejects a configured model ID, stop and report it; do not try another model.",
  },
  {
    name: "interrogate-reject",
    re: /If the subagent tool rejects a configured entry, run that reviewer on its family's table default and say so\. Families go by prefix: `claude-\*`, and `grok-\*` with `cursor-grok-\*` and `composer-\*`\. A refused `composer-\*` entry runs on Reviewer B's default\. With no family match, use Reviewer A's default\. If it rejects a table default, spawn with the closest equivalent from the valid model IDs in its error message \(prefer the same family and reasoning tier\), and open a separate PR to update the default table\. Do not block the review on the model ID issue\. Never treat an alias entry as a rejected model ID or apply either fallback to it\./g,
    to: "If the subagent tool rejects a configured model ID, stop and report it; do not try another model. Never treat an alias entry as a rejected model ID.",
  },
  {
    name: "interrogate-fallback",
    re: /If the rule or that line is missing, use the table defaults\./g,
    to: "If the rule or that line is missing, use the fallback column.",
  },
  {
    name: "interrogate-table-default",
    re: /or its table default when there is no configured line/g,
    to: "or its fallback entry when there is no configured line",
  },
  {
    name: "model-defaults",
    re: /`(?:grok-4\.7-xhigh-fast|claude-opus-5-5-xhigh)`/g,
    to: "`inherit-parent`",
    expect: 23,
  },
  {
    name: "arena-panel-fallback",
    re: /default to one each on `inherit-parent` and `inherit-parent`/g,
    to: "default both seats to the parent model",
  },
  {
    name: "arena-cross-judge-fallback",
    re: /choose from `inherit-parent` and `inherit-parent`/g,
    to: "use the parent model",
  },
  {
    name: "architect-panel-fallback",
    re: /use `inherit-parent` and `inherit-parent`/g,
    to: "use the parent model for both seats",
  },
]

// Applied after POST_REWRITES. Keep this list in execution order: the combination fixes must run
// before the generic model fallback and the model defaults must run before the panel wording.
POST_REWRITES.push(...SUBAGENT_REWRITES);

// A missing role line is not permission to silently collapse the role onto the parent model. The
// upstream fallback rules point at setup's detection and confirmation instead.
const MODEL_GATE_REWRITES = [
  {
    name: "model-missing-selection",
    re: /If the (?:file|rule) or that line is missing, (?:use the parent model for both seats|default both seats to the parent model|use the parent model|use the fallback column|use `inherit-parent`)\./g,
    to: "If the file or that line is missing, stop and ask the user to run `/skill:setup-pstack`; do not choose a fallback model.",
    expect: 5,
  },
  {
    name: "model-missing-default",
    re: /, or to the default if the file or the line is missing/g,
    to: ". If the file or the line is missing, stop and ask the user to run `/skill:setup-pstack`; do not substitute a default",
    expect: 3,
  },
  {
    name: "interrogate-missing-entry",
    re: /, or its fallback entry when there is no configured line/g,
    to: ". If there is no configured entry, stop and ask the user to run `/skill:setup-pstack`",
    expect: 1,
  },
  {
    name: "poteto-missing-line",
    re: /Without a configured line, use the parent model/g,
    to: "If the file is missing or has no configured line, stop and ask the user to run `/skill:setup-pstack`; do not use the parent model as a fallback",
    expect: 1,
  },
  {
    name: "poteto-hardest-missing",
    re: /or the parent model when that line is absent/g,
    to: "or stop and ask the user to run `/skill:setup-pstack` when that line is absent",
    expect: 1,
  },
  {
    name: "interrogate-table-values",
    re: /\| Reviewer A \| `inherit-parent` \|\n\| Reviewer B \| `inherit-parent` \|/g,
    to: "| Reviewer A | configured by `/skill:setup-pstack` |\n| Reviewer B | configured by `/skill:setup-pstack` |",
    expect: 1,
  },
  {
    name: "reflect-table-values",
    re: /\| (Judgment|Tooling|Divergent) \| ([^|]+) \| `inherit-parent` \|/g,
    to: "| $1 | $2 | configured by `/skill:setup-pstack` |",
    expect: 3,
  },
  {
    name: "guide-install-sentence",
    re: /In a Cursor chat, run:\n\nThis package is loaded by the system's Pi packages; there is no install command\./g,
    to: "Pi loads this package from its system packages; no install command is needed.",
    expect: 1,
  },
  {
    name: "help-custom-mode-line",
    re: /- Pi applies `\/skill:poteto-mode` to one message\. Start each new task with that explicit entry; Pi has no Custom Mode\.\n- Start each new task with `\/skill:poteto-mode`; Pi has no Custom Mode\./g,
    to: "- Pi applies `/skill:poteto-mode` to one message; each task starts with that explicit entry.",
    expect: 1,
  },
  {
    name: "poteto-role-default",
    re: /A role with no line keeps its default/g,
    to: "A role with no line stops the workflow until `/skill:setup-pstack` fills it",
    expect: 1,
  },
  {
    name: "model-default-phrasing",
    re: /\(default `inherit-parent`\)/g,
    to: "(configured by `/skill:setup-pstack`)",
    expect: 9,
  },
  {
    name: "model-inline-default",
    re: /, default `inherit-parent`\./g,
    to: "; role configured by `/skill:setup-pstack`.",
    expect: 2,
  },
];
POST_REWRITES.push(...MODEL_GATE_REWRITES);


// Host differences in bundled shell helpers: Linux stat/date flags and Pi session paths.
const SCRIPT_RULES = [
  { from: "# Transcripts dir: ~/.cursor/projects/<slugified-repo-path>/agent-transcripts.", to: "# Pi sessions dir: ~/.pi/agent/sessions/--<slugified-repo-path>--.", expect: 1 },
  { from: 'transcripts="$HOME/.cursor/projects/$slug/agent-transcripts"', to: 'sessions="$HOME/.pi/agent/sessions/--$slug--"', expect: 1 },
  { from: '[ -d "$transcripts" ]', to: '[ -d "$sessions" ]', expect: 1 },
  { from: '"$transcripts" 2>/dev/null', to: '"$sessions" 2>/dev/null', expect: 1 },
  { from: "| xargs stat -f '%m %N' 2>/dev/null", to: "| xargs stat -c '%Y %n' 2>/dev/null", expect: 1 },
  { from: 'date -r "$last_ts"', to: 'date -d "@$last_ts"', expect: 1 },
];

const CHECK_PLAN_RULES = [
  {
    path: "skills/poteto-mode/scripts/check-plan.mjs",
    name: "check-plan-program-marker",
    re: /"git show origin\/main:"/,
    to: JSON.stringify(SKILL_READ_PREFIX),
    expect: 1,
  },
  {
    path: "skills/poteto-mode/scripts/check-plan.test.ts",
    name: "check-plan-valid-fixture",
    re: /\\`git show origin\/main:\\`/,
    to: "\\`" + SKILL_READ_PREFIX + "poteto-mode/playbooks/autopilot-stack.md\\`",
    expect: 1,
  },
];

const counts = new Map();
// Count every occurrence, including rules written without /g for a single anchored edit. A
// duplicated anchor must fail the exact-count check instead of silently leaving later copies
// untransformed.
function allOccurrences(re) {
  return re.flags.includes("g") ? re : new RegExp(re.source, `${re.flags}g`);
}
function applyRule(out, rule) {
  const re = allOccurrences(rule.re);
  const hits = out.match(re);
  if (hits) counts.set(rule.name, (counts.get(rule.name) ?? 0) + hits.length);
  return out.replace(re, rule.to);
}
function applyRules(text) {
  let out = text;
  for (const rule of SETUP_REWRITES) out = applyRule(out, rule);
  for (const rule of [...RULES, COMMAND_RULE]) out = applyRule(out, rule);
  for (const rule of POST_REWRITES) out = applyRule(out, rule);
  return out;
}

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

// The generated tree must match its committed copy before we transform it.
const check = spawnSync(process.execPath, [join(srcRoot, "scripts", "generate-pstack-harness-trees.mjs"), "--check"], {
  cwd: srcRoot,
  encoding: "utf8",
});
if (check.status !== 0) {
  console.error(check.stdout ?? "");
  console.error(check.stderr ?? "");
  process.exit(1);
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const skipped = new Set([".claude-plugin", "plugin.json", "docs/harness/claude-code.md", "agents"]);
for (const path of walk(HARNESS)) {
  const rel = relative(HARNESS, path);
  if (skipped.has(rel) || [...skipped].some((p) => rel.startsWith(`${p}/`))) continue;
  const target = join(outDir, rel);
  mkdirSync(dirname(target), { recursive: true });
  if (path.endsWith(".md")) {
    writeFileSync(target, applyRules(readFileSync(path, "utf8"), rel));
  } else if (rel === "skills/poteto-mode/scripts/worktree-audit.sh") {
    let text = readFileSync(path, "utf8");
    for (const rule of SCRIPT_RULES) {
      const hits = text.split(rule.from).length - 1;
      if (hits !== rule.expect) {
        console.error(`pstack script transform '${rule.from}': expected ${rule.expect}, got ${hits} in ${rel}`);
        process.exit(1);
      }
      text = text.split(rule.from).join(rule.to);
    }
    writeFileSync(target, text);
    chmodSync(target, statSync(path).mode & 0o777);
  } else {
    cpSync(path, target);
    chmodSync(target, statSync(path).mode & 0o777);
  }
}

// Copied store files are read-only, so replace them rather than opening them for writing.
for (const rule of CHECK_PLAN_RULES) {
  const path = join(outDir, rule.path);
  const text = readFileSync(path, "utf8");
  rmSync(path);
  writeFileSync(path, applyRule(text, rule));
  chmodSync(path, statSync(join(HARNESS, rule.path)).mode & 0o777);
}

// Three direct workflow dependencies from the same pinned cursor-team-kit snapshot. They pass
// through the same rules and validation as pstack skills; the rest of cursor-team-kit is omitted.
const bundledRoot = join(srcRoot, "cursor-team-kit", "skills");
for (const name of ["deslop", "control-cli", "control-ui"]) {
  for (const path of walk(join(bundledRoot, name))) {
    const rel = relative(join(bundledRoot, name), path);
    const target = join(outDir, "skills", name, rel);
    mkdirSync(dirname(target), { recursive: true });
    if (path.endsWith(".md")) {
      writeFileSync(target, applyRules(readFileSync(path, "utf8"), `cursor-team-kit/skills/${name}/${rel}`));
    } else {
      cpSync(path, target);
      chmodSync(target, statSync(path).mode & 0o777);
    }
  }
}

// Agent bodies: the Nix profile table owns frontmatter, tools, and worktree membership.
mkdirSync(join(outDir, "agents"), { recursive: true });
for (const name of readdirSync(join(HARNESS, "agents"))) {
  const text = readFileSync(join(HARNESS, "agents", name), "utf8");
  const body = text.replace(/^---\n[\s\S]*?\n---\n+/, "");
  writeFileSync(join(outDir, "agents", `${name.replace(/\.md$/, "")}.body.md`), applyRules(body, `agents/${name}`));
}

const allRules = [...SETUP_REWRITES, ...RULES, ...POST_REWRITES, COMMAND_RULE, ...CHECK_PLAN_RULES];
const expected = new Map(allRules.map((rule) => [rule.name, rule.expect ?? 1]));
if (process.env.PSTACK_REPORT) {
  for (const [name, n] of [...counts].sort()) console.log(`count ${name}: ${n}`);
}

const drifts = [...expected].filter(([name, want]) => counts.get(name) !== want);
if (drifts.length > 0) {
  for (const [name, want] of drifts) console.error(`pstack transform '${name}': expected ${want}, got ${counts.get(name) ?? 0}`);
  console.error("The upstream snapshot changed shape. Review the transformations before rebuilding.");
  process.exit(1);
}

// Executable guidance must not still name a Cursor-only tool or rule source.
const remaining = [
  [/`Task`/, "`Task`"],
  [/`AskQuestion`/, "`AskQuestion`"],
  [/subagent_type\s*:\s*["'`]?generalPurpose/, "subagent_type: generalPurpose"],
  [/\b(?:environment|readonly|is_background)\s*:/, "Cursor subagent field"],
  [/`cloud_base_branch`/, "`cloud_base_branch`"],
  [/\bfile_attachments\b/, "file_attachments"],
  [/pstack-models\.mdc/, "pstack-models.mdc"],
  [/(?<![\w/.-])pstack\/skills\//, "repo-relative pstack skills path"],
  [/\.cursor\/(?:rules|plugins|worktrees)|\.cursor-plugin/, "Cursor path"],
  [/\bcreate-skill\b/, "Cursor create-skill"],
  [/\bcursor-team-kit\b/, "cursor-team-kit"],
  [bareCommandPattern, "bare bundled skill command"],
  [/\/principle-<name>/, "bare principle command"],
  [/\/in-cloud\b/, "Cursor in-cloud command"],
  [/\bown VM\b/, "remote VM claim"],
  [/\bCursor Project\b/, "Cursor Project instruction"],
  [/Cursor's skills docs/, "Cursor documentation referral"],
  [/FOR_AGENTS\.md/, "Cursor automation setup"],
  [/Raise it one step|Lower it one step|use its nearest lower level/, "automatic runtime thinking adjustment"],
];
const allowedSubagentTypes = new Set(AGENT_TYPES);
const allowedSpawnFields = new Set([
  "subagent_type",
  "model",
  "thinking",
  "run_in_background",
  "description",
  "prompt",
]);

function extractFlatObjects(text) {
  const objects = [];
  let depth = 0;
  let start = -1;
  let quote = null;
  let escaped = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (depth === 0) {
      if (char === "{") {
        start = index;
        depth = 1;
      }
      continue;
    }
    if (quote !== null) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
    } else if (char === "{") {
      depth += 1;
    } else if (char === "}" && depth > 0) {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        objects.push({ call: text.slice(start, index + 1), start, end: index + 1 });
        start = -1;
      }
    }
  }
  return objects;
}

function maskRanges(text, ranges) {
  const chars = text.split("");
  for (const range of ranges) {
    for (let index = range.start; index < range.end; index += 1) chars[index] = " ";
  }
  return chars.join("");
}

function decodeQuoted(raw, quote) {
  if (quote === '"') {
    try {
      return JSON.parse(`"${raw}"`);
    } catch {
      return raw;
    }
  }
  return raw.replace(/''/g, "'");
}

function readCallValue(call, colon) {
  let index = colon + 1;
  while (index < call.length && /\s/.test(call[index])) index += 1;
  const quote = call[index];
  if (quote === '"' || quote === "'") {
    const start = index;
    let escaped = false;
    for (index += 1; index < call.length; index += 1) {
      const char = call[index];
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) {
        return decodeQuoted(call.slice(start + 1, index), quote);
      }
    }
    return decodeQuoted(call.slice(start + 1), quote);
  }
  const start = index;
  while (index < call.length && !/[\s,}]/.test(call[index])) index += 1;
  return call.slice(start, index);
}

function extractCallFields(call) {
  const fields = [];
  let quote = null;
  let escaped = false;
  for (let index = 0; index < call.length; index += 1) {
    const char = call[index];
    if (quote !== null) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char !== ":") continue;
    let end = index - 1;
    while (end >= 0 && /\s/.test(call[end])) end -= 1;
    if (end < 0) continue;
    let start;
    let quotedKey = false;
    if (call[end] === '"' || call[end] === "'") {
      quotedKey = true;
      const closing = call[end];
      start = end - 1;
      while (start >= 0 && !(call[start] === closing && call[start - 1] !== "\\")) start -= 1;
      if (start < 0) continue;
      start += 1;
    } else {
      start = end;
      while (start >= 0 && /[A-Za-z0-9_.-]/.test(call[start])) start -= 1;
      start += 1;
    }
    let before = quotedKey ? start - 2 : start - 1;
    while (before >= 0 && /\s/.test(call[before])) before -= 1;
    if (before >= 0 && call[before] !== "{" && call[before] !== ",") continue;
    const key = quotedKey ? decodeQuoted(call.slice(start, end), call[end]) : call.slice(start, end + 1);
    fields.push({ key, value: readCallValue(call, index) });
  }
  return fields;
}

function validateModelValue(value, file, label) {
  if (/-fast\b/.test(value) || /^(?:grok|claude|composer|cursor-grok)-/i.test(value)) {
    throw new Error(`${file}: Cursor model ID remains '${value}' in ${label}`);
  }
}

function validateCall(call, file, label) {
  const fields = extractCallFields(call);
  if (!fields.some((field) => field.key === "subagent_type")) return;
  for (const field of fields) {
    if (!allowedSpawnFields.has(field.key)) {
      throw new Error(`${file}: unsupported subagent field '${field.key}' in ${label}: ${call}`);
    }
    if (field.key === "model") validateModelValue(field.value, file, label);
  }
  for (const key of new Set(fields.map((field) => field.key))) {
    if (fields.filter((field) => field.key === key).length > 1) {
      throw new Error(`${file}: duplicate subagent field '${key}' in ${label}: ${call}`);
    }
  }
  const type = fields.find((field) => field.key === "subagent_type")?.value;
  if (type !== undefined && !allowedSubagentTypes.has(type)) {
    throw new Error(`${file}: unsupported subagent_type '${type}' in ${label}: ${call}`);
  }
}

function parseYamlScalar(raw) {
  const value = raw.trim();
  if (!value.startsWith('"') && !value.startsWith("'")) {
    return { value: value.replace(/\s+#.*$/, "").trim(), valid: true };
  }
  const quote = value[0];
  let close = -1;
  let escaped = false;
  for (let index = 1; index < value.length; index += 1) {
    const char = value[index];
    if (escaped) {
      escaped = false;
    } else if (char === "\\" && quote === '"') {
      escaped = true;
    } else if (char === quote) {
      if (quote === "'" && value[index + 1] === "'") {
        index += 1;
      } else {
        close = index;
        break;
      }
    }
  }
  if (close < 0) return { value: "", valid: false };
  const rest = value.slice(close + 1).trim();
  if (rest !== "" && !rest.startsWith("#")) return { value: "", valid: false };
  let decoded;
  if (quote === '"') {
    try {
      decoded = JSON.parse(value.slice(0, close + 1));
    } catch {
      return { value: "", valid: false };
    }
  } else {
    decoded = value.slice(1, close).replace(/''/g, "'");
  }
  return { value: decoded, valid: true };
}

function maskYamlPromptScalars(text) {
  const chars = text.split("");
  const mask = (start, end) => {
    for (let index = start; index < end; index += 1) chars[index] = " ";
  };
  for (const block of text.matchAll(/```[^\n]*\n([\s\S]*?)```/g)) {
    const bodyStart = block.index + block[0].indexOf("\n") + 1;
    const bodyEnd = block.index + block[0].length - 3;
    let offset = bodyStart;
    while (offset < bodyEnd) {
      const newline = text.indexOf("\n", offset);
      const lineEnd = newline < 0 || newline > bodyEnd ? bodyEnd : newline;
      const line = text.slice(offset, lineEnd);
      const match = line.match(/^(\s*)(?:"([^"]*)"|'([^']*)'|([A-Za-z][A-Za-z0-9_.-]*))\s*:\s*(.*)$/);
      if (match) {
        const key = match[2] !== undefined
          ? parseYamlScalar(`"${match[2]}"`).value
          : match[3] !== undefined
            ? parseYamlScalar(`'${match[3]}'`).value
            : match[4];
        if (key !== "prompt") {
          offset = lineEnd + 1;
          continue;
        }
        const indent = match[1].length;
        const prefixEnd = offset + line.indexOf(match[5], match[0].indexOf(":") + 1);
        const raw = match[5].trim();
        if (/^[|>][0-9+-]*$/.test(raw)) {
          let cursor = lineEnd + 1;
          while (cursor < bodyEnd) {
            const nextNewline = text.indexOf("\n", cursor);
            const nextEnd = nextNewline < 0 || nextNewline > bodyEnd ? bodyEnd : nextNewline;
            const nextLine = text.slice(cursor, nextEnd);
            const nextIndent = nextLine.match(/^\s*/)[0].length;
            if (nextLine.trim() !== "" && nextIndent <= indent) break;
            mask(cursor, nextEnd);
            cursor = nextEnd + 1;
          }
          offset = cursor;
          continue;
        }
        if (raw.startsWith('"') || raw.startsWith("'")) {
          const quote = raw[0];
          let cursor = prefixEnd + 1;
          let escaped = false;
          let closed = false;
          while (cursor < bodyEnd) {
            const char = text[cursor];
            if (escaped) escaped = false;
            else if (char === "\\" && quote === '"') escaped = true;
            else if (char === quote) {
              if (quote === "'" && text[cursor + 1] === "'") {
                cursor += 2;
                continue;
              }
              mask(prefixEnd, cursor + 1);
              closed = true;
              break;
            }
            cursor += 1;
          }
          if (!closed) mask(prefixEnd, bodyEnd);
          offset = cursor + 1;
          continue;
        }
        mask(prefixEnd, lineEnd);
        let cursor = lineEnd + 1;
        while (cursor < bodyEnd) {
          const nextNewline = text.indexOf("\n", cursor);
          const nextEnd = nextNewline < 0 || nextNewline > bodyEnd ? bodyEnd : nextNewline;
          const nextLine = text.slice(cursor, nextEnd);
          const nextIndent = nextLine.match(/^\s*/)[0].length;
          if (nextLine.trim() !== "" && nextIndent <= indent) break;
          mask(cursor, nextEnd);
          cursor = nextEnd + 1;
        }
        offset = cursor;
        continue;
      }
      offset = lineEnd + 1;
    }
  }
  return chars.join("");
}

function fencedHasSelector(body) {
  for (const line of body.split("\n")) {
    const quoted = line.match(/^\s*(["'])(.*?)\1\s*:/);
    if (quoted) {
      const key = parseYamlScalar(quoted[1] + quoted[2] + quoted[1]).value;
      if (key === "subagent_type") return true;
    }
    if (/^\s*subagent_type\s*:/.test(line)) return true;
    if (/\bsubagent_type\b/.test(line)) return true;
  }
  return false;
}

function validateFencedMapping(body, file, language) {
  const stripped = body.trim();
  if (/json/i.test(language) || stripped.startsWith("{") || stripped.startsWith("[")) {
    try {
      JSON.parse(stripped);
    } catch {
      throw new Error(`${file}: unsupported fenced JSON/flow syntax`);
    }
    return;
  }
  if (/\\[xU]/.test(body)) {
    throw new Error(`${file}: unsupported YAML escape syntax in fenced call`);
  }
  if (!fencedHasSelector(body)) return;
  const records = [];
  let document = 0;
  let scalarIndent = null;
  for (const line of body.split("\n")) {
    const trimmed = line.trim();
    const indent = line.match(/^\s*/)[0].length;
    if (scalarIndent !== null) {
      if (trimmed === "" || indent > scalarIndent) continue;
      scalarIndent = null;
    }
    if (trimmed === "---") {
      document += 1;
      continue;
    }
    if (trimmed === "") continue;
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      throw new Error(`${file}: unsupported flow-style fenced mapping: ${trimmed}`);
    }
    const quotedMatch = line.match(/^\s*(["'])(.*?)\1\s*:\s*(.*)$/);
    const plainMatch = line.match(/^\s*([A-Za-z][A-Za-z0-9_.-]*)\s*:\s*(.*)$/);
    if (!quotedMatch && !plainMatch) {
      if (line.includes(":") && !trimmed.startsWith("#") && !trimmed.startsWith("-")) {
        throw new Error(`${file}: unsupported fenced field syntax: ${trimmed}`);
      }
      if (indent > 0) {
        throw new Error(`${file}: unsupported fenced scalar continuation: ${trimmed}`);
      }
      continue;
    }
    const key = quotedMatch
      ? parseYamlScalar(quotedMatch[1] + quotedMatch[2] + quotedMatch[1]).value
      : plainMatch[1];
    const rawValue = quotedMatch ? quotedMatch[3] : plainMatch[2];
    records.push({ document, key, rawValue, line: trimmed, indent });
    if (key === "prompt") scalarIndent = indent;
  }
  if (!records.some((record) => record.key === "subagent_type")) return;
  const documents = new Set(records.map((record) => record.document));
  for (const doc of documents) {
    const fields = records.filter((record) => record.document === doc);
    if (!fields.some((record) => record.key === "subagent_type")) continue;
    const seen = new Set();
    for (const record of fields) {
      if (!allowedSpawnFields.has(record.key)) {
        throw new Error(`${file}: unsupported subagent field '${record.key}' in fenced call: ${record.line}`);
      }
      if (seen.has(record.key)) {
        throw new Error(`${file}: duplicate subagent field '${record.key}' in fenced call: ${record.line}`);
      }
      seen.add(record.key);
      if (record.key === "prompt") continue;
      const parsed = parseYamlScalar(record.rawValue);
      if (!parsed.valid) {
        throw new Error(`${file}: unsupported fenced scalar syntax: ${record.line}`);
      }
      if (record.key === "model") validateModelValue(parsed.value, file, "fenced call");
      if (record.key === "subagent_type" && !allowedSubagentTypes.has(parsed.value)) {
        throw new Error(`${file}: unsupported subagent_type '${parsed.value}' in fenced call: ${record.line}`);
      }
    }
  }
}

function validateGuidance(text, file) {
  const fences = [...text.matchAll(/```([^\n]*)\n([\s\S]*?)```/g)];
  for (const block of fences) validateFencedMapping(block[2], file, block[1]);
  const promptSafe = maskYamlPromptScalars(text);
  const calls = extractFlatObjects(promptSafe);
  for (const object of calls) validateCall(object.call, file, "object call");
  // Do not rescan call values, prompt scalars, or fenced bodies as prose.
  const fenceRanges = fences.map((block) => ({ start: block.index, end: block.index + block[0].length }));
  const prose = maskRanges(promptSafe, [...calls, ...fenceRanges]);
  const paragraphs = prose.split(/\n\s*\n/);
  for (const [paragraphIndex, paragraph] of paragraphs.entries()) {
    const normalized = paragraph.replace(/\s*\n\s*/g, " ");
    if (/\b(?:environment|readonly|is_background)\s*:/.test(normalized)) {
      throw new Error(`${file}:${paragraphIndex + 1}: unsupported Cursor subagent field: ${normalized}`);
    }
    for (const sentence of normalized.split(/(?<=[.!?])\s+/)) {
      const fields = [
        ...sentence.matchAll(
          /\b["'`]?subagent_type["'`]?\s*:\s*(?:"([^"]*)"|'([^']*)'|`([^`]*)`|([^\s,"'`}\]]+))/g,
        ),
      ];
      if (fields.length > 1) {
        throw new Error(`${file}:${paragraphIndex + 1}: multiple subagent_type fields in one sentence: ${sentence}`);
      }
      for (const field of fields) {
        const type = field[1] ?? field[2] ?? field[3] ?? field[4];
        if (!allowedSubagentTypes.has(type)) {
          throw new Error(`${file}:${paragraphIndex + 1}: unsupported subagent_type '${type}'`);
        }
      }
      if (fields.length > 0 && /\\["']/.test(sentence)) {
        throw new Error(`${file}:${paragraphIndex + 1}: unsupported escaped key in call-shaped prose: ${sentence}`);
      }
      for (const model of sentence.matchAll(/\bmodel\s*:\s*(?:"([^"]*)"|'([^']*)'|`([^`]*)`|([^\s,`]+))/g)) {
        validateModelValue(model[1] ?? model[2] ?? model[3] ?? model[4], file, "prose call");
      }
      if (fields.length > 0) {
        const keys = [
          ...sentence.matchAll(/(?<![A-Za-z0-9_-])(?:"([^"]*)"|'([^']*)'|`([^`]*)`|([A-Za-z][A-Za-z0-9_.-]*))\s*:\s*/g),
        ]
          .map((match) => {
            const key = match[1] ?? match[2] ?? match[3] ?? match[4];
            const before = sentence.slice(0, match.index).trimEnd().slice(-1);
            return { key, quoted: match[4] === undefined, callLike: before === "," || before === "{" };
          })
          .filter(({ key, quoted, callLike }) => quoted || callLike || key.includes("_") || /[A-Z]/.test(key))
          .map(({ key }) => key);
        for (const key of keys) {
          if (!allowedSpawnFields.has(key)) {
            throw new Error(`${file}:${paragraphIndex + 1}: unsupported subagent field '${key}': ${sentence}`);
          }
        }
        for (const key of new Set(keys)) {
          if (keys.filter((candidate) => candidate === key).length > 1) {
            throw new Error(`${file}:${paragraphIndex + 1}: duplicate subagent field '${key}': ${sentence}`);
          }
        }
      }
    }
    if (/(?:^|[\s`"'])(?:grok|composer|cursor-grok)-[a-z0-9]/i.test(normalized)) {
      throw new Error(`${file}:${paragraphIndex + 1}: Cursor model ID remains: ${normalized}`);
    }
    if (/-fast\b/.test(normalized)) {
      throw new Error(`${file}:${paragraphIndex + 1}: fast model variant remains: ${normalized}`);
    }
    if (/\bAskQuestion\b/.test(normalized)) {
      throw new Error(`${file}:${paragraphIndex + 1}: Cursor tool name remains: ${normalized}`);
    }
    if (/pstack-models\.mdc|\.cursor\/(?:rules|plugins|worktrees)|\.cursor-plugin|cloud_base_branch/.test(normalized)) {
      throw new Error(`${file}:${paragraphIndex + 1}: Cursor path or field remains: ${normalized}`);
    }
  }
  return prose;
}
const executableFiles = walk(join(outDir, "skills")).filter((p) => p.endsWith(".md"));
executableFiles.push(...walk(join(outDir, "agents")).filter((p) => p.endsWith(".md")));
executableFiles.push(...walk(join(outDir, "docs", "guide")).filter((p) => p.endsWith(".md")));
executableFiles.push(join(outDir, "README.md"));
for (const path of executableFiles) {
  const text = readFileSync(path, "utf8");
  if (relative(outDir, path) === "skills/poteto-mode/playbooks/multi-phase-plan.md" && /`git show origin\/main:/.test(text)) {
    console.error(`leftover obsolete trunk read in ${relative(outDir, path)}`);
    process.exit(1);
  }
  let executableText;
  try {
    executableText = validateGuidance(text, relative(outDir, path));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
  for (const [re, label] of remaining) {
    if (re.test(executableText)) {
      console.error(`leftover ${label} in ${relative(outDir, path)}`);
      process.exit(1);
    }
  }
}

// Commander and the bootstrap install key: the scripts must start without running bun install.
const scriptsDir = join(outDir, "skills", "poteto-mode", "scripts");
const installKey = createHash("sha256")
  .update(readFileSync(join(scriptsDir, "package.json")))
  .update("\0")
  .update(readFileSync(join(scriptsDir, "bun.lock")))
  .digest("hex");
mkdirSync(join(scriptsDir, "node_modules"), { recursive: true });
writeFileSync(join(scriptsDir, "node_modules", ".poteto-mode-tools-install-key"), `${installKey}\n`);

const upstreamVersion = JSON.parse(readFileSync(join(HARNESS, "plugin.json"), "utf8")).version;
writeFileSync(
  join(outDir, "package.json"),
  `${JSON.stringify({ name: "pi-pstack", version: upstreamVersion, private: true, type: "module" }, null, 2)}\n`,
);
