;; External Unit MCP bridge — owns the loopback MCP HTTP server and isolated
;; OpenCode config for external unit development sessions.  This is a separate
;; bridge from `llm/agent/opencode-mcp-bridge.fnl` and must not import or
;; mutate the internal agent bridge.

(local Core (require :llm/opencode-mcp/bridge))

(local native-tool-permissions
  {:invalid "deny"
   :read "deny"
   :write "deny"
   :edit "deny"
   :grep "deny"
   :glob "deny"
   :list "deny"
   :bash "deny"
   :task "deny"
   :external_directory "deny"
   :todowrite "deny"
   :webfetch "deny"
   :websearch "deny"
   :lsp "deny"
   :skill "deny"
   :question "deny"})

(fn ExternalUnitMcpBridge [opts]
  (local tools (or opts.tools (error "ExternalUnitMcpBridge requires :tools")))
  (local data-dir (or opts.data-dir (error "ExternalUnitMcpBridge requires :data-dir")))
  (Core.OpencodeMcpBridge
    {:name "ExternalUnitMcpBridge"
     :tools tools
     :data-dir data-dir
     :config-dir-name "external-unit-opencode-config"
     :mcp-key "space-unit-dev"
     :permissions native-tool-permissions
     :host (or opts.host "127.0.0.1")
     :http-server-factory opts.http-server-factory
     :mcp-server-factory opts.mcp-server-factory}))

{:ExternalUnitMcpBridge ExternalUnitMcpBridge}
