---
type: dev-note
tags:
  - note
---

# LLM Systems

Space has several LLM-related integration surfaces. They share some concepts
but are intentionally separate in code, persistence, safety policy, and runtime
ownership. This note is a map for developers deciding which surface they are
touching.

## Direct provider conversations

Direct chat uses the conversation store and the direct provider registry:

```text
LlmChatView or graph LLM node
  -> llm/conversations/store.fnl
  -> llm/conversations/requests.fnl
  -> llm/conversations/providers.fnl
  -> OpenAI or ZAI conversation adapter
  -> low-level provider client
```

Relevant files include `assets/lua/llm-chat-view.fnl`,
`assets/lua/graph/nodes/llm*.fnl`, `assets/lua/llm/conversations/*.fnl`,
`assets/lua/llm/conversations/providers/openai.fnl`,
`assets/lua/llm/conversations/providers/zai.fnl`, and the lower-level clients in
`assets/lua/llm/providers/openai.fnl` and `assets/lua/llm/providers/zai.fnl`.

The current direct provider registry supports OpenAI and ZAI only. OpenCode and
Codex integrations are not registered as normal direct conversation providers.

Conversation state is stored under the app user-data directory in:

- `llm/conversations`
- `llm/messages`
- `llm/links/conversation-items`

Requests can store assistant messages, tool calls, and tool results, then run an
optional follow-up loop when tool output must be sent back to the model.

## Direct provider behavior

OpenAI direct chat uses `POST /responses` through
`llm/providers/openai.fnl`. It defaults to `gpt-4o-mini`, contains handling for
GPT-5.2 reasoning/text response shapes, rejects streaming requests, and adds the
`OpenAI-Beta: tools=v1` header when tools are present.

ZAI direct chat uses `/api/paas/v4/chat/completions` through
`llm/providers/zai.fnl`. The supported model is `glm-4.7`, streaming is rejected,
and tool definitions are sent only when explicitly passed.

## Direct LLM tools

Direct chat tools live in `assets/lua/llm/tools/`:

- `list-dir`
- `read-file`
- `write-file`
- `delete-file`
- `apply-patch`
- `bash`
- `edit-file`

These modules convert Space-side functions into OpenAI-style function tool
definitions for direct provider requests. They are separate from the Space Agent
tool surface and do not imply the same preset resolution or approval flow.

## OpenCode SDK integration

The OpenCode SDK wrapper lives under `assets/lua/llm/providers/opencode*.fnl`.
It starts `opencode serve`, talks to OpenCode REST endpoints, and subscribes to
OpenCode SSE events. This SDK is used by the Space Agent runtime, but it is not
listed in `llm/conversations/providers.fnl` and should not be treated as a
drop-in provider for direct chat.

## Space Agent runtime

The in-app Space Agent is bootstrapped from `assets/lua/main.fnl`. Startup wires
the MCP tool registry, preset manager/adapters, `AgentApprovals`,
`AgentToolSurface`, `AgentMcpSync`, `AgentOpencodeMcpBridge`, the OpenCode
provider factory, `SpaceAgent`, and `WorkflowAgentRunner`.

At runtime, Space Agent sends prompts to OpenCode sessions and audits returned
messages and tool events. It launches OpenCode with an isolated generated
`XDG_CONFIG_HOME` that points OpenCode at Space's internal MCP bridge instead of
mutating a developer's global OpenCode configuration.

Agent tools are preset-driven:

```text
llm/presets/*
  -> tool adapters
  -> AgentToolSurface
  -> approval-gated MCP definitions
  -> MCP ToolRegistry
  -> AgentOpencodeMcpBridge
  -> OpenCode session
```

Risk levels include `normal`, `filesystem-read`, `filesystem-write`,
`destructive`, and `shell`. Tools that require approval use the Space approval
tool `space_agent_request_tool_approval`.

## Workflow-backed agent sessions

Current agent sessions are backed by workflows rather than only by the older
`llm/agent/session.fnl` module. The relevant workflow files include
`assets/lua/workflows/store.fnl`, `assets/lua/workflows/runner.fnl`,
`assets/lua/workflows/code-executor.fnl`, and the agent workflow modules under
`assets/lua/llm/agent/workflow-*.fnl`.

The agent workflow template is `wf-agent-session-v1`; its chat step is
`step-agent-chat`. The step waits for `agent-user-input` and resumes via
`runtime.run-agent-turn`.

Workflow graph integration lives in
`assets/lua/graph/extensions/builtins/workflows.fnl`,
`assets/lua/graph/nodes/workflow*.fnl`, and
`assets/lua/graph/nodes/agent-session.fnl`. These nodes inspect workflow and
agent-session state; they are not the same persistence layer as direct LLM
conversations.

## Codex CLI integration

Codex support lives under `assets/lua/llm/providers/codex*.fnl`. It wraps
`codex exec --experimental-json`, parses JSON lines, supports starting and
resuming threads, polls the streamed child process, and exposes options for
images, output schemas, sandboxing, network access, web search, and approvals.

Codex is isolated from both the direct conversation provider registry and the
OpenCode-backed Space Agent runtime. See [Codex SDK For Fennel](./codex-sdk-fennel)
for the design note.

## External MCP bridges

Space also ships standalone MCP bridges for external tools:

- Fennel validation: `assets/lua/llm/fennel-validation/*` and
  `assets/lua/tools/fennel-validation-mcp-server.fnl` expose read-only
  validation tools.
- External unit MCP: `assets/lua/llm/external-unit-mcp/*` and
  `assets/lua/tools/external-unit-mcp-server.fnl` expose unit list, inspect,
  read, patch, create, test, reload, log, and snapshot operations.

These bridges are separate from the internal Space Agent MCP bridge. They use
their own entrypoints and isolated OpenCode configuration data rather than the
in-app agent bootstrap. See [External Unit MCP](./external-unit-mcp) for the
external unit bridge.

## Repo-local OpenCode automation

Files under `.opencode/` and scripts such as `scripts/opencode_*` are developer
automation for working on this repository. They define repository-local agents,
skills, and wrappers used by development workflows. They are not Space runtime
configuration for the in-app Space Agent, and they should not be documented as
user-facing app behavior.

## Interoperation and known gaps

- Direct chat and Space Agent are parallel systems. Direct chat goes through the
  conversation store and direct OpenAI/ZAI providers; Space Agent goes through
  workflow-backed OpenCode sessions and MCP.
- Direct LLM tools and approval-gated agent tools are separate tool surfaces.
  Sharing behavior between them requires explicit adapter work.
- OpenCode is an SDK/runtime dependency for Space Agent, not a direct
  `llm/conversations` provider today.
- Codex is a separate CLI wrapper and does not currently share persistence or
  session routing with direct chat or Space Agent.
- Persistence is split between direct LLM store data, workflow run data, and
  OpenCode session data.
- Streaming support differs by surface: direct OpenAI/ZAI adapters reject
  streaming, OpenCode uses SSE, and Codex exposes JSONL process events.
- Safety and model configuration are fragmented across provider adapters,
  direct tools, presets, approvals, OpenCode configuration, and Codex options.

## See also

- [Graph LLM Strategy](./graph-llm)
- [Agent Presets](./agent-presets)
- [Codex SDK For Fennel](./codex-sdk-fennel)
- [External Unit MCP](./external-unit-mcp)
