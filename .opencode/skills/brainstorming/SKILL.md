---
name: brainstorming
description: "Use before full creative feature work, architectural changes, ambiguous changes, broad refactors, and high-risk work. Not required for read-only audits or supervisor-classified tiny changes that still route through implementer -> reviewer -> pass."
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design and proceed unless a blocking ambiguity remains.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action for normal full-flow work until the design has been captured in a committed, self-reviewed spec and the implementation plan has been captured in a committed, self-reviewed plan. Stop for the user only on unresolved ambiguity, explicit user-requested checkpoints, permission prompts, or blockers; brainstorming remains mandatory before full creative feature work, architectural changes, ambiguous changes, broad refactors, and high-risk work.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Full-flow projects go through this process. A todo list, a single-function utility, a config change — all of them need this when they are creative, architectural, ambiguous, broad, high-risk, or not explicitly classified for a lower-ceremony path. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but for normal full-flow work you MUST present it, commit a self-reviewed spec, and self-transition to implementation planning.

## Low-Risk Exclusions

Brainstorming is not required for read-only audits where the user requests no
repository mutation. Brainstorming is also not required for a tiny change path
that the supervisor has explicitly classified as eligible and that still routes
every mutation through `implementer` -> `reviewer` -> pass. Any uncertainty
about whether the work is low-risk, local, or complete as one focused change
escalates back to brainstorming, preserving the committed spec/plan hard gate
for normal full-flow work.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits. For broad codebase searches, dispatch the `explorer` subagent to gather information without polluting your context.
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and your recommendation. When evaluating whether an approach fits existing architecture, dispatch the `planner` subagent with a focused question about the relevant abstractions.
4. **Present design direction** — summarize the chosen direction and proceed unless a blocking ambiguity remains
5. **Write design doc** — save to `docs/specs/YYYY-MM-DD-<topic>-design.md`
6. **Commit the spec** — `git add docs/specs/<filename>.md && git commit -m "docs: add design spec for <topic>"`. This is a hard gate: do not proceed to self-review or any further step until the spec file is committed. The finishing skill will reject a dirty tree, and subagent-driven-development only tracks its own task commits — no one else is responsible for committing coordination artifacts.
7. **Spec self-review** — quick inline check for placeholders, contradictions, ambiguity, scope. If the review surfaces changes, amend the commit.
8. **Automatic transition** — invoke the writing-plans skill from the committed spec to create a detailed implementation plan; do not wait for user review unless the user explicitly requested a checkpoint or the spec has unresolved ambiguity.

**The terminal state is a complete, committed, self-reviewed implementation plan produced by the writing-plans skill.** Proceed to implementation only after the plan is committed and self-reviewed. Pause for the user only on unresolved ambiguity, explicit user-requested checkpoints, permission prompts, or blockers.

## The Process

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems, flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message — if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
- YAGNI ruthlessly — remove unnecessary features from every approach and design

**Presenting the design:**

- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Present each section and continue automatically unless a blocking ambiguity remains or a stop condition (unresolved ambiguity, explicit user-requested checkpoint, permission prompt, or blocker) applies
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Can someone understand what a unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work.
- Smaller, well-bounded units are also easier for you to work with — you reason better about code you can hold in context at once, and your edits are more reliable when files are focused.

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work (e.g., a file that's grown too large, unclear boundaries, tangled responsibilities), include targeted improvements as part of the design — the way a good developer improves code they're working in.
- Don't propose unrelated refactoring. Stay focused on what serves the current goal.

## After the Design

**Documentation:**

- Write the validated design (spec) to `docs/specs/YYYY-MM-DD-<topic>-design.md`
  - (User preferences for spec location override this default)
- Commit the design document to git

**Spec Self-Review:**
After writing the spec document, look at it with fresh eyes:

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition?
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.

Fix any issues inline. No need to re-review — just fix and move on.

**Automatic Progression:**
After the spec review loop passes, proceed automatically to the writing-plans skill without waiting for user review. Only pause for the user if there is unresolved ambiguity, the user explicitly requested a review checkpoint, the action requires a permission prompt, or a genuine blocker is encountered.
