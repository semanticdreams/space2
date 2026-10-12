# Weekly Agent Workflow Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a weekly Orca/OpenCode automation that analyzes sanitized Space OpenCode sessions across project worktrees, implements high-confidence agent workflow improvements through review gates, and publishes a docs report and guarded auto-merge PR.

**Architecture:** Add a deterministic Python analyzer that reads only whitelisted OpenCode data sources and emits sanitized JSON evidence. Add a repository-local OpenCode skill plus supervisor routing/permissions modeled after the daily devlog automation. Add docs for Orca setup and a stable report location.

**Tech Stack:** Python 3 standard library (`argparse`, `sqlite3`, `json`, `pathlib`, `re`, `subprocess`), pytest, Markdown/VitePress docs, OpenCode project agents/skills in `.opencode/**`, GitHub CLI (`gh`), Space `make` validation.

## Global Constraints

- Recommended Orca prompt: `Run the weekly agent workflow automation`.
- Analyze OpenCode sessions for this project across all worktrees, not unrelated projects.
- External reads are narrow: `~/.local/share/opencode/opencode.db*`, `~/.local/share/opencode/tool-output/**`, `~/.local/share/opencode/log/**`, and the configured Space worktree parent, defaulting to `~/space/**`.
- Do not read `auth.json`; do not query credential/account/auth/token/secret tables.
- Agents consume sanitized analyzer artifacts, not raw OpenCode database rows, raw logs, or raw tool-output dumps.
- Reports may include short sanitized excerpts when they materially justify a finding.
- High-confidence improvements may touch any file category, but only through implementer → reviewer → validation gates.
- `.opencode/**`, source, tests, docs, and constraints all go through implementer → reviewer → pass unless they are supervisor-allowlisted coordination artifacts.
- Automation branch format: `automation/weekly-agent-workflow/YYYY-Www`.
- Never push directly to `main`.
- Create a PR targeting `main` and auto-merge only after branch protection and required checks are verified.
- Default full-suite command: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- For Fennel-facing changes, run the validation ladder from `AGENTS.md`: `make fennel-check`, constraints, focused tests, then broader suite.
- OpenCode config, agent, and skill changes are startup-loaded; restart OpenCode after merge before relying on the new automation.

---

## File Structure Map

- `scripts/weekly_agent_workflow_analyzer.py` — deterministic sanitized analyzer CLI and importable analysis functions.
- `scripts/tests/test_weekly_agent_workflow_analyzer.py` — pytest fixtures for redaction, project worktree discovery, schema drift, and aggregation.
- `docs/dev/features/weekly-agent-workflow-automation.md` — Orca setup, access model, branch policy, privacy model, and restart note.
- `docs/dev/reports/agent-workflow/index.md` — stable weekly report landing page and report contract.
- `docs/dev/index.md` — links setup page and report index.
- `docs/dev/features/index.md` — links setup page from feature index.
- `.opencode/skills/weekly-agent-workflow-automation/SKILL.md` — scheduled automation workflow skill.
- `.opencode/agents/supervisor.md` — trigger routing, external read permissions, and guarded weekly branch/PR command permissions.

---

### Task 1: Sanitized Weekly Analyzer

**Files:**
- Create: `scripts/weekly_agent_workflow_analyzer.py`
- Test: `scripts/tests/test_weekly_agent_workflow_analyzer.py`

**Interfaces:**
- Consumes: repo root, OpenCode data directory, Space worktree parent, optional prior report directory.
- Produces:
  - `AnalyzerConfig(repo_root: Path, opencode_data_dir: Path, worktree_parent: Path, output: Path | None = None, report_dir: Path | None = None, since_days: int = 7, max_excerpt_chars: int = 500, now: datetime | None = None)`
  - `redact_text(text: str) -> tuple[str, list[str]]`
  - `bounded_excerpt(text: str, max_chars: int) -> str`
  - `discover_worktrees(repo_root: Path, worktree_parent: Path) -> list[dict[str, str]]`
  - `analyze(config: AnalyzerConfig) -> dict[str, Any]`
  - `main(argv: Sequence[str] | None = None) -> int`
  - JSON with `schema_version`, `sources`, `redaction`, `worktrees`, `sessions`, `findings`, and `prior_reports`.

- [ ] **Step 1: Write failing analyzer tests**

  In `scripts/tests/test_weekly_agent_workflow_analyzer.py`, insert `scripts/` onto `sys.path`, import `weekly_agent_workflow_analyzer as analyzer`, and define fixture helpers:

  ```python
  def create_fixture_space_worktrees(tmp_path: Path) -> tuple[Path, Path]:
      parent = tmp_path / "space-parent"
      repo = parent / "space"
      sibling = parent / "space-feature"
      unrelated = parent / "other"
      for path in (repo, sibling, unrelated):
          path.mkdir(parents=True)
          subprocess.run(["git", "init"], cwd=path, check=True, stdout=subprocess.DEVNULL)
      for path in (repo, sibling):
          subprocess.run(["git", "remote", "add", "origin", "git@example.com:semanticdreams/spacecore.git"], cwd=path, check=True)
      subprocess.run(["git", "remote", "add", "origin", "git@example.com:someone/other.git"], cwd=unrelated, check=True)
      return repo, parent

  def create_fixture_db(data_dir: Path, repo: Path, *, repeated_failures: bool = False) -> None:
      conn = sqlite3.connect(data_dir / "opencode.db")
      conn.execute("CREATE TABLE project (id text primary key, worktree text, name text, time_created integer, time_updated integer)")
      conn.execute("CREATE TABLE session (id text primary key, project_id text, directory text, title text, agent text, model text, cost real, tokens_input integer, tokens_output integer, tokens_reasoning integer, time_created integer, time_updated integer)")
      conn.execute("CREATE TABLE message (id text primary key, session_id text, time_created integer, time_updated integer, data text)")
      conn.execute("CREATE TABLE part (id text primary key, message_id text, session_id text, time_created integer, time_updated integer, data text)")
      conn.execute("CREATE TABLE account (id text, secret text)")
      conn.execute("INSERT INTO account VALUES ('acct', 'sk-live-sensitive')")
      conn.execute("INSERT INTO project VALUES ('space-project', ?, 'space', 1, 1)", (str(repo),))
      conn.execute("INSERT INTO project VALUES ('other-project', ?, 'other', 1, 1)", (str(repo.parent / "other"),))
      conn.execute("INSERT INTO session VALUES ('project-session-1', 'space-project', ?, 'Project session', 'implementer', '{\"id\":\"deepseek\"}', 1.2, 100, 20, 5, 1785500000000, 1785500100000)", (str(repo),))
      conn.execute("INSERT INTO session VALUES ('unrelated-session', 'other-project', ?, 'Other session', 'supervisor', '{}', 0, 1, 1, 0, 1785500000000, 1785500100000)", (str(repo.parent / "other"),))
      texts = ["make test failed with FAIL"]
      if repeated_failures:
          texts = ["make test failed", "fennel-check error", "constraints FAIL"]
      for index, text in enumerate(texts):
          message_id = f"msg-{index}"
          part_id = f"part-{index}"
          conn.execute("INSERT INTO message VALUES (?, 'project-session-1', 1785500000000, 1785500000000, ?)", (message_id, json.dumps({"role": "assistant"})))
          conn.execute("INSERT INTO part VALUES (?, ?, 'project-session-1', 1785500000000, 1785500000000, ?)", (part_id, message_id, json.dumps({"type": "text", "text": text})))
      conn.commit()
      conn.close()
  ```

  Add tests for:
  - secret redaction of bearer tokens, `sk-proj-`, passwords, and private keys;
  - matching-origin worktree discovery that excludes unrelated repos;
  - excluding unrelated sessions and avoiding sensitive table content;
  - bounded, redacted tool-output excerpts;
  - `repeated-validation-failure` aggregation;
  - schema drift raising `SchemaDriftError`.

- [ ] **Step 2: Run tests and verify red**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  ```

  Expected: FAIL because `weekly_agent_workflow_analyzer` does not exist.

- [ ] **Step 3: Implement analyzer skeleton**

  Create `scripts/weekly_agent_workflow_analyzer.py` with `AnalyzerError`, `SchemaDriftError`, `AnalyzerConfig`, and the public functions listed above. Open SQLite read-only with:

  ```python
  conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5.0)
  conn.execute("PRAGMA query_only = ON")
  ```

  Install a SQLite authorizer that denies table names containing `auth`, `account`, `credential`, `token`, or `secret`.

- [ ] **Step 4: Implement worktree and session filtering**

  `discover_worktrees` must compare `git remote get-url origin` for `repo_root` and each direct child under `worktree_parent`. Include only matching origins, always include `repo_root` when it is a git worktree, and return labels from directory names. `analyze` must include only sessions whose `directory`, `project.worktree`, or workspace/project path maps to an included worktree.

- [ ] **Step 5: Implement redaction, excerpts, and findings**

  Redact authorization headers, bearer tokens, assignments whose keys include `api_key`, `apikey`, `token`, `secret`, `password`, `authorization`, or `x-api-key`, common token prefixes (`sk-`, `sk-proj-`, `ghp_`, `github_pat_`, `xoxb-`, `AKIA`, `ASIA`), and PEM private-key blocks. Read at most 16 KiB from each matching `tool-output`/`log` file and emit at most three excerpts per session. Hash raw session ids with SHA-256 and expose only 12 hex characters as `session_ref`.

  First-version findings:
  - `repeated-validation-failure` from repeated `make test`, `pytest`, `ctest`, `fennel-check`, `constraints`, `failed`, `FAIL`, or `error` evidence;
  - `review-fix-loop-churn` from reviewer finding plus follow-up fix language;
  - `permission-friction` from permission prompts or denied tool messages;
  - `skill-routing-gap` from missing/wrong skill language.

- [ ] **Step 6: Implement prior report parsing and CLI**

  Default report dir: `repo_root / "docs/dev/reports/agent-workflow"`. Parse Markdown headings and lines containing `finding id`, `Finding ID`, `deferred`, or `re-check` into sanitized compact strings.

  CLI:

  ```bash
  python3 scripts/weekly_agent_workflow_analyzer.py \
    --repo-root . \
    --opencode-data-dir ~/.local/share/opencode \
    --worktree-parent ~/space \
    --since-days 7 \
    --output .superpowers/sdd/weekly-agent-workflow/evidence.json
  ```

  Exit codes: `0` success, `2` missing input path, `3` unreadable DB/schema drift, `4` sanitizer leak.

- [ ] **Step 7: Run focused validation**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  python3 scripts/weekly_agent_workflow_analyzer.py --help
  ```

  Expected: tests pass and help lists all CLI flags.

- [ ] **Step 8: Commit analyzer**

  ```bash
  git add scripts/weekly_agent_workflow_analyzer.py scripts/tests/test_weekly_agent_workflow_analyzer.py
  git commit -m "feat(scripts): add sanitized weekly agent workflow analyzer"
  ```

---

### Task 2: Report and Orca Setup Documentation

**Files:**
- Create: `docs/dev/features/weekly-agent-workflow-automation.md`
- Create: `docs/dev/reports/agent-workflow/index.md`
- Modify: `docs/dev/index.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: analyzer output contract from Task 1.
- Produces: docs consumed by users and by the weekly skill report contract.

- [ ] **Step 1: Create setup page**

  Create `docs/dev/features/weekly-agent-workflow-automation.md` with sections: `Orca Setup`, `Required Local Access`, `Branch and Pull Request Policy`, `Evidence and Privacy`, and `Weekly Reports`. Include this exact prompt block:

  ```text
  Run the weekly agent workflow automation
  ```

  State that OpenCode must be restarted after changes to `.opencode/opencode.json`, `.opencode/agents/**`, or `.opencode/skills/**`. Document default access paths as `~/.local/share/opencode/opencode.db*`, `~/.local/share/opencode/tool-output/**`, `~/.local/share/opencode/log/**`, and `~/space/**` for sibling worktree discovery. State that `auth.json`, credential tables, account tables, and unrelated projects are excluded.

- [ ] **Step 2: Create report index**

  Create `docs/dev/reports/agent-workflow/index.md` with the report contract:

  ```markdown
  # Agent Workflow Reports

  Weekly agent workflow automation reports contain sanitized evidence only.

  Each dated report includes:

  1. date/range analyzed;
  2. data sources and redaction status;
  3. summary of sessions, agents, costs/tokens when available;
  4. top findings with sanitized evidence;
  5. changes implemented in this run;
  6. recommendations deferred and why;
  7. validation performed;
  8. risks/noise observed;
  9. signals to re-check next week.
  ```

- [ ] **Step 3: Link docs pages**

  In `docs/dev/index.md`, add:
  - `- [Agent Workflow Reports](/dev/reports/agent-workflow/)` under `## Work Tracking`.
  - `- [Weekly Agent Workflow Automation](/dev/features/weekly-agent-workflow-automation)` under `## Feature Pages` near the agent entries.

  In `docs/dev/features/index.md`, add:
  - `- [Weekly Agent Workflow Automation](./weekly-agent-workflow-automation)`.

- [ ] **Step 4: Validate and commit docs**

  Run:

  ```bash
  cd docs && npm run docs:build
  ```

  Then commit:

  ```bash
  git add docs/dev/features/weekly-agent-workflow-automation.md docs/dev/reports/agent-workflow/index.md docs/dev/index.md docs/dev/features/index.md
  git commit -m "docs: document weekly agent workflow automation"
  ```

---

### Task 3: Weekly OpenCode Skill

**Files:**
- Create: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`

**Interfaces:**
- Consumes: analyzer CLI from Task 1 and docs contract from Task 2.
- Produces: OpenCode skill `weekly-agent-workflow-automation`.

- [ ] **Step 1: Run writing-skills baseline where practical**

  Before creating the skill, run or document a fresh-context baseline with:

  ```text
  A scheduled Orca run says: "Run the weekly agent workflow automation". You are in the Space repo. Explain what you would do next. Assume there is a daily devlog automation skill but no weekly skill.
  ```

  Record whether the baseline reads raw OpenCode data directly, skips implementer/reviewer gates, lacks branch/PR guardrails, or treats the prompt as generic exploration.

- [ ] **Step 2: Create skill frontmatter and body**

  Create `.opencode/skills/weekly-agent-workflow-automation/SKILL.md` with:

  ```markdown
  ---
  name: weekly-agent-workflow-automation
  description: Use when a scheduled Orca/OpenCode run or user prompt asks to run weekly agent workflow automation, audit recent OpenCode sessions, improve agent workflows, or publish a weekly agent workflow report
  ---
  ```

  Include sections: `Overview`, `Preconditions`, `Workflow`, `Improvement Selection`, `Report Contract`, `Validation`, `Commit, Push, and PR`, `Fail-Closed Cases`, `Red Flags`.

- [ ] **Step 3: Add workflow contract**

  The `Workflow` section must require: clean checkout, fetch `origin/main`, branch `automation/weekly-agent-workflow/YYYY-Www`, analyzer command with `--worktree-parent ~/space`, fail closed on analyzer/redaction failure, read prior reports, choose high-confidence improvements, dispatch implementer and reviewer, use `writing-skills` for skill edits, debug validation failures via `systematic-debugging`, inspect final diff, commit reviewed changes, push branch, create PR, verify branch protection/checks, then enable auto-merge only when safe.

- [ ] **Step 4: Add report template and PR safety text**

  Include a report template with headings: `Range Analyzed`, `Data Sources and Redaction`, `Session Summary`, `Top Findings`, `Implemented Changes`, `Deferred Recommendations`, `Validation`, `Risks and Noise`, `Signals To Re-check Next Week`.

  State that the automation must run `gh auth status`, verify protection with `gh api repos/<owner>/<repo>/branches/main/protection`, verify required checks, use `gh pr merge --auto --squash automation/weekly-agent-workflow/YYYY-Www` only after those checks, and never push directly to `origin/main`.

- [ ] **Step 5: Validate and commit skill**

  Run:

  ```bash
  python3 - <<'PY'
  from pathlib import Path
  text = Path('.opencode/skills/weekly-agent-workflow-automation/SKILL.md').read_text(encoding='utf-8')
  frontmatter = text.split('---', 2)[1]
  required = [
      'name: weekly-agent-workflow-automation',
      'description: Use when ',
      '# Weekly Agent Workflow Automation',
      '## Workflow',
      'implementer → reviewer → pass',
      'automation/weekly-agent-workflow/YYYY-Www',
      'gh api repos/<owner>/<repo>/branches/main/protection',
  ]
  assert text.startswith('---\n')
  assert len(frontmatter) <= 1024
  assert not [item for item in required if item not in text]
  print('weekly skill validation passed')
  PY
  ```

  Then commit:

  ```bash
  git add .opencode/skills/weekly-agent-workflow-automation/SKILL.md
  git commit -m "feat(opencode): add weekly agent workflow automation skill"
  ```

---

### Task 4: Supervisor Routing, Permissions, and PR Rules

**Files:**
- Modify: `.opencode/agents/supervisor.md`

**Interfaces:**
- Consumes: skill name from Task 3.
- Produces: supervisor routing, external-directory permissions, and guarded weekly branch/PR command permissions.

- [ ] **Step 1: Update external-directory permissions**

  Replace `external_directory: ask` with this ordered map:

  ```yaml
  external_directory:
    "*": ask
    "~/.local/share/opencode/opencode.db*": allow
    "~/.local/share/opencode/tool-output/**": allow
    "~/.local/share/opencode/log/**": allow
    "~/space/**": allow
  ```

  The broad `*` rule must remain before the narrow allows because OpenCode evaluates the last matching permission rule.

- [ ] **Step 2: Add weekly bash allow rules**

  Add these rules near the existing daily automation rules and after `gh *: deny` where relevant:

  ```yaml
  "git push origin HEAD:refs/heads/automation/weekly-agent-workflow/????-W??": allow
  "gh repo view --json owner,name --jq *": allow
  "gh api repos/*/*/branches/main/protection*": allow
  "gh pr create --base main --head automation/weekly-agent-workflow/????-W?? --fill": allow
  "gh pr view automation/weekly-agent-workflow/????-W??*": allow
  "gh pr checks automation/weekly-agent-workflow/????-W?? --watch": allow
  "gh pr merge --auto --squash automation/weekly-agent-workflow/????-W??": allow
  ```

  Do not add any allow rule for `git push origin main`.

- [ ] **Step 3: Add skill routing**

  Under `### Space Project Skill Routing`, add:

  ```markdown
  - If a request says "Run the weekly agent workflow automation" or otherwise asks
    for scheduled/weekly agent workflow automation, invoke
    `weekly-agent-workflow-automation` before dispatching implementation work.
  ```

- [ ] **Step 4: Validate and commit supervisor changes**

  Run:

  ```bash
  python3 - <<'PY'
  from pathlib import Path
  text = Path('.opencode/agents/supervisor.md').read_text(encoding='utf-8')
  required = [
      '"~/.local/share/opencode/opencode.db*": allow',
      '"~/.local/share/opencode/tool-output/**": allow',
      '"~/.local/share/opencode/log/**": allow',
      '"~/space/**": allow',
      '"git push origin HEAD:refs/heads/automation/weekly-agent-workflow/????-W??": allow',
      '"gh api repos/*/*/branches/main/protection*": allow',
      '`weekly-agent-workflow-automation` before dispatching implementation work.',
  ]
  assert not [item for item in required if item not in text]
  assert '"git push origin main": allow' not in text
  assert '"gh *": deny' in text
  print('supervisor weekly automation validation passed')
  PY
  python3 -m json.tool .opencode/opencode.json >/tmp/opencode-json-validation.out
  ```

  Then commit:

  ```bash
  git add .opencode/agents/supervisor.md
  git commit -m "chore(opencode): route weekly automation and allow guarded PR workflow"
  ```

---

### Task 5: End-to-End Validation and Integration Readiness

**Files:**
- Validate all files from Tasks 1–4.
- Modify only if validation reveals a reviewed fix is necessary.

**Interfaces:**
- Consumes: analyzer, docs, skill, and supervisor changes.
- Produces: validation evidence and any reviewed validation fixes.

- [ ] **Step 1: Run focused validations**

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  python3 scripts/weekly_agent_workflow_analyzer.py --help
  python3 -m json.tool .opencode/opencode.json >/tmp/opencode-json-validation.out
  ```

- [ ] **Step 2: Run docs build**

  ```bash
  cd docs && npm run docs:build
  ```

- [ ] **Step 3: Run full suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 4: Inspect scope and secrets**

  ```bash
  git status --short
  git diff -- . ':!docs/plans/2026-07-31-weekly-agent-workflow-automation.md'
  git diff --stat HEAD~5..HEAD
  git diff HEAD~5..HEAD | rg -n -i 'api[_-]?key|secret|token|password|-----begin|private key|/home/|/Users/|file:///' || true
  ```

  Any matches must be generic redaction examples or intentional `~` paths, not real secrets or private absolute paths.

- [ ] **Step 5: Commit validation fixes if needed**

  If validation required changes, commit them with:

  ```bash
  git add scripts/weekly_agent_workflow_analyzer.py scripts/tests/test_weekly_agent_workflow_analyzer.py docs/dev/features/weekly-agent-workflow-automation.md docs/dev/reports/agent-workflow/index.md docs/dev/index.md docs/dev/features/index.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md .opencode/agents/supervisor.md
  git commit -m "test(opencode): validate weekly automation workflow"
  ```

  If no files changed, do not create an empty commit.

---

## Acceptance Criteria

- `Run the weekly agent workflow automation` routes supervisor to `weekly-agent-workflow-automation`.
- Analyzer reads OpenCode DB read-only and emits compact sanitized JSON.
- Analyzer excludes unrelated project sessions under the worktree parent.
- Analyzer avoids `auth.json` and credential/account/auth/token/secret tables.
- Analyzer tests cover redaction, bounded excerpts, worktree detection, unrelated session exclusion, repeated failure aggregation, and schema drift fail-closed behavior.
- Weekly skill requires clean checkout, branch from `origin/main`, analyzer execution, prior report review, implementer → reviewer gates, validation, report generation, PR creation, and guarded auto-merge.
- Supervisor permissions allow only the external reads and branch/PR commands needed for unattended automation.
- Docs page explains Orca setup and includes the exact prompt.
- Weekly report index documents the report contract.
- Branch auto-merge is attempted only after branch protection and required checks are verified.
- Restart note is present for OpenCode config/agent/skill changes.

## Validation Ladder

1. Focused:
   - `python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q`
   - `python3 scripts/weekly_agent_workflow_analyzer.py --help`
   - Python validation snippets for `.opencode/agents/supervisor.md` and `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`
   - `python3 -m json.tool .opencode/opencode.json >/tmp/opencode-json-validation.out`
2. Docs:
   - `cd docs && npm run docs:build`
3. Full suite:
   - `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`
4. Risk checks:
   - final diff has no unjustified files;
   - no `git push origin main` allow rule was introduced;
   - no raw secret or private absolute home path was committed;
   - OpenCode restart note is present.

## Explicitly Out of Scope

- Analyzing unrelated projects' OpenCode sessions.
- Reading OpenCode credentials, auth tokens, account state, or `auth.json`.
- Directly pushing to `main`.
- Bypassing implementer/reviewer discipline because the run is automated.
- Guaranteeing every recommendation is implemented in the same weekly run.
- Creating dashboards, external services, or non-repo analytics storage.
- Changing global `~/.config/opencode/**`.
- Adding third-party Python dependencies.
