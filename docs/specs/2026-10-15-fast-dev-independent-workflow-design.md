# Independent fast-dev workflow

## Intent

Make interactive Space development efficient: the user-selected `fast-dev`
primary owns edits and local commits directly, with comprehensive review and
integration deferred until the user requests wrap-up. Environment isolation,
not narrow tool permissions or operational worker agents, bounds its authority.

## Design

Use a short primary prompt, an on-demand `fast-dev-wrap-up` skill, and one
`fast-dev-reviewer` subagent for independent whole-branch review. Exploration
may be delegated when useful; implementation, debugging, Git, and GitHub work
are direct. No mandatory micro-design, spec, plan, implementation delegation,
per-change review, or handoff to another primary agent exists in this workflow.

Alternatives rejected: putting all integration details in the always-loaded
prompt wastes interactive context; adapting the strict capability system adds
unnecessary coupling and ceremony.

### Interactive lifecycle

- Before mutation, use a dedicated `fast-dev/<topic>` branch. New work starts
  from freshly fetched `origin/main`; continue an existing branch only when
  it clearly belongs to the current work and has not already been integrated.
- Do not develop on local `main`, overwrite branches, silently carry unrelated
  commits, discard user work, or automatically stash ambiguous dirty changes.
  Ask a bounded question when ownership is unclear.
- Edit directly and make small coherent local checkpoints with short,
  intent-focused subjects. No verbose body or approval gate is required.
- Run focused validation when useful. Preserve clean design, explicit errors,
  and Space technical guidance. No planning/process skill is automatically
  required for ordinary edits, debugging, commits, or task completion.
- A commit request is local only. Do not push or open a PR until explicit
  wrap-up/integration authorization.

### Wrap-up lifecycle

The on-demand skill commits intended pending work, fetches `origin/main`, and
safely merges that base when needed. It runs risk-appropriate checks for the
complete change and requests one independent review of every accumulated
commit plus the final diff, using recorded base/head SHAs and user intent.
The reviewer inspects Git directly and returns concrete findings and coverage
gaps; missing process artifacts are not findings.

Fast-dev fixes findings and failing checks directly, commits fixes, and
self-reviews/revalidates changes. There is no mandatory independent re-review
per fix. Unresolved material findings or required test failures prevent PR
integration. Reconcile pre-PR base changes and inspect/test resulting changes.

Use raw `git` and `gh` to push only the topic branch, create/reuse a PR targeting
`main`, enable auto-merge, and poll PR/merge-group checks until actually merged.
Verify repository/PR identity and required merge-queue/test protection. Do not
refresh the PR branch solely because main advances after queue entry. Diagnose
actionable failures directly; report concrete human-owned blockers rather than
treat pending checks as completion. Finally fetch `origin/main` and verify the
PR merge commit is its ancestor. Preserve the branch/worktree; no cleanup is
required. No direct main push, rebase, or force-push.

## Configuration and policy

Give only the fast-dev primary broad agent-local permissions (`permission:
allow`). The final reviewer is observational: allow repository/Git inspection,
deny editing, and instruct it not to mutate or operate GitHub. This is an
operating contract, not a command-by-command security sandbox.

Add an identity-scoped `AGENTS.md` exception that overrides inherited process
requirements, including those imported by domain skills. Keep technical Space
rules and validation commands. Keep other primary/subagent permissions, the
default agent, shared skills, and capability wrappers unchanged. Update stale
descriptions and canonical docs without making fast-dev aware of other primary
agents. Teach the permission checker the exact intentional broad-primary and
observational-reviewer profiles; do not broaden unrelated agents.

## Validation and acceptance

- Replace obsolete prompt assertions; cover broad permissions only for the
  canonical fast-dev primary, retained unrelated role boundaries, dedicated
  branches, local-only checkpoints, explicit wrap-up activation, full review,
  direct fixes, and merged-in-origin/main completion evidence.
- Exercise baseline and updated prompt scenarios without publishing demo PRs.
- Run focused Python policy tests, `make opencode-check`, docs automation
  checks, and `git diff --check`. No engine build is justified by this surface.
- Validate supported OpenCode configuration forms; do not claim restarted
  runtime/global configuration verification without evidence.
- Document that OpenCode must be restarted to load these changes.

## Scope

Agent definitions, one new wrap-up skill, scoped repository guidance, canonical
workflow docs, and policy checks/tests only. No engine/Fennel changes, wrapper
branch-policy changes, global permission grants, default-agent change, or
general agent-evaluation framework.
