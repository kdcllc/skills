---
title: "Research: Forge-Adapter Support for PR Delivery (Azure DevOps first)"
topic: forge-adapter-support
date: 2026-08-26
status: shipped
shipped_in: ["1.0.0"]
goals: [forge-adapter-delivery]
supersedes: []
memory: [20260826T120005Z-8afeea66]
---

# Research: Forge-Adapter Support for PR Delivery (Azure DevOps first)

**Method**: `research` skill — self-contained prompt
(`_memory/work/research/forge-adapter-support/prompt.md`) → external deep-research report
(saved at `_memory/work/research/forge-adapter-support/report.md`, scratch) → critical
ingestion against the kit's codebase and primary sources. Scratch lives under
`_memory/work/research/`; **this brief is canonical.**

The `setup-interview-hardening` follow-up (STORY-016) remains pending.

**Trigger**: a pre-release install field report from an Azure DevOps-hosted project. The
kit's Phase 7 delivery (`ship-pr`) is GitHub/`gh`-only, and the setup interview's
instruction for non-GitHub repos ("delete Phase 7 from the emitted ORCHESTRATION.md")
understates a fan-out of ~14 reference sites across four template files, leaving the
emitted kit incoherent. All of the field report's codebase claims were verified against
the kit at the time and held. The report also raised two adjacent gaps this research verified:
single-family model rotation on Claude-only installs, and path-scoped rules not
reaching subagents.

---

## Part 1 — Findings

### 1.1 Azure DevOps delivery works via `az repos pr` — cloud only

The complete documented CLI path for `dev.azure.com` / legacy `visualstudio.com`
remotes ([learn.microsoft.com/cli/azure/repos/pr](https://learn.microsoft.com/cli/azure/repos/pr)):

- **Extension**: `az extension add --name azure-devops` (auto-installs on first
  `az repos` use; explicit install avoids a first-run prompt in scripted flows).
- **Auth**: `az login` (Entra) or `AZURE_DEVOPS_EXT_PAT` for automation. **Footgun**:
  an active `az login` token *overrides* a narrowly-scoped PAT — the PAT is a
  fallback, so least-privilege PAT assumptions can be silently bypassed.
- **Context**: `--detect` (on by default) resolves org/project/repo from the git
  remote; explicit `--org`/`--project`/`--repository` take precedence and are the
  robust fallback.
- **Create**: `az repos pr create --source-branch <b> --target-branch <base>
  --title … --description …` (markdown; each arg value is a new line), `--draft`,
  `--reviewers`, `--work-items`, `--auto-complete`. `--target-branch` defaults to the
  target repo's default branch.
- **Idempotency**: no create-or-update flag. Existence check first —
  `az repos pr list --source-branch <b> --target-branch <base> --status active` —
  then route to `az repos pr update --id <id>`. Mirrors the kit's current
  `gh pr create` / `gh pr edit` split.
- **Edge cases**: branch must be pushed first (no server ref otherwise); duplicate
  create for the same source/target pair fails server-side; branch policies gate
  *completion*, not creation; PAT needs Code (Read & Write) scope.

**Hard limit**: Microsoft states "Azure DevOps CLI commands aren't supported for
Azure DevOps Server" — on-prem has no `az repos` path at all.

### 1.2 On-prem / no-CLI fallback: draft, push, hand over a URL

For on-prem ADO Server or any undetected forge: draft the PR title/body, get human
approval, push the branch, then print a ready-to-use artifact and **stop** — either
the PR-creation URL that `git push` output surfaces (ADO Services), a constructed
`…/_git/{repo}/pullrequestcreate?sourceRef=…&targetRef=…` web URL, or the exact
create command. The REST alternative
(`POST …/pullrequests?api-version=7.1` on cloud) uses *different* api-versions on
Server (community tooling pins TFS to 4.0/4.1) — a REST fallback must discover the
server's supported version, never assume 7.1. The hand-over design is what git-town's
`propose` does for unsupported forges, and it is the only branch that preserves the
kit's human-approval invariant with zero risk.

### 1.3 Forge detection and multi-remote resolution

- **URL patterns are reliable for**: GitHub (`github.com`), Azure DevOps
  (`dev.azure.com`, `ssh.dev.azure.com:v3/…`, `{org}.visualstudio.com`,
  `vs-ssh.visualstudio.com` — the `_git` path segment is a strong signal), and
  `gitlab.com`. **Structurally undetectable**: self-hosted GitLab/Gitea and GHE
  custom domains — an explicit override is mandatory, not optional (every precedent
  tool ships one).
- **Multi-remote precedence**: `gh` resolves the base repo in **upstream → github →
  origin** order, with a persisted per-repo override (`gh repo set-default` →
  `remote.<name>.gh-resolved` in git config). Copy the shape: deterministic
  precedence + a one-time explicit override.
- **Default branch without a forge CLI**: primary resolver is
  `git ls-remote --symref <remote> HEAD` (authoritative, network, works on all three
  forges with the remote's own auth); offline fallback is the cached
  `refs/remotes/<remote>/HEAD` symref (commonly unset after `git init` +
  `remote add`, or broken after a default-branch rename; `git remote set-head
  <remote> -a` repairs it, with network). **Resolve the base from the same remote the
  PR will target**, never a bare "origin". **Stop and ask the human** when the chosen
  remote's HEAD is unresolvable, when two candidate remotes resolve to different
  forges, or when the detected base differs from the branch the commits diverged
  from.
- **GitLab parity confirmed**: `glab mr create` covers draft (`--draft`),
  title/description/`--fill`, target-branch defaulting, `glab mr list` as the
  existence check, and `GITLAB_HOST` for self-hosted.

### 1.4 Precedents converge on the same adapter shape

- **git-town** (closest match): URL-detect from the development remote + explicit
  `forge-type` config override (+ `origin-hostname` for SSH aliases); connectors are
  CLI-based (`gh`, `glab`) or token-API; unsupported forges degrade to a pre-filled
  browser URL. Azure DevOps support exists but is flagged *experimental*.
- **git-pkgs/forge**: routes by URL domain; documented config precedence (CLI flags →
  env vars → committed `.forge` file → user config → defaults); a committed
  domain→type file is the most ergonomic self-hosted story.
- **OpenHands**: per-provider `GitService` implementations behind a facade, but
  detection *iterates providers until one succeeds* — a documented mis-routing
  liability (issue #9725). Anti-pattern: prefer URL-domain routing.
- **Synthesis**: a small adapter surface — detect(remoteURL) → {github, azuredevops,
  gitlab, none}, resolveBase(remote), findExistingPR, createPR/updatePR, and an
  emit-manual-instructions branch — expresses the kit's current `gh` path unchanged
  and maps one-to-one onto the field report's proposed table.

### 1.5 Single-family model rotation: the gap is real; effort-escalation is unproven

- Claude Code exposes **no non-Anthropic model natively** — only gateway/proxy
  workarounds (`ANTHROPIC_BASE_URL` routers, LiteLLM/OpenRouter), and Bedrock/Vertex
  still serve Anthropic models. On a Claude-only install,
  `{{MODEL_ALT_FAMILY}}`/`{{MODEL_FRONTIER_ALT_FAMILY}}` genuinely cannot resolve to
  a different family.
- The cross-model premise is evidence-backed: Self-Correction Bench
  ([arXiv:2507.02778](https://arxiv.org/abs/2507.02778)) measures a 64.5%
  self-correction blind spot (14 open non-reasoning models — cohort-specific, not a
  universal constant); Tan et al. ([arXiv:2505.17656](https://arxiv.org/abs/2505.17656),
  EMNLP 2025) find self-consistent errors "rarely overlap across different LLMs" and
  validate cross-model verification.
- **Raising reasoning effort within one family has no direct published support** as a
  substitute. Evidence-backed same-family mitigations: reintroduce the error as
  *external* feedback, and reflection prompts (appending "Wait" cut blind spots by
  89.3% in-bench). Honest degraded mode: same-family retry with external-feedback
  framing + reflection, an explicit notice that cross-family arbitration is
  unavailable, and earlier human escalation — do not document effort-escalation as
  recovering the cross-family benefit.

### 1.6 Path-scoped rules and fresh-context subagents (all four harnesses)

Path/glob-scoped instructions are unreliable for subagents everywhere: Claude Code
`paths:` rules do not load at spawn (global rules + CLAUDE.md do; a rule *may* fire
dynamically if the subagent itself touches matching files —
[claude-code#32906](https://github.com/anthropics/claude-code/issues/32906)); Cursor
subagents "start fresh" (glob-into-subagent behavior only community-observed);
Copilot `applyTo:` instructions attach only to files being worked on, and the coding
agent reads instructions from the PR *base* branch; Codex has no glob scoping at all
(nearest AGENTS.md wins, 32 KiB cap, silent truncation). **Portable pattern**: put
subagent-critical conventions in the always-loaded root file per harness or in the
subagent definition/context package — never rely on scoped rule files reaching
workers. Setup should detect scoped-rule setups (`paths:`/`globs:`/`applyTo:`) and
emit an explicit citation table into the orchestrator's context-package instructions.

### 1.7 Cross-platform emission: never route prose through sed/heredoc

Templates full of typographic quotes and em-dashes corrupt under heredoc/sed quoting
and locale passes; `envsubst` is POSIX-only and `$VAR`-shaped. Documented-good:
Python `string.Template`-style substitution (no shell pass) or PowerShell literal
here-strings, always with explicit UTF-8 I/O. For this kit: a tiny `{{TOKEN}}` regex
replace in whatever runtime the installer runs, explicit UTF-8, no shell-quoting of
prose.

---

## Part 2 — Critical ingestion notes (corrections and flags)

1. **Override storage**: the report suggests `git config orchestration-kit.forge-type`
   as one option. The kit's `ship-pr` guardrail is "never update git config" — the
   override belongs in `orchestration-kit.manifest.json` (an `options.forge` key),
   which setup already owns on install and re-run. A git-config *read* (respecting a
   user-set key) is fine; the kit must not write it.
2. **"Copilot CLI uses `.agent.md`, not AGENTS.md"** — dubious/possibly stale;
   GitHub has been rolling AGENTS.md support across Copilot surfaces. Does not affect
   the D9 conclusion (always-loaded root file), but re-verify before emitting
   Copilot-specific guidance.
3. **Community-inferred details to re-verify at implementation time**: the TF400898
   duplicate-reviewer error, on-prem REST api-version 4.0/4.1 pinning, and the
   `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` env var.
4. **Tension with the field report's own fix**: the installer who filed the feedback
   resolved the single-family gap with effort-escalation (cycle 2 `effort: high`,
   arbitration `effort: max`). Per §1.5 that substitution is unproven — the kit's
   degraded mode should lead with external-feedback framing + reflection + earlier
   human escalation, and may *offer* effort-escalation only labeled as untested.
5. **Scope note**: the report's staged rollout (interface → ADO cloud → detection →
   GitLab/none) is a proposal, not a decision — the kit's goal/task structure and
   what lands in which version are decided in planning with the evaluator gate.

## Open questions (carried forward)

1. `az repos pr list --source-branch` matching: short branch names vs `refs/heads/…`
   across CLI versions — the existence check should test both forms.
2. Legacy `vs-ssh.visualstudio.com` remotes: does `--detect` resolve org/project, or
   must the adapter parse the URL explicitly?
3. Whether raising reasoning effort measurably reduces same-family self-correction
   blindness — no published study; would need an internal A/B to claim.
4. Whether any first-party agent product ships a documented forge-adapter
   abstraction to benchmark against (none found in this pass).
