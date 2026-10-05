---
name: systematic-debugging
description: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes
---

# Systematic Debugging

## Overview

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## When to Use

Use for ANY technical issue:
- Test failures
- Bugs in production
- Unexpected behavior
- Performance problems
- Build failures
- Integration issues

**Use this ESPECIALLY when:**
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- Previous fix didn't work
- You don't fully understand the issue

**Don't skip when:**
- Issue seems simple (simple bugs have root causes too)
- You're in a hurry (rushing guarantees rework)
- Manager wants it fixed NOW (systematic is faster than thrashing)

## Quick Debugging Triage

For failures that appear obvious and localized, a brief read-only triage pass is
allowed before entering the full four phases. This pass may only reproduce the
failure and inspect existing evidence: read error output, rerun the exact
failing command when safe, inspect relevant files, compare recent diffs, and
state one localized hypothesis. It may not edit code, tests, configuration,
workflows, prompts, or repository files.

Escalate immediately into the full four phases when any of these occur:

- root cause is unclear;
- reproduction is not consistent;
- the first localized hypothesis fails;
- the surface is high-risk;
- the fix would touch multiple subsystems;
- any code/config/test/workflow edit is needed.

The iron law still applies: no repository fix without root cause investigation
and no unreviewed fixes. Quick triage can shorten obvious evidence gathering;
it cannot skip diagnosis, `implementer` routing, reviewer verification, or the
normal failure-recovery gates.

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read Error Messages Carefully**
   - Don't skip past errors or warnings
   - They often contain the exact solution
   - Read stack traces completely
   - Note line numbers, file paths, error codes

2. **Reproduce Consistently**
   - Can you trigger it reliably?
   - What are the exact steps?
   - Does it happen every time?
   - If not reproducible → gather more data, don't guess

3. **Check Recent Changes**
   - What changed that could cause this?
   - Git diff, recent commits
   - New dependencies, config changes
   - Environmental differences

4. **Gather Evidence in Multi-Component Systems**

   **WHEN system has multiple components (CI → build → signing, API → service → database):**

   **BEFORE proposing fixes, add diagnostic instrumentation:**
   ```
   For EACH component boundary:
     - Log what data enters component
     - Log what data exits component
     - Verify environment/config propagation
     - Check state at each layer

   Run once to gather evidence showing WHERE it breaks
   THEN analyze evidence to identify failing component
   THEN investigate that specific component
   ```

   **Example (multi-layer system):**
   ```bash
   # Layer 1: Workflow
   echo "=== Secrets available in workflow: ==="
   echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"

   # Layer 2: Build script
   echo "=== Env vars in build script: ==="
   env | grep IDENTITY || echo "IDENTITY not in environment"

   # Layer 3: Signing script
   echo "=== Keychain state: ==="
   security list-keychains
   security find-identity -v

   # Layer 4: Actual signing
   codesign --sign "$IDENTITY" --verbose=4 "$APP"
   ```

   **This reveals:** Which layer fails (secrets → workflow ✓, workflow → build ✗)

5. **Trace Data Flow**

   **WHEN error is deep in call stack:**

   See `root-cause-tracing.md` in this directory for the complete backward tracing technique.

   **Quick version:**
   - Where does bad value originate?
   - What called this with bad value?
   - Keep tracing up until you find the source
   - Fix at source, not at symptom

### Phase 2: Pattern Analysis

**Find the pattern before fixing:**

1. **Find Working Examples**
   - Locate similar working code in same codebase
   - What works that's similar to what's broken?

2. **Compare Against References**
   - If implementing pattern, read reference implementation COMPLETELY
   - Don't skim - read every line
   - Understand the pattern fully before applying

3. **Identify Differences**
   - What's different between working and broken?
   - List every difference, however small
   - Don't assume "that can't matter"

4. **Understand Dependencies**
   - What other components does this need?
   - What settings, config, environment?
   - What assumptions does it make?

### Phase 3: Hypothesis and Testing

**Scientific method:**

1. **Form Single Hypothesis**
   - State clearly: "I think X is the root cause because Y"
   - Write it down
   - Be specific, not vague

2. **Test Minimally (no code edits)**
   - Test hypotheses with read-only inspection, shell commands, or targeted
     logging — never by editing production or test source files.
   - One variable at a time
   - Don't test multiple hypotheses at once
   - If a code change is required to test a hypothesis: capture it as a
     proposed experiment in the evidence brief and send to `debug-advisor`
     for judgment before touching code.

3. **Verify Before Continuing**
   - Did it work? Yes → Phase 3.5
   - Didn't work? Form NEW hypothesis
   - DON'T add more fixes on top

4. **When You Don't Know**
   - Say "I don't understand X"
   - Don't pretend to know
   - Ask for help
   - Research more

### Phase 3.5: Diagnostic Advisor Gate

**Before implementing any fix, validate the diagnosis with a smarter model.**

0. **Ensure the artifact directory exists** (keeps debug files out of git):
   ```
   .opencode/skills/github-workflow-debug/scripts/ci-artifact-dir.sh
   ```

1. **Write a debug evidence brief** (to `.superpowers/sdd/debug-evidence-brief.md`):
   - Observed bug and reproduction steps
   - Relevant error messages, logs, stack traces
   - Code paths inspected (file:line references)
   - Hypotheses tested and rejected (with reasons)
   - Current suspected root cause with supporting evidence
   - Proposed minimal fix (scope, files, approach)
   - Exact validation command that would confirm the fix

2. **Dispatch the `debug-advisor`** (gpt-5.5 high). Provide only the evidence
   brief path and relevant source-file paths. The advisor is read-only — it
   judges the diagnosis, it does not re-investigate.

3. The advisor returns a JSON verdict:

   - **confirmed** → proceed to Phase 4.1 (Prepare). The evidence brief
     becomes the basis for the debug-fix brief.
   - **needs_more_evidence** → run the specific commands the advisor
     requests, inspect the files it names, append findings to the evidence
     brief, and re-dispatch the advisor.
   - **wrong_root_cause** → return to Phase 1. The advisor's rationale
     and suggested direction guide the new investigation.
   - **too_broad_needs_plan** → convert findings into a plan and invoke
     **subagent-driven-development**.
   - **requires_human** → present the advisor's rationale to the human.

4. After failed fix attempts (Phase 4.6, <3 attempts): append new evidence
   from the failed attempt to the brief and re-dispatch the advisor before
   starting a new implementation round. The advisor re-evaluates with the
   additional data.

### Phase 4: Implementation

**Do not implement fixes yourself.** The supervisor's job is investigation and
coordination — dispatch the `implementer` for code changes and the `reviewer`
for independent verification.

#### 4.1. Prepare

The `debug-advisor` has confirmed the diagnosis in Phase 3.5.

1. **Define the reproduction in the brief.** The supervisor adds to the
   debug-fix brief: the exact reproduction command, expected vs actual
   output, and what a failing test must cover. The supervisor does NOT
   create the test file — the implementer does that as its first
   implementation step and reports RED evidence.

2. **Write a debug-fix brief** (to `.superpowers/sdd/debug-fix-brief.md`).
   Base it on the evidence brief from Phase 3.5, now including the failing
   test. Include:
   - Bug description and reproduction steps
   - Root cause (from Phase 1-3 investigation, confirmed by advisor)
   - Expected fix (narrow, single-purpose)
   - Files likely to change
   - Validation command (exact test or reproduce command to verify the fix)

3. **Assess scope.** If the fix would touch more than 3 files, introduce new
   abstractions, or require a design change → convert the root-cause findings
   into a small plan and invoke **subagent-driven-development** instead of
   continuing here.

#### 4.2. Dispatch the Implementer

Record `BASE=$(git rev-parse HEAD)`.

Dispatch the **implementer** subagent with:
- The debug-fix brief path
- A report-file path: `.superpowers/sdd/debug-fix-report.md`
- Context: "This is a focused bug fix. Implement only what the brief
  specifies. Create the failing test first — the brief defines the
  reproduction you must capture. Report RED/GREEN evidence in your
  report file. Return only status summary."

The implementer reports one of: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT,
BLOCKED. Handle as in the SDD task loop (NEEDS_CONTEXT → provide missing
info and re-dispatch; BLOCKED → assess blocker; DONE_WITH_CONCERNS →
note concerns and proceed to review).

#### 4.3. Review

When the implementer returns DONE, generate a review package:
```
.opencode/skills/subagent-driven-development/scripts/review-package \
  /dev/null "$BASE" HEAD .superpowers/sdd/debug-review-pack.diff
```

Dispatch the **reviewer** in FULL REVIEW MODE:
```
You are reviewing a debug fix using FULL REVIEW MODE.

Task brief (debug-fix brief): .superpowers/sdd/debug-fix-brief.md
Implementer report: .superpowers/sdd/debug-fix-report.md
Review package (diff): .superpowers/sdd/debug-review-pack.diff

Global constraints:
- Fix the root cause identified in the brief, not the symptom
- No bundled refactoring or "while I'm here" changes
- The fix must be covered by the failing test case from the brief
```

#### 4.4. Fix Loop

If review status is `candidates_found` with Critical or Important findings:

- **Round 1-2:** Resume the implementer with the findings verbatim. It is
  being resumed — it knows the code. Record `FIX_BASE`, generate a fix-diff
  review package:
  ```
  .opencode/skills/subagent-driven-development/scripts/review-package \
    /dev/null "$FIX_BASE" HEAD .superpowers/sdd/debug-fix-review-pack.diff
  ```
  Dispatch reviewer in TARGETED VERIFICATION MODE:
  ```
  You are verifying fixes for a debug fix using TARGETED VERIFICATION MODE.

  Task brief (debug-fix brief): .superpowers/sdd/debug-fix-brief.md
  Implementer report (fix reports appended): .superpowers/sdd/debug-fix-report.md
  Findings under verification: [list findings verbatim — copied from the full review]
  Review package (fix diff): .superpowers/sdd/debug-fix-review-pack.diff
  ```

- **Round 3 (breaker):** Dispatch the **adjudicator** subagent with the
  open findings and the debug-fix brief. The adjudicator returns
  accept/park/escalate decisions. Parked findings are noted in the final
  report. Escalated findings go to the human.

If the reviewer returns `requires_human` at any point, present the findings
to the human.

#### 4.5. Verify Fix

Review complete and clean? Final checks:
- The failing test from the brief passes
- No other tests broken
- The fix addresses the root cause, not the symptom
- The implementer's report is trustworthy (reviewer confirmed)

#### 4.6. If Fix Doesn't Work

If the fix fails validation despite clean review:
- **Attempts < 3:** Return to Phase 1 with new information.
- **Attempts ≥ 3:** STOP. The failure may be architectural. Discuss with
  the human before attempting Fix #4. Consider converting findings into an
  SDD plan for broader refactoring.

**Do not implement fixes yourself at any point in Phase 4.** The supervisor
investigates, writes briefs, and coordinates — `implementer` edits code.

## Red Flags - STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Pattern says X but I'll adapt it differently"
- "Here are the main problems: [lists fixes without investigation]"
- Proposing solutions before tracing data flow
- **"One more fix attempt" (when already tried 2+)**
- **Each fix reveals new problem in different place**
- **"I'll just fix this one myself"**

**ALL of these mean: STOP. Return to Phase 1.**

**If 3+ fixes failed:** Question the architecture (see Phase 4.6)

## your human partner's Signals You're Doing It Wrong

**Watch for these redirections:**
- "Is that not happening?" - You assumed without verifying
- "Will it show us...?" - You should have added evidence gathering
- "Stop guessing" - You're proposing fixes without understanding
- "Ultra-think this" - Question fundamentals, not just symptoms
- "We're stuck?" (frustrated) - Your approach isn't working

**When you see these:** STOP. Return to Phase 1.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write test after confirming fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question pattern, don't fix again. |
| "I'll just fix this one myself" | Controller fixes skip review. Dispatch the implementer — the fix loop catches regressions. |
| "The fix is too small to review" | Unreviewed fixes are how regressions land. Every fix gets reviewed. |

## Quick Reference

| Phase | Key Activities | Success Criteria |
|-------|---------------|------------------|
| **1. Root Cause** | Read errors, reproduce, check changes, gather evidence | Understand WHAT and WHY |
| **2. Pattern** | Find working examples, compare | Identify differences |
| **3. Hypothesis** | Form theory, test minimally | Confirmed or new hypothesis |
| **3.5 Advisor Gate** | Write evidence brief, dispatch debug-advisor | Diagnosis confirmed by smarter model |
| **4. Implementation** | Dispatch implementer, review, fix loop, verify | Bug resolved, review clean, tests pass |

## When Process Reveals "No Root Cause"

If systematic investigation reveals issue is truly environmental, timing-dependent, or external:

1. You've completed the process
2. Document what you investigated
3. Implement appropriate handling (retry, timeout, error message)
4. Add monitoring/logging for future investigation

**But:** 95% of "no root cause" cases are incomplete investigation.

## Supporting Techniques

These techniques are part of systematic debugging:

- **Root cause tracing** — Trace bugs backward through the call stack to find the original trigger. Start at the crash site; for each frame, ask "what called this with a bad value?" and keep tracing up until you find the source.
- **Defense in depth** — After finding the root cause, add validation at multiple layers: validate inputs at boundaries, add assertions at intermediate layers, and make the crash site fail informatively.
- **Condition-based waiting** — Replace arbitrary timeouts (`sleep 500`, `setTimeout(fn, 1000)`) with polling loops that check a concrete condition and fail with a clear timeout message if the condition is never met.
