# OpenCode Fast Development Flow Design

## Purpose

The current project OpenCode workflow is intentionally strict: the supervisor
coordinates planning, implementation, independent review, finishing checks, and
GitHub integration. That safety model is valuable, but ordinary interactive
development is slow because small audits and small iterations pay the same
ceremony cost as high-risk feature work.

This design splits speed work into two complementary tracks:

1. **Optimize the existing strict flow** so the current supervisor remains safe
   but avoids avoidable latency.
2. **Add a second primary agent for fast interactive development** that uses
   micro-design and focused review instead of full specs/plans for low-risk
   iteration.

The goal is faster iteration without drifting into patchy conditional logic,
compatibility shims, or spaghetti code.

## Non-Goals

- Do not remove the strict supervisor or weaken it for high-risk work.
- Do not allow unreviewed production/test/config changes.
- Do not bypass capability agents for privileged Git, GitHub, OpenCode config,
  Windows CI reproduction, or external-directory boundaries.
- Do not make the fast path a license for tactical patches, silent failures,
  broad compatibility aliases, or design shortcuts.
- Do not change application behavior as part of this workflow-design work except
  where CI workflow speedups are explicitly implemented later.

## Design Principles

### Fast means lower ceremony, not lower design quality

The fast flow optimizes around smaller scope, quicker context gathering, and
tighter feedback. It must still ask the design questions that prevent patches:

- Which abstraction owns this behavior?
- Is this a local fix or a missing design concept?
- Would this introduce a special-case conditional future code must remember?
- Is there an existing pattern to extend instead?
- Is a small coherent refactor required before the behavior change?

If a clean answer is not available within the current scope, the fast agent
stops and escalates to the strict supervisor flow.

### Strict remains the integration authority

The fast agent can help explore, iterate, and produce reviewed commits. It does
not claim ready-to-merge, create PRs, enable auto-merge, or poll merge queues by
default. Final integration continues through the strict supervisor and finishing
branch workflow unless the human explicitly requests otherwise and the required
guardrails are updated in a later approved design.

### Safety is routed by risk, not by file count

A one-line change can be architectural if it adds a bad abstraction boundary. A
larger change can be fast-path eligible if it is mechanical and locally
validated. The fast agent should choose the path based on risk surface and
design clarity.

## Track 1: Make Existing Strict Flows Faster

These changes preserve the current supervisor contract while reducing avoidable
latency.

### Agent model and step tuning

- Keep high-reasoning models for roles that need judgment:
  - strict supervisor when running the full process
  - planner
  - reviewer
  - debug-advisor
  - adjudicator when genuinely needed
- Move deterministic/search/wrapper agents to faster models where available:
  - explorer
  - git-integrator
  - github-operator
  - config-auditor
  - pr-recovery-operator
  - windows-ci-reproducer
- Reduce excessive step limits on agents whose work is bounded by wrapper
  output or short reports.

### Skill fast paths inside strict flow

Add explicit low-risk modes to existing process skills so they do not inject the
full ceremony for tasks that do not need it:

- **Read-only audit path:** no spec, plan, or implementer/reviewer loop when no
  repository mutation is requested.
- **Tiny change path:** short design note plus implementer -> focused reviewer;
  no committed spec/plan unless the task is ambiguous, architectural, or risky.
- **Quick debugging triage:** reproduce and inspect obvious/localized failures;
  escalate to full systematic debugging when root cause is unclear, failures
  repeat, or the surface is high-risk.
- **Single-task SDD path:** when one focused task covers the complete diff, skip
  the final whole-branch review unless the reviewer or risk surface requires it.

These fast paths should be opt-in through clear eligibility rules, not informal
exceptions.

### Remove duplicated finishing work

The finishing workflow should keep the final `origin/main` freshness gate but
avoid repeating fetch/base checks back-to-back unless time elapsed, origin
moved, or push/PR creation failed. Post-PR freshness remains the merge queue's
job.

### CI latency improvements

The CI workflow should get objective speedups without changing correctness:

- Use all available cores for Linux builds: `make BUILD_JOBS=$(nproc) build`.
- Run CTest in parallel where target dependencies allow it.
- Avoid running constraints twice when CTest already includes the constraints
  fixture.
- Add workflow concurrency so superseded PR runs are canceled while merge-group
  runs are not canceled.
- Avoid installing `sccache` from Cargo on every run when a cache, prebuilt
  action, or runner image can provide it.
- Reevaluate whether Windows installer packaging belongs in the required PR and
  merge-queue path or should move to release/manual validation.

## Track 2: Add a Fast Interactive Primary Agent

### Agent identity

Add a second primary agent, tentatively named `fast-dev`.

The agent is optimized for interactive development, quick local iteration, and
design-preserving small changes. It is not a replacement for the strict
supervisor.

Suggested description:

> Fast primary agent for interactive exploration, small scoped changes, and
> design-preserving local iteration. Escalates to the strict supervisor for
> risky, ambiguous, architectural, integration, or broad workflow changes.

### Responsibilities

`fast-dev` may:

- perform read-only exploration directly;
- use explorer for targeted repository searches;
- perform a micro-design assessment before edits;
- dispatch implementer for small scoped changes;
- dispatch reviewer for focused design/correctness review;
- request targeted local validation appropriate to the changed surface;
- stop and escalate when clean design requires broader planning.

`fast-dev` must not:

- edit production code, tests, `.opencode/**`, workflows, or other repository
  files directly;
- skip independent review for repository mutations;
- create PRs, push branches, enable auto-merge, or poll merge queues by default;
- use raw privileged Git/GitHub commands instead of capability agents;
- accept patch-around fixes that add special cases, silent failures, or hidden
  coupling.

### Eligibility for fast mode

Fast mode is appropriate when all of the following are true:

- The user is asking for interactive development, a small scoped change, a
  targeted bugfix, a focused refactor, or read-only exploration.
- The ownership boundary is clear or can be clarified with a brief micro-design
  note.
- The validation surface is targeted and local.
- The change does not require a new product/API/data/architecture decision.
- The change does not require final integration, PR creation, merge queue
  operation, or privileged repository recovery.

Fast mode must escalate to strict supervisor when any of the following are true:

- The clean design requires broad refactoring or a new abstraction.
- Multiple subsystems or independent tasks are involved.
- The user asks for branch finishing, ready-to-merge, PR creation, or merge
  queue follow-through.
- The task touches high-risk workflow policy, capability boundaries, auth,
  secrets, graph topology/persistence, broad runtime initialization, packaging,
  or release behavior.
- A reviewer flags design-integrity issues that cannot be fixed locally.
- Validation failure diagnosis requires the full systematic-debugging workflow.

### Micro-design note

Before dispatching implementation, `fast-dev` records a short note in the
handoff prompt rather than creating a committed spec. The note should include:

- desired behavior or problem statement;
- owning abstraction/module;
- existing pattern to follow;
- design risks to avoid;
- validation surface.

For example:

```text
Micro-design: Extend the existing command registry behavior rather than adding
call-site conditionals. The registry owns command discovery and availability;
callers should not special-case command names. Prefer a small helper if two call
sites need the same predicate. Validate with the focused command tests.
```

### Implementation handoff contract

When dispatching implementer, `fast-dev` must include clean-design constraints:

- Prefer a coherent local refactor over adding special cases.
- Do not add compatibility aliases or legacy shims unless the task explicitly
  requires a migration design.
- Do not convert failures into no-ops or quiet exits.
- Keep ownership in the abstraction that already owns the behavior.
- If the clean solution is broader than the scoped task, stop and report instead
  of patching around it.
- Run the narrowest meaningful validation and explain why it covers the changed
  behavior.

### Focused reviewer contract

The reviewer should verify both correctness and design integrity. The review
prompt should include a fast-mode checklist:

- Does the diff extend the right abstraction?
- Did it avoid special-case conditionals and patch-around behavior?
- Did it avoid duplicated state ownership or hidden coupling?
- Did it preserve explicit errors instead of silent failures?
- Is the validation appropriate for the risk surface?
- Should this have escalated to strict supervisor instead?

Important design-integrity findings remain blocking even in fast mode.

### Relationship to skills

`fast-dev` should not load heavyweight process skills for every small task.
Instead, it should apply its embedded micro-design and escalation rules.

It should still invoke project-domain skills when their domain is directly
touched and the skill contains critical project-specific constraints, for
example:

- `space-fennel` for Space `.fnl` files and Fennel validation tooling;
- `space-fennel-ui` for Fennel widgets/layout/rendering;
- `space-graph-doctrine` for graph topology, persistence, nodes, maps, views,
  key loaders, and graph terminology;
- `space-testing-runtime` for tests, runtime harnesses, profiling, E2E, and
  build commands.

Those skills should be used for domain constraints, not as a reason to expand a
small fast-mode task into the full strict lifecycle.

## OpenCode Configuration Shape

The implementation should prefer file-based agents in `.opencode/agents/`.

Expected new or changed files in a later implementation plan:

- `.opencode/agents/fast-dev.md` for the new primary agent.
- Possibly `.opencode/agents/fast-reviewer.md` if focused fast-mode review is
  cleaner as a separate lighter reviewer than as prompt instructions to the
  existing reviewer.
- Existing agent frontmatter updates for model/variant/step tuning.
- Existing skill text updates for explicit fast paths.
- `.github/workflows/test.yml` updates for CI speedups.

Because `.opencode/**` and workflow edits affect agent behavior and CI, later
implementation must go through implementer -> reviewer -> pass before commit.
OpenCode users must restart after `.opencode/**` changes.

## Error Handling and Escalation

- If `fast-dev` cannot identify the owning abstraction, it asks one concise
  clarifying question or escalates to strict supervisor.
- If implementer reports that a clean solution requires broader changes,
  `fast-dev` stops and presents the tradeoff instead of demanding a patch.
- If reviewer finds design-integrity issues, route a focused fix through
  implementer -> reviewer. If the second review still indicates architectural
  uncertainty, escalate.
- If required validation fails and the root cause is not obvious/localized,
  escalate to systematic-debugging under the strict workflow.
- If branch finishing or PR integration is requested, hand off to strict
  supervisor/finishing flow.

## Testing and Validation Strategy

For the workflow/config implementation itself:

- Run the project OpenCode capability/config check (`make opencode-check`) after
  `.opencode/**` edits.
- Use focused text searches to verify new routing language is not contradictory
  with existing supervisor, AGENTS, and skills.
- For CI workflow edits, validate YAML shape and run focused review of changed
  commands; full CI remains the authoritative integration gate.
- Because this is prompt/config/workflow work, local validation should focus on
  config wiring and diff review rather than application test suites unless code
  or build behavior changes require broader validation.

## Acceptance Criteria

- The strict supervisor remains available and remains the default for high-risk
  development and final integration.
- A new fast primary agent exists with clear permissions, escalation rules, and
  clean-design guardrails.
- Small fast-mode edits still require implementer -> reviewer before completion.
- Reviewer prompts/checklists explicitly block patchy conditionals, silent
  failures, misplaced ownership, and spaghetti-design risks.
- Existing strict flows are faster where possible without removing safety gates
  from high-risk work.
- CI changes reduce obvious latency sources without reducing required coverage
  for PR/merge-queue correctness.
