# OpenCode Fast Development Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reviewed fast interactive OpenCode workflow while preserving the strict supervisor as the safe default for high-risk work and final integration.

**Architecture:** Introduce `fast-dev` as a second primary agent with read/explore authority, no edit authority, and mandatory implementer -> reviewer routing for repository mutations. Update the existing strict supervisor/process skills with explicit low-ceremony paths for read-only audits, tiny scoped changes, quick debugging triage, single-task SDD, and non-duplicative finishing checks. Tune bounded agent frontmatter and CI workflow commands for objective latency wins, documenting the resulting workflow in the existing OpenCode developer guide.

**Tech Stack:** OpenCode repo-local agent Markdown frontmatter, OpenCode skill Markdown, GitHub Actions YAML, Python-based `make opencode-check`, focused `rg`/diff/YAML review.

## Global Constraints

- Do not edit files while drafting or reviewing this plan.
- This is OpenCode config/workflow work. Implementation of all non-plan/spec edits must route through `implementer` -> `reviewer` -> pass before commit.
- The strict supervisor remains available and remains the default for high-risk development and final integration.
- Do not remove the strict supervisor or weaken it for high-risk work.
- Do not allow unreviewed production/test/config changes.
- Do not bypass capability agents for privileged Git, GitHub, OpenCode config, Windows CI reproduction, or external-directory boundaries.
- Do not make the fast path a license for tactical patches, silent failures, broad compatibility aliases, or design shortcuts.
- Do not change application behavior as part of this workflow-design work except where CI workflow speedups are explicitly implemented later.
- `fast-dev` must not edit production code, tests, `.opencode/**`, workflows, or other repository files directly.
- `fast-dev` must not skip independent review for repository mutations.
- `fast-dev` must not create PRs, push branches, enable auto-merge, or poll merge queues by default.
- `fast-dev` must not use raw privileged Git/GitHub commands instead of capability agents.
- `fast-dev` must not accept patch-around fixes that add special cases, silent failures, or hidden coupling.
- Small fast-mode edits still require implementer -> reviewer before completion.
- Reviewer prompts/checklists explicitly block patchy conditionals, silent failures, misplaced ownership, and spaghetti-design risks.
- Existing strict flows are faster where possible without removing safety gates from high-risk work.
- CI changes reduce obvious latency sources without reducing required coverage for PR/merge-queue correctness.
- OpenCode users must restart after `.opencode/**` changes.
- `.opencode/opencode.json` must keep `"default_agent": "supervisor"`.
- OpenCode agent `model` values must use provider/model-id form. HUMAN_DECISION_REQUIRED before changing any existing agent to a new faster model ID not already present in repository evidence.
- No new `fast-reviewer` agent in this implementation; the existing `reviewer` remains the single independent review gate, with fast-mode checklist text supplied by `fast-dev` and strict process prompts.
- Windows installer required-path removal is out of scope. HUMAN_DECISION_REQUIRED before removing or weakening `build-windows-installer` from required PR/merge-queue validation.
- Because this is prompt/config/workflow work, local validation focuses on `make opencode-check`, text searches, diff review, YAML review, and PR CI. Do not run application suites locally unless implementation unexpectedly changes application code, build system behavior outside `.github/workflows/test.yml`, or reviewer requests broader validation for a concrete risk.
- Acceptance criteria: `fast-dev` exists as a primary agent with clear permissions, escalation rules, micro-design requirements, clean-design guardrails, implementer/reviewer routing, no direct edit authority, and no default integration authority.
- Acceptance criteria: strict workflow skills document opt-in low-risk paths without contradicting high-risk full-flow requirements.
- Acceptance criteria: bounded agent step/model tuning is explicit and does not guess unavailable model IDs.
- Acceptance criteria: GitHub Actions YAML includes Linux build parallelism, CTest parallelism, no duplicated constraints step, PR-run concurrency cancellation that does not cancel merge-group runs, and cached/skipped `sccache` installation.
- Acceptance criteria: `docs/dev/features/opencode-agent-workflow.md` documents strict vs fast flow, restart requirement, local validation expectations, CI speed assumptions, escalation rules, and unresolved human decisions.
- Validation ladder: focused per-task checks are `make opencode-check` for `.opencode/**`, focused text searches for expected/forbidden workflow language, `git diff --check`, and YAML parse/review for `.github/workflows/test.yml`.
- Validation ladder: complete relevant local suite for this prompt/config/workflow surface is `make opencode-check` plus focused text/diff/YAML review; application `make test` is not required for this plan unless implementation changes application behavior.
- Validation ladder: broader final checks are focused local validation from a clean tree, then **PR CI** as the authoritative full integration gate.

---

### Task 1: Fast Interactive Primary Agent

**Files:**
- Create: `.opencode/agents/fast-dev.md`
- Test: `make opencode-check`

**Interfaces:**
- Consumes: Existing subagents `explorer`, `implementer`, `reviewer`, `git-integrator`, `github-operator`, `config-auditor`, `windows-ci-reproducer`; existing domain skills named in `AGENTS.md`.
- Produces: A new primary OpenCode agent named `fast-dev` with frontmatter `mode: primary`, `model: openai/gpt-5.5`, `variant: medium`, `steps: 180`, read/search permissions, no edit permission, and prompt sections that later docs and workflow text can reference by name.

- [ ] **Step 1: Create `.opencode/agents/fast-dev.md` with fail-closed permissions.**

  Required frontmatter shape:

  ```markdown
  ---
  description: Fast primary agent for interactive exploration, small scoped changes, and design-preserving local iteration. Escalates to the strict supervisor for risky, ambiguous, architectural, integration, or broad workflow changes.
  mode: primary
  model: openai/gpt-5.5
  variant: medium
  temperature: 0.2
  steps: 180
  permission:
    read:
      "*": allow
      "*.env": deny
      "*.env.*": deny
      "*.env.example": allow
    glob: allow
    grep: allow
    list: allow
    lsp: allow
    edit: deny
    task: allow
    external_directory: deny
    webfetch: deny
    websearch: deny
    question: deny
    bash:
      "*": deny
      "git status*": allow
      "git diff*": allow
      "git log*": allow
      "git rev-parse*": allow
      "git branch --show-current*": allow
      "make opencode-check": allow
  ---
  ```

  Do not add `git fetch`, `git merge`, `git push`, broad `gh`, `rm`, package-manager, `sudo`, `edit`, or external-directory permissions.

- [ ] **Step 2: Add the agent identity and scope sections.**

  The body must state that `fast-dev` is optimized for interactive development, quick local iteration, and design-preserving small changes, and is not a replacement for the strict supervisor.

  It must include these exact responsibility rules:

  - may perform read-only exploration directly;
  - may use `explorer` for targeted repository searches;
  - must perform a micro-design assessment before edits;
  - must dispatch `implementer` for small scoped changes;
  - must dispatch `reviewer` for focused design/correctness review;
  - may request targeted local validation appropriate to the changed surface;
  - must stop and escalate when clean design requires broader planning.

- [ ] **Step 3: Add fast-mode eligibility and escalation rules.**

  Eligibility must require all of the following:

  - user asks for interactive development, a small scoped change, a targeted bugfix, a focused refactor, or read-only exploration;
  - ownership boundary is clear or can be clarified with a brief micro-design note;
  - validation surface is targeted and local;
  - change does not require a new product/API/data/architecture decision;
  - change does not require final integration, PR creation, merge queue operation, or privileged repository recovery.

  Escalation must trigger when any of the following are true:

  - clean design requires broad refactoring or a new abstraction;
  - multiple subsystems or independent tasks are involved;
  - user asks for branch finishing, ready-to-merge, PR creation, or merge queue follow-through;
  - task touches high-risk workflow policy, capability boundaries, auth, secrets, graph topology/persistence, broad runtime initialization, packaging, or release behavior;
  - reviewer flags design-integrity issues that cannot be fixed locally;
  - validation failure diagnosis requires the full `systematic-debugging` workflow.

- [ ] **Step 4: Add the micro-design note contract.**

  The agent prompt must require a short micro-design note before dispatching implementation, with these fields:

  - desired behavior or problem statement;
  - owning abstraction/module;
  - existing pattern to follow;
  - design risks to avoid;
  - validation surface.

  Include the example from the approved spec, adapted verbatim enough to preserve the command registry ownership lesson.

- [ ] **Step 5: Add implementer handoff guardrails.**

  The prompt must require every implementer dispatch to include:

  - Prefer a coherent local refactor over adding special cases.
  - Do not add compatibility aliases or legacy shims unless the task explicitly requires a migration design.
  - Do not convert failures into no-ops or quiet exits.
  - Keep ownership in the abstraction that already owns the behavior.
  - If the clean solution is broader than the scoped task, stop and report instead of patching around it.
  - Run the narrowest meaningful validation and explain why it covers the changed behavior.

- [ ] **Step 6: Add focused reviewer checklist and review gate.**

  The prompt must state that no repository mutation is complete until the existing `reviewer` returns pass. The review handoff must include this checklist:

  - Does the diff extend the right abstraction?
  - Did it avoid special-case conditionals and patch-around behavior?
  - Did it avoid duplicated state ownership or hidden coupling?
  - Did it preserve explicit errors instead of silent failures?
  - Is the validation appropriate for the risk surface?
  - Should this have escalated to strict supervisor instead?

- [ ] **Step 7: Add domain skill and capability boundary routing.**

  The prompt must say that `fast-dev` should not load heavyweight process skills for every small task, but must still invoke critical project-domain skills when their domain is directly touched:

  - `space-fennel` for Space `.fnl` files and Fennel validation tooling;
  - `space-fennel-ui` for Fennel widgets/layout/rendering;
  - `space-graph-doctrine` for graph topology, persistence, nodes, maps, views, key loaders, and terminology;
  - `space-testing-runtime` for tests, runtime harnesses, profiling, E2E, and build commands.

  It must also route privileged Git/GitHub/OpenCode config/Windows CI work through the existing capability agents and escalate final integration to the strict supervisor/finishing flow.

- [ ] **Step 8: Validate OpenCode agent wiring.**

  Run:

  ```bash
  make opencode-check
  ```

  Expected: pass.

- [ ] **Step 9: Run focused text checks for fast-dev invariants.**

  Run:

  ```bash
  rg -n "mode: primary|edit: deny|task: allow|Micro-design|implementer|reviewer|strict supervisor|HUMAN_DECISION_REQUIRED|OpenCode users must restart" .opencode/agents/fast-dev.md
  ```

  Expected: matches show `mode: primary`, `edit: deny`, `task: allow`, micro-design rules, implementer/reviewer routing, strict supervisor escalation, and restart language.

---

### Task 2: Strict Supervisor Low-Ceremony Routing

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/brainstorming/SKILL.md`
- Modify: `.opencode/skills/writing-plans/SKILL.md`
- Test: `make opencode-check`

**Interfaces:**
- Consumes: Existing strict supervisor workflow, existing `brainstorming` and `writing-plans` skill contracts, `fast-dev` scope from Task 1.
- Produces: Strict-flow routing language that supports read-only audit and tiny-change paths without weakening full spec/plan/SDD/finishing requirements for high-risk or ambiguous work.

- [ ] **Step 1: Update supervisor skill routing to distinguish low-risk paths from full build workflow.**

  Add a section before `## Core Workflow` named `## Low-Ceremony Strict Paths`.

  It must define:

  - **Read-only audit path:** use direct read/glob/grep/list or `explorer`; no spec, plan, implementer, reviewer, or commit when the user requests no repository mutation.
  - **Tiny change path:** use a short micro-design note plus `implementer` -> focused `reviewer`; no committed spec/plan when the task is clear, local, low-risk, and complete as one focused change.
  - **Escalation:** switch to full brainstorming -> writing-plans -> SDD -> finishing when the task is ambiguous, architectural, high-risk, multi-subsystem, or needs final integration.
  - **Review invariant:** every repository mutation, including `.opencode/**`, workflow files, skills, docs outside supervisor allowlist, tests, and config, still requires `implementer` -> `reviewer` -> pass.

- [ ] **Step 2: Update supervisor red flags and core workflow.**

  Preserve the existing red flag that small changes still require review. Add a corresponding positive rule: small eligible changes may skip committed specs/plans only when the low-ceremony strict path criteria are met, but never skip implementer/reviewer.

  Update `When the human asks to build something:` so it first classifies the request as:

  1. read-only audit,
  2. tiny change,
  3. full strict flow.

  The full strict flow must remain unchanged for high-risk work.

- [ ] **Step 3: Update the supervisor subagent table.**

  Add `fast-dev` to the table as a primary peer, not a subagent, with wording that the strict supervisor does not dispatch it as an implementation worker. The table or nearby text must say users select `fast-dev` for interactive small work, while the strict supervisor remains the default for high-risk work and final integration.

- [ ] **Step 4: Relax the brainstorming hard gate only for explicit low-risk exclusions.**

  In `.opencode/skills/brainstorming/SKILL.md`, replace the absolute “EVERY project” language with a bounded rule:

  - brainstorming remains mandatory before full creative feature work, architectural changes, ambiguous changes, broad refactors, and high-risk work;
  - brainstorming is not required for read-only audits;
  - brainstorming is not required for a tiny change path that the supervisor has explicitly classified as eligible and that still routes mutation through `implementer` -> `reviewer` -> pass;
  - any uncertainty escalates back to brainstorming.

  Preserve the existing spec/plan hard gate for normal full-flow work.

- [ ] **Step 5: Update writing-plans scope language.**

  In `.opencode/skills/writing-plans/SKILL.md`, add a short section near `## Scope Check`:

  - writing-plans is required for approved specs, multi-step tasks, architectural changes, ambiguous work, high-risk changes, and normal strict-flow implementation;
  - writing-plans is not invoked for read-only audits;
  - writing-plans is not invoked for supervisor-classified tiny changes that use a micro-design note and `implementer` -> `reviewer` -> pass;
  - if the tiny change grows beyond one coherent local change, stop and create a plan.

- [ ] **Step 6: Validate OpenCode prompt/config policy.**

  Run:

  ```bash
  make opencode-check
  ```

  Expected: pass.

- [ ] **Step 7: Run focused contradiction checks.**

  Run:

  ```bash
  rg -n "Read-only audit path|Tiny change path|micro-design|brainstorming remains mandatory|writing-plans is required|implementer.*reviewer.*pass|strict supervisor remains" .opencode/agents/supervisor.md .opencode/skills/brainstorming/SKILL.md .opencode/skills/writing-plans/SKILL.md
  ```

  Expected: matches show the new fast paths and preserved review/full-flow gates.

---

### Task 3: Process Skill Fast Paths and Finishing De-Duplication

**Files:**
- Modify: `.opencode/skills/subagent-driven-development/SKILL.md`
- Modify: `.opencode/skills/systematic-debugging/SKILL.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Test: `make opencode-check`

**Interfaces:**
- Consumes: Supervisor low-ceremony routing from Task 2.
- Produces: Skill-level contracts for single-task SDD, quick debugging triage, and non-duplicative finishing checks that the supervisor and `fast-dev` can rely on.

- [ ] **Step 1: Add single-task SDD path to `subagent-driven-development`.**

  Add a section before `## Final Whole-Branch Review` named `## Single-Task Low-Risk Path`.

  It must state:

  - eligible only when one focused task covers the complete diff;
  - each task still dispatches `implementer`;
  - each task still dispatches `reviewer`;
  - fix loop and adjudicator rules remain unchanged;
  - the final whole-branch review may be skipped only when the reviewer passed, there are no parked findings, no reviewer request for broader review, no high-risk surface, and the plan/controller explicitly marked the run single-task low-risk;
  - if any condition fails, run the normal final whole-branch review.

- [ ] **Step 2: Update SDD finish language.**

  Preserve the existing finishing handoff and PR CI language. Add that skipping final whole-branch review in the single-task path is not a ready-to-merge claim and does not skip finishing validation, current-base checks, or PR CI.

- [ ] **Step 3: Add quick debugging triage to `systematic-debugging`.**

  Add a section before `## The Four Phases` named `## Quick Debugging Triage`.

  It must allow only read-only reproduction and inspection before the full phases when the failure appears obvious and localized. It must require escalation into the full four phases when:

  - root cause is unclear;
  - reproduction is not consistent;
  - a first localized hypothesis fails;
  - the surface is high-risk;
  - the fix would touch multiple subsystems;
  - any code/config/test/workflow edit is needed.

  It must preserve the iron law: no repository fix without root cause investigation and no unreviewed fixes.

- [ ] **Step 4: Update finishing freshness de-duplication.**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, keep Step 1’s final `origin/main` freshness gate, but prevent immediate back-to-back duplicate fetch/status checks.

  Required behavior:

  - record the wrapper evidence from the most recent `git-integrator fetch-origin` + `status` check in the current finishing pass;
  - reuse that evidence if no validation, fix, push, PR creation, merge, or meaningful time gap occurred after it;
  - re-fetch/recheck before integration when validation ran after the check, origin evidence is missing, push/PR creation failed, or the supervisor cannot prove the prior check is still the latest integration gate;
  - never rebase or force-push;
  - post-PR freshness remains the merge queue’s job.

- [ ] **Step 5: Preserve validation failure recovery language.**

  Ensure the finishing skill still requires `systematic-debugging`, `implementer` -> `reviewer` -> pass, rerun validation from a clean/current-base tree, and **PR CI** before ready-to-merge claims.

- [ ] **Step 6: Validate OpenCode skill policy.**

  Run:

  ```bash
  make opencode-check
  ```

  Expected: pass.

- [ ] **Step 7: Run focused text checks for skill contracts.**

  Run:

  ```bash
  rg -n "Single-Task Low-Risk Path|final whole-branch review may be skipped|Quick Debugging Triage|no repository fix without root cause|reuse that evidence|post-PR freshness remains the merge queue" .opencode/skills/subagent-driven-development/SKILL.md .opencode/skills/systematic-debugging/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md
  ```

  Expected: matches show the new paths and preserved safety gates.

---

### Task 4: Bounded Agent Frontmatter Tuning

**Files:**
- Modify: `.opencode/agents/explorer.md`
- Modify: `.opencode/agents/git-integrator.md`
- Modify: `.opencode/agents/github-operator.md`
- Modify: `.opencode/agents/config-auditor.md`
- Modify: `.opencode/agents/pr-recovery-operator.md`
- Modify: `.opencode/agents/windows-ci-reproducer.md`
- Modify: `.opencode/agents/supervisor.md`
- Test: `make opencode-check`

**Interfaces:**
- Consumes: Existing agent frontmatter and supervisor subagent table.
- Produces: Reduced step limits for bounded/search/wrapper agents and a documented model-decision boundary that does not guess unavailable model IDs.

- [ ] **Step 1: Preserve high-reasoning model assignments.**

  Do not lower or weaken these agents:

  - `.opencode/agents/supervisor.md`
  - `.opencode/agents/planner.md`
  - `.opencode/agents/reviewer.md`
  - `.opencode/agents/debug-advisor.md`
  - `.opencode/agents/adjudicator.md`

  The strict supervisor may have table text updated, but its frontmatter model, variant, and step limit remain unchanged in this task.

- [ ] **Step 2: Reduce bounded agent step limits.**

  Change only the `steps` field for these files unless HUMAN_DECISION_REQUIRED is resolved with exact faster model IDs:

  - `.opencode/agents/explorer.md`: `steps: 20`
  - `.opencode/agents/git-integrator.md`: `steps: 18`
  - `.opencode/agents/github-operator.md`: `steps: 25`
  - `.opencode/agents/config-auditor.md`: `steps: 15`
  - `.opencode/agents/pr-recovery-operator.md`: `steps: 15`
  - `.opencode/agents/windows-ci-reproducer.md`: `steps: 20`

- [ ] **Step 3: Do not guess faster model IDs.**

  If the human supplies exact approved provider/model-id values before implementation of this task, update the `model:` field for the deterministic/search/wrapper agents listed in Step 2 and update the supervisor subagent table to match.

  If no exact provider/model-id values are supplied, leave `model: openai/gpt-5.5` unchanged for those files and add a note to `.opencode/agents/supervisor.md` near the subagent table:

  ```markdown
  Faster-model swaps for deterministic/search/wrapper agents require exact approved provider/model-id values. Do not use shorthand model names or infer availability from comments.
  ```

- [ ] **Step 4: Align the supervisor subagent table with frontmatter.**

  Update model labels in `.opencode/agents/supervisor.md` so the table does not claim a model that differs from agent frontmatter. If model fields remain unchanged, the table must say `gpt-5.5` for explorer, implementer, and wrapper agents rather than unverified shorthand.

- [ ] **Step 5: Validate OpenCode policy after frontmatter edits.**

  Run:

  ```bash
  make opencode-check
  ```

  Expected: pass.

- [ ] **Step 6: Run focused frontmatter checks.**

  Run:

  ```bash
  rg -n "steps: (15|18|20|25)|model: openai/gpt-5.5|Faster-model swaps" .opencode/agents/explorer.md .opencode/agents/git-integrator.md .opencode/agents/github-operator.md .opencode/agents/config-auditor.md .opencode/agents/pr-recovery-operator.md .opencode/agents/windows-ci-reproducer.md .opencode/agents/supervisor.md
  ```

  Expected: step limits match Step 2 and model text is not contradictory.

---

### Task 5: GitHub Actions CI Latency Improvements

**Files:**
- Modify: `.github/workflows/test.yml`
- Test: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: Existing `test` workflow jobs and CTest constraints fixture in `CMakeLists.txt`.
- Produces: Faster CI workflow with unchanged required coverage and merge-group safety.

- [ ] **Step 1: Add workflow concurrency that does not cancel merge groups.**

  Add top-level YAML after `on:`:

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: ${{ github.event_name != 'merge_group' }}
  ```

  This must cancel superseded branch/PR runs while preserving merge-group runs.

- [ ] **Step 2: Use all Linux cores for the main Linux build.**

  Change the Linux `Build` step from:

  ```yaml
  run: make build
  ```

  to:

  ```yaml
  run: make BUILD_JOBS=$(nproc) build
  ```

- [ ] **Step 3: Remove the duplicated explicit constraints step.**

  Delete the standalone step:

  ```yaml
  - name: Run constraints
    run: make constraints
  ```

  This is safe because `CMakeLists.txt` registers `${PROJECT_NAME}_constraints` as `FIXTURES_SETUP space_constraints`, and the Fennel/SSH CTest entries require that fixture.

- [ ] **Step 4: Run CTest in parallel.**

  Change the Linux test-suite command from:

  ```yaml
  xvfb-run -a ctest --test-dir build --output-on-failure -V
  ```

  to:

  ```yaml
  xvfb-run -a ctest --test-dir build --output-on-failure -V --parallel "$(nproc)"
  ```

- [ ] **Step 5: Cache and skip repeated `sccache` binary installation.**

  Add a cache step before `Install sccache`:

  ```yaml
  - name: Restore sccache binary
    uses: actions/cache@v5
    with:
      path: ~/.cargo/bin/sccache
      key: sccache-bin-${{ runner.os }}-0.16.0
  ```

  Change `Install sccache` to:

  ```yaml
  - name: Install sccache
    run: |
      if command -v sccache >/dev/null 2>&1; then
        sccache --version
      else
        cargo install sccache --version 0.16.0 --locked
      fi
  ```

- [ ] **Step 6: Leave Windows installer packaging in required CI.**

  Do not remove, skip, or weaken `build-windows-installer`. Add no condition that excludes it from pull requests or merge groups. This remains HUMAN_DECISION_REQUIRED for a later product/process decision.

- [ ] **Step 7: Validate YAML syntax locally.**

  Run:

  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/test.yml")'
  ```

  Expected: command exits 0.

- [ ] **Step 8: Run workflow-focused text checks.**

  Run:

  ```bash
  rg -n "concurrency:|cancel-in-progress:|BUILD_JOBS=\$\(nproc\) build|--parallel \"\$\(nproc\)\"|Restore sccache binary|cargo install sccache --version 0.16.0" .github/workflows/test.yml
  ```

  Expected: all intended speedup constructs are present.

  Run:

  ```bash
  ! rg -n "name: Run constraints|run: make constraints" .github/workflows/test.yml
  ```

  Expected: no standalone constraints step remains.

- [ ] **Step 9: Run whitespace/diff checks.**

  Run:

  ```bash
  git diff --check .github/workflows/test.yml
  ```

  Expected: pass.

---

### Task 6: Developer Documentation and Final Local Validation

**Files:**
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:**
- Consumes: `fast-dev` behavior from Task 1, strict flow updates from Tasks 2-3, agent tuning from Task 4, CI workflow changes from Task 5.
- Produces: Canonical developer documentation for strict vs fast OpenCode workflow, restart requirements, validation, CI speedups, unresolved model and Windows-installer decisions, and out-of-scope boundaries.

- [ ] **Step 1: Add a `Fast interactive development flow` section.**

  In `docs/dev/features/opencode-agent-workflow.md`, add a section after `## Space workflow expectations` or another nearby workflow section.

  It must document:

  - `supervisor` remains default and strict;
  - `fast-dev` is a second primary agent for interactive exploration and small scoped changes;
  - `fast-dev` performs micro-design before edits;
  - repository mutations still require `implementer` -> `reviewer` -> pass;
  - final integration stays with strict supervisor/finishing unless the human explicitly requests otherwise under a later approved design.

- [ ] **Step 2: Document eligibility and escalation.**

  Add bullets matching the Task 1 eligibility/escalation rules. Include high-risk examples from the spec: workflow policy, capability boundaries, auth, secrets, graph topology/persistence, broad runtime initialization, packaging, and release behavior.

- [ ] **Step 3: Document strict-flow low-ceremony paths.**

  Add a subsection explaining:

  - read-only audit path;
  - tiny change path;
  - quick debugging triage;
  - single-task SDD path;
  - no path skips review for mutations;
  - no path claims ready-to-merge before finishing validation and PR CI.

- [ ] **Step 4: Document OpenCode restart requirement.**

  Ensure the page clearly repeats:

  ```markdown
  Restart OpenCode after `.opencode/**` changes. Agent definitions, skill instructions, and permission rules are loaded at startup and are not hot-reloaded.
  ```

- [ ] **Step 5: Document CI latency changes.**

  Add a concise subsection under the CI/capability area describing:

  - Linux build uses `make BUILD_JOBS=$(nproc) build`;
  - CTest runs in parallel in CI;
  - constraints are not run as a separate duplicated workflow step because CTest owns the constraints fixture;
  - PR workflow concurrency cancels superseded PR runs but not merge-group runs;
  - `sccache` binary installation is skipped when restored from cache;
  - Windows installer required-path removal remains HUMAN_DECISION_REQUIRED.

- [ ] **Step 6: Document model decision boundary.**

  Add a note that deterministic/search/wrapper agents may move to faster models only when exact approved provider/model-id values are supplied. Do not document shorthand model names as valid config.

- [ ] **Step 7: Run OpenCode policy validation.**

  Run:

  ```bash
  make opencode-check
  ```

  Expected: pass.

- [ ] **Step 8: Run focused documentation checks.**

  Run:

  ```bash
  rg -n "fast-dev|micro-design|implementer.*reviewer.*pass|Restart OpenCode|BUILD_JOBS=\$\(nproc\)|CTest runs in parallel|HUMAN_DECISION_REQUIRED|PR CI" docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: matches show the documented behavior, restart rule, CI speedups, unresolved decisions, and PR CI gate.

- [ ] **Step 9: Run complete local prompt/config/workflow validation from a clean tree.**

  Run:

  ```bash
  make opencode-check
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/test.yml")'
  git diff --check
  rg -n "fast-dev|Read-only audit path|Tiny change path|Quick Debugging Triage|Single-Task Low-Risk Path|cancel-in-progress|BUILD_JOBS=\$\(nproc\)" .opencode docs/dev/features/opencode-agent-workflow.md .github/workflows/test.yml
  ! rg -n "name: Run constraints|run: make constraints" .github/workflows/test.yml
  ```

  Expected: all commands pass, intended workflow language is present, duplicated constraints step is absent.

- [ ] **Step 10: Treat PR CI as the integration gate.**

  After implementation, review, commits, and clean-tree final local validation, the strict finishing flow must create/update the PR through capability agents. **PR CI** is the authoritative full integration gate for this workflow/config/CI change.
