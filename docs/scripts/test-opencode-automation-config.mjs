import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(__dirname, '..', '..')

let skillContent = ''
let supervisorContent = ''
let finishingContent = ''
let weeklySkillContent = ''
let notesContent = ''
let workflowDebugContent = ''
let testWorkflowContent = ''
let agentsContent = ''
let opencodeWorkflowContent = ''
let githubOperatorContent = ''
let prOperatorContent = ''
let fastDevContent = ''
let fastDevReviewerContent = ''
let fastDevWrapUpContent = ''

async function loadFiles() {
    if (skillContent) return
    skillContent = await readFile(join(repoRoot, '.opencode', 'skills', 'daily-devlog-automation', 'SKILL.md'), 'utf8')
    supervisorContent = await readFile(join(repoRoot, '.opencode', 'agents', 'supervisor.md'), 'utf8')
    finishingContent = await readFile(join(repoRoot, '.opencode', 'skills', 'finishing-a-development-branch', 'SKILL.md'), 'utf8')
    weeklySkillContent = await readFile(join(repoRoot, '.opencode', 'skills', 'weekly-agent-workflow-automation', 'SKILL.md'), 'utf8')
    workflowDebugContent = await readFile(join(repoRoot, '.opencode', 'skills', 'github-workflow-debug', 'SKILL.md'), 'utf8')
    testWorkflowContent = await readFile(join(repoRoot, '.github', 'workflows', 'test.yml'), 'utf8')
    agentsContent = await readFile(join(repoRoot, 'AGENTS.md'), 'utf8')
    opencodeWorkflowContent = await readFile(join(repoRoot, 'docs', 'dev', 'features', 'opencode-agent-workflow.md'), 'utf8')
    githubOperatorContent = await readFile(join(repoRoot, '.opencode', 'agents', 'github-operator.md'), 'utf8')
    prOperatorContent = await readFile(join(repoRoot, 'scripts', 'opencode_pr_operator.py'), 'utf8')
    fastDevContent = await readFile(join(repoRoot, '.opencode', 'agents', 'fast-dev.md'), 'utf8')
    fastDevReviewerContent = await readFile(join(repoRoot, '.opencode', 'agents', 'fast-dev-reviewer.md'), 'utf8')
    fastDevWrapUpContent = await readFile(join(repoRoot, '.opencode', 'skills', 'fast-dev-wrap-up', 'SKILL.md'), 'utf8')
    try {
        notesContent = await readFile(join(repoRoot, 'docs', 'dev', 'notes', 'daily-devlog-automation.md'), 'utf8')
    } catch { /* optional */ }
}

test('daily devlog skill mentions GitHub rulesets or effective branch rules, not only classic protection', async () => {
    await loadFiles()
    const hasRulesets = skillContent.includes('ruleset') ||
        skillContent.includes('rules/branches') ||
        skillContent.includes('effective branch rule') ||
        skillContent.includes('effective rules')
    assert.ok(hasRulesets,
        'SKILL.md should mention rulesets or effective branch rules, not only classic protection')
})

test('daily devlog delegates effective branch rule verification to the guarded protection capability', async () => {
    await loadFiles()
    assert.match(skillContent, /Dispatch `github-operator` to verify branch protection rules and required status checks/)
    assert.ok(githubOperatorContent.includes('"python3 scripts/opencode_pr_operator.py check-main-protection --repo-root .": allow'))
    assert.ok(prOperatorContent.includes('f"repos/{SPACE_REPO}/rules/branches/main"'),
        'the delegated protection wrapper must inspect effective branch rules')
})

test('daily devlog skill requires verifying required status checks before auto-merge', async () => {
    await loadFiles()
    assert.ok(
        // Must mention required status checks in context of verification/auto-merge
        /required.status.check/i.test(skillContent),
        'SKILL.md should require verifying required status checks before auto-merge'
    )
})

test('daily devlog skill requires verifying pull-request protection before auto-merge', async () => {
    await loadFiles()
    // Must mention pull-request rules / PR protection in context of verification
    const hasPrProtection = /pull.request.*(?:protect|rule|required|verified)|pull.request/i.test(skillContent) &&
        /auto.merge/i.test(skillContent)
    assert.ok(hasPrProtection,
        'SKILL.md should require verifying pull-request protection before auto-merge')
})

test('daily devlog skill does not hard-code --squash and instead selects merge method from rules', async () => {
    await loadFiles()
    // The skill must NOT require --squash as the only option
    const hasHardcodedSquash = /gh pr merge --auto --squash automation\/daily-devlog/.test(skillContent)
    // The skill must mention using the merge method from verified rules
    const hasMergeMethodFromRules = /merge.method/i.test(skillContent) ||
        /allowed.merge/i.test(skillContent) ||
        /--merge automation\/daily-devlog/.test(skillContent) ||
        /merge.*allowed/i.test(skillContent)
    assert.ok(!hasHardcodedSquash,
        'SKILL.md must NOT hard-code --squash for daily auto-merge')
    assert.ok(hasMergeMethodFromRules,
        'SKILL.md should say to use the merge method allowed by verified branch rules')
})

test('weekly agent workflow skill does not hard-code --squash and instead selects merge method from rules', async () => {
    await loadFiles()
    // The skill must NOT require --squash as the only option
    const hasHardcodedSquash = /gh pr merge --auto --squash automation\/weekly-agent-workflow/.test(weeklySkillContent)
    // The skill must mention using the merge method from verified rules
    const hasMergeMethodFromRules = /merge.method/i.test(weeklySkillContent) ||
        /allowed.merge/i.test(weeklySkillContent) ||
        /--merge automation\/weekly-agent-workflow/.test(weeklySkillContent) ||
        /merge.*allowed/i.test(weeklySkillContent)
    assert.ok(!hasHardcodedSquash,
        'SKILL.md must NOT hard-code --squash for weekly auto-merge')
    assert.ok(hasMergeMethodFromRules,
        'SKILL.md should say to use the merge method allowed by verified branch rules')
})

test('supervisor denies direct protection API access and delegates protection checks', async () => {
    await loadFiles()
    assert.ok(supervisorContent.includes('"gh api repos/*/*/rules/branches/main*": deny'))
    assert.match(supervisorContent.replace(/\s+/g, ' '), /Dispatch `github-operator` for GitHub authentication checks, target-branch protection checks/)
})

test('daily auto-merge stays with the guarded GitHub capability', async () => {
    await loadFiles()
    assert.match(skillContent, /enable auto-merge, and poll for merge only through `github-operator`/)
    assert.ok(githubOperatorContent.includes('"python3 scripts/opencode_pr_operator.py enable-auto-merge-current --repo-root .": allow'))
    assert.match(skillContent, /require a rebase-only merge method, do not enable auto-merge automatically/,
        'rebase-only rules must remain a human-owned decision')
})

test('weekly auto-merge stays with the guarded GitHub capability', async () => {
    await loadFiles()
    assert.match(weeklySkillContent, /Before auto-merge, dispatch `github-operator` for authentication, protection checks, and merge queue proof/)
    assert.match(weeklySkillContent, /require a rebase-only merge method, do not enable auto-merge automatically/)
    assert.ok(supervisorContent.includes('"gh *": deny'),
        'automation must not depend on direct broad GitHub authority')
})

test('guarded auto-merge requires protection proof instead of raw merge-method grants', async () => {
    await loadFiles()
    assert.doesNotMatch(supervisorContent, /"gh pr merge[^\n]*": allow/)
    assert.match(prOperatorContent, /if not has_test or not has_queue:\s+return human_decision/,
        'protection verification must fail closed unless both required test and queue are proven')
    assert.match(prOperatorContent, /protection = check_main_protection\(repo_root\)\s+if protection.get\("status"\) != "pass":\s+return human_decision/,
        'auto-merge must be gated on the protection result')
    assert.ok(prOperatorContent.includes('["gh", "pr", "merge", safe, "--auto", "--merge"]'),
        'the guarded wrapper, not the primary, owns the merge invocation')
})

test('daily devlog skill attributes work by origin/main landing date, not author date', async () => {
    await loadFiles()

    const oneLineSkill = skillContent.replace(/\s+/g, ' ')
    const rejectsAuthorDates = /(?:author|original commit|commit\/author) dates?.{0,220}(?:must not|never|do not|not decide|not cause|skipped|backdated)|(?:must not|never|do not).{0,220}(?:author|original commit|commit\/author) dates?/i

    assert.match(oneLineSkill, /origin\/main/i,
        'SKILL.md should name origin/main as the source for recent work')
    assert.match(oneLineSkill, /source of truth/i,
        'SKILL.md should call origin/main the source of truth')
    assert.match(oneLineSkill, /mainline|first-parent/i,
        'SKILL.md should require mainline or first-parent inspection')
    assert.match(oneLineSkill, /merge commits|PR merges|landed ranges/i,
        'SKILL.md should mention merge commits, PR merges, or landed ranges')
    assert.match(oneLineSkill, /land(?:ed|ing)|merge(?:d|s)?/i,
        'SKILL.md should describe landed or merged work')
    assert.ok(rejectsAuthorDates.test(oneLineSkill),
        'SKILL.md should say author/original commit dates must not decide devlog eligibility')
    assert.doesNotMatch(skillContent,
        /Inspect recent journal entries, docs notes, plans\/specs, and commits since the latest journal entry or recent day boundary\./,
        'SKILL.md should not keep the ambiguous commits-since workflow wording')
})

test('daily devlog skill preserves one-paragraph inline-link and compression style policy', async () => {
    await loadFiles()

    const oneLineSkill = skillContent.replace(/\s+/g, ' ')

    assert.match(oneLineSkill, /single narrative paragraph|One short narrative paragraph/i,
        'SKILL.md should keep the one-paragraph journal contract')
    assert.match(oneLineSkill, /inline Markdown links/i,
        'SKILL.md should explicitly permit inline Markdown links')
    assert.match(oneLineSkill, /relevant docs, notes, plans, specs, or feature pages/i,
        'SKILL.md should limit inline links to relevant project context')
    assert.match(oneLineSkill, /forbid.{0,180}link lists/i,
        'SKILL.md should forbid separate link lists')
    assert.match(oneLineSkill, /compression\/style pass|compression pass/i,
        'SKILL.md should require a compression/style pass')
    assert.match(oneLineSkill, /denser/i,
        'SKILL.md should say compression makes prose denser')
    assert.match(oneLineSkill, /preserv.{0,160}(?:important context|main landed changes|why they matter)/i,
        'SKILL.md should say compression preserves important context')
})

test('daily devlog developer note documents landing-date and inline-link policies', async () => {
    await loadFiles()

    assert.ok(notesContent.length > 0,
        'daily devlog developer note should be present for human-facing policy')
    const oneLineNotes = notesContent.replace(/\s+/g, ' ')

    assert.match(oneLineNotes, /origin\/main/i,
        'developer note should name origin/main')
    assert.match(oneLineNotes, /land(?:ed|ing)|merge(?:d|s)?/i,
        'developer note should document landing or merge attribution')
    assert.match(oneLineNotes, /author|original commit/i,
        'developer note should say author/original commit dates do not drive attribution')
    assert.match(oneLineNotes, /inline Markdown links/i,
        'developer note should document inline Markdown links')
    assert.match(oneLineNotes, /link lists/i,
        'developer note should forbid separate link lists')
})

test('github workflow debug lands through a PR branch instead of local main', async () => {
    await loadFiles()

    const oneLineSkill = workflowDebugContent.replace(/\s+/g, ' ')

    assert.match(oneLineSkill, /final PR branch/i,
        'workflow-debug skill should name a final PR branch')
    assert.match(oneLineSkill, /origin\/main/i,
        'workflow-debug final PR branch should be created from origin/main')
    assert.match(oneLineSkill, /squash-merge/i,
        'workflow-debug skill should keep squash-merge landing semantics')
    assert.match(oneLineSkill, /remove.{0,160}temporary.{0,80}trigger/i,
        'workflow-debug skill should remove the temporary workflow trigger before final commit')
    assert.match(oneLineSkill, /staged review/i,
        'workflow-debug skill should require staged review')
    assert.match(oneLineSkill, /gh pr create --base main --head <final-pr-branch> --fill/i,
        'workflow-debug skill should create a PR with gh pr create')
    assert.match(oneLineSkill, /PR URL/i,
        'workflow-debug skill should return the PR URL')
    assert.match(oneLineSkill, /branch-protection incompatible/i,
        'workflow-debug skill should say direct main push is branch-protection incompatible')

    assert.doesNotMatch(workflowDebugContent, /## Final landing on main/,
        'workflow-debug skill must not title the landing path as local main')
    assert.doesNotMatch(oneLineSkill, /Check out `main`|Fast-forward `main`|Final commit on main|Ready to push|git checkout main|checkout main|check out main|commit (?:on|to|onto) (?:`?main`?|main)|squash[- ]merge[\s\S]*?(?:onto|into)\s+(?:`?main`?|main)|squash\s+(?:onto|into)\s+(?:`?main`?|main)/i,
        'workflow-debug skill must not reference local main checkout, commit-on-main, or ready-to-push-main output')
    assert.doesNotMatch(workflowDebugContent, /git push origin main/,
        'workflow-debug skill must not tell agents to push main directly')
})

test('strict workflow-debug integration delegates topic pushes and PRs and denies main push', async () => {
    await loadFiles()

    assert.ok(supervisorContent.includes('"git push origin HEAD:refs/heads/opencode/workflow-debug-pr/*": deny'))
    assert.ok(supervisorContent.includes('"git push origin main": deny'),
        'direct main push must be denied, not ask-gated')
    const oneLine = supervisorContent.replace(/\s+/g, ' ')
    assert.match(oneLine, /Dispatch `git-integrator`[\s\S]*pushing the current branch through `scripts\/opencode_git_integrate.py`/)
    assert.match(oneLine, /Dispatch `github-operator` for[\s\S]*PR creation/)
    assert.ok(githubOperatorContent.includes('"python3 scripts/opencode_pr_operator.py create-current --repo-root .": allow'))
    assert.ok(supervisorContent.includes('"gh *": deny'))
})

test('daily devlog skill preconditions mention installing locked docs dependencies when node_modules or vitepress is missing', async () => {
    await loadFiles()
    // Validation/preconditions area must mention npm ci for docs dependency install
    const oneLineSkill = skillContent.replace(/\s+/g, ' ')
    assert.match(oneLineSkill, /npm\s+ci/i,
        'SKILL.md should mention npm ci for installing locked docs dependencies')
    assert.ok(
        oneLineSkill.includes('node_modules') || oneLineSkill.includes('vitepress'),
        'SKILL.md should reference checking for docs/node_modules or vitepress'
    )
})

test('daily devlog developer note documents fresh-checkout docs dependency install before docs build', async () => {
    await loadFiles()
    assert.ok(notesContent.length > 0,
        'daily devlog developer note should be present for human-facing policy')
    const oneLineNotes = notesContent.replace(/\s+/g, ' ')
    assert.match(oneLineNotes, /npm\s+ci/i,
        'developer note should document npm ci for installing locked docs dependencies')
    assert.match(oneLineNotes, /npm run docs:build/i,
        'developer note should retain npm run docs:build in dependency flow')
})

test('required test workflow runs for merge queue merge_group events', async () => {
    await loadFiles()
    assert.match(testWorkflowContent, /^\s*merge_group:\s*$/m,
        'test.yml should include an on.merge_group trigger so required checks run for merge queue candidates')
})

test('daily devlog developer note documents Orca/OpenCode project-config caveat', async () => {
    await loadFiles()
    assert.ok(notesContent.length > 0,
        'daily devlog developer note should be present for human-facing policy')
    const oneLineNotes = notesContent.replace(/\s+/g, ' ')
    assert.match(oneLineNotes, /OPENCODE_DISABLE_PROJECT_CONFIG|project.config/i,
        'developer note should document OPENCODE_DISABLE_PROJECT_CONFIG or project-config caveat')
    assert.match(oneLineNotes, /synchroniz|sync.*(?:global|config)|restart/i,
        'developer note should mention syncing global config or restarting after .opencode changes')
})

test('repository policy requires agents to poll merge queue until PR merge', async () => {
    await loadFiles()
    const combined = `${agentsContent}\n${opencodeWorkflowContent}`
    const oneLine = combined.replace(/\s+/g, ' ')

    assert.match(oneLine, /poll.{0,160}(?:mergedAt|merged)/i,
        'policy should tell agents to poll until mergedAt or merged state')
    assert.match(combined, /gh pr view/i,
        'policy should document gh pr view for PR polling')
    assert.match(combined, /gh run list --workflow test\.yml --event merge_group/i,
        'policy should document merge_group run inspection')
    assert.match(oneLine, /do not update.{0,180}origin\/main.{0,5}advanced/i,
        'policy should keep the stale-branch update-loop prohibition')
    assert.doesNotMatch(oneLine, /Stop after successful merge-queue handoff/i,
        'policy should not treat merge-queue handoff as the terminal success state')
    assert.match(oneLine, /push.{0,160}requeue/i,
        'policy should require pushing the repaired branch before requeuing')
})

test('opencode workflows monitor queued PRs until merged', async () => {
    await loadFiles()
    const files = [
        ['supervisor', supervisorContent],
        ['finishing', finishingContent],
        ['daily', skillContent],
        ['weekly', weeklySkillContent],
    ]

    for (const [name, content] of files) {
        const oneLine = content.replace(/\s+/g, ' ')
        assert.match(oneLine, /poll.{0,180}(?:mergedAt|merged)/i,
            `${name} should poll until mergedAt or merged state`)
        assert.match(content, /`github-operator`/,
            `${name} should delegate GitHub polling`)
        assert.match(oneLine, /wrapper (?:actions|evidence)/i,
            `${name} should use guarded wrapper evidence rather than raw CLI authority`)
        assert.match(oneLine, /do not (?:safe-merge|update).{0,220}origin\/main advanced/i,
            `${name} should preserve stale-branch loop prohibition`)
        assert.doesNotMatch(oneLine, /Stop after successful merge-queue handoff/i,
            `${name} should not stop after queue handoff`)
        assert.match(oneLine, /closed[-\u2010\u2011\u2012\u2013\u2014]?unmerged/i,
            `${name} should list closed-unmerged PRs as an actionable blocker`)
        assert.match(oneLine, /queue timeout/i,
            `${name} should list queue timeouts as an actionable blocker`)
        assert.match(oneLine, /push.{0,80}requeue/i,
            `${name} should require push before requeue in the fix loop`)
    }
})

test('strict merge queue inspection is exposed only through guarded current-branch wrappers', async () => {
    await loadFiles()
    assert.ok(supervisorContent.includes('"gh *": deny'))
    assert.match(githubOperatorContent, /^    "\*": deny$/m)
    for (const command of ['view-current', 'poll-merge-queue-current']) {
        assert.ok(githubOperatorContent.includes(`"python3 scripts/opencode_pr_operator.py ${command} --repo-root .": allow`))
        assert.ok(supervisorContent.includes(`github-operator ${command}`))
    }
    assert.doesNotMatch(githubOperatorContent, /^    "gh[^\n]*": allow$/m)
})

test('guarded polling retains canonical PR fields and a fixed 100-second cadence', async () => {
    await loadFiles()
    assert.ok(prOperatorContent.includes('PR_VIEW_FIELDS = "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url"'))
    assert.ok(prOperatorContent.includes('["gh", "pr", "view", safe, "--json", PR_VIEW_FIELDS]'))
    assert.match(prOperatorContent, /^DEFAULT_POLL_INTERVAL_SECONDS = 100$/m)
    assert.ok(prOperatorContent.includes('poll_merge_queue(repo_root, safe, DEFAULT_POLL_TIMEOUT_SECONDS, DEFAULT_POLL_INTERVAL_SECONDS)'))
    assert.match(prOperatorContent, /if data.get\("mergedAt"\):\s+return success/)
    assert.match(prOperatorContent, /if data.get\("state"\) == "CLOSED":\s+return human_decision/)
})

test('fast-dev is direct and local-only until explicit wrap-up, without changing strict contracts', async () => {
    await loadFiles()
    assert.match(fastDevContent, /^mode: primary$/m)
    assert.match(fastDevContent, /^permission: allow$/m)
    const primary = fastDevContent.replace(/\s+/g, ' ')
    assert.match(primary, /fast-dev\/<topic>.*before edits/)
    assert.match(primary, /freshly fetched `origin\/main`/)
    assert.match(primary, /A commit request is local only/)
    assert.match(primary, /Only explicit user wrap-up\/integration authorization triggers `fast-dev-wrap-up`/)
    assert.doesNotMatch(fastDevContent, /supervisor|dispatch `implementer`|micro-design/i)
    assert.match(agentsContent, /For the user-selected `fast-dev` primary only/)
    assert.match(agentsContent, /override conflicting process rules below and those imported by domain skills/)
    assert.match(agentsContent, /Retain Space technical standards/)
    assert.match(supervisorContent, /^    "gh \*": deny$/m)
})

test('fast-dev wrap-up reviews the whole branch once and fixes findings directly', async () => {
    await loadFiles()
    const wrapUp = fastDevWrapUpContent.replace(/\s+/g, ' ')
    assert.match(wrapUp, /git log origin\/main\.\.HEAD/)
    assert.match(wrapUp, /git diff origin\/main\.\.\.HEAD/)
    assert.match(wrapUp, /base\/head SHAs/)
    assert.match(wrapUp, /one independent review from `fast-dev-reviewer` covering every accumulated commit and final diff/)
    assert.match(wrapUp, /Fix findings and failing checks directly/)
    assert.match(wrapUp, /commit fixes, self-review.*revalidate/)
    assert.match(wrapUp, /no mandatory independent re-review per fix/)
    assert.match(wrapUp, /Do not integrate with unresolved material findings or required validation failures/)
    assert.match(fastDevReviewerContent, /^  bash: allow$/m)
    assert.match(fastDevReviewerContent, /^  edit: deny$/m)
    assert.match(fastDevReviewerContent.replace(/\s+/g, ' '), /Do not run tests, builds, commits, GitHub commands/)
})

test('fast-dev wrap-up keeps protection, polling, and fetched-main completion proof', async () => {
    await loadFiles()
    const wrapUp = fastDevWrapUpContent.replace(/\s+/g, ' ')
    assert.match(wrapUp, /rules\/branches\/main/)
    assert.match(wrapUp, /require merge queue and required `test` protection for merge-group candidates/)
    assert.match(wrapUp, /gh pr create --base main --head <topic-branch>/)
    assert.match(wrapUp, /gh pr merge <pr> --auto/)
    assert.match(wrapUp, /100-second cadence/)
    assert.match(wrapUp, /gh pr view <pr> --json state,mergedAt,mergeCommit/)
    assert.match(wrapUp, /gh run list --workflow test.yml --event merge_group/)
    assert.match(wrapUp, /gh run watch <relevant-run-id> --exit-status --interval 100/)
    assert.match(wrapUp, /missing conclusions are not completion/)
    assert.match(wrapUp, /After queue entry, do not merge main solely because it advances/)
    assert.match(wrapUp, /Require PR `mergedAt` and `mergeCommit.oid`.*fresh `git fetch origin` and `git merge-base --is-ancestor <merge-sha> origin\/main`/)
    assert.match(wrapUp, /Preserve branch and worktree/)
})
