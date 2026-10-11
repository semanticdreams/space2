;; Loopback MCP bridge for read-only Fennel validation tools. Generates an
;; isolated OpenCode config under the provided data dir only.

(local Core (require :llm/opencode-mcp/bridge))

(local native-tool-permissions
  {:invalid "deny"
   :read "allow"
   :write "deny"
   :edit "deny"
   :grep "allow"
   :glob "allow"
   :list "allow"
   :bash "deny"
   :task "deny"
   :external_directory "deny"
   :todowrite "deny"
   :webfetch "deny"
   :websearch "deny"
   :lsp "deny"
   :skill "deny"
   :question "deny"})

(fn FennelValidationMcpBridge [opts]
  (local tools (or opts.tools (error "FennelValidationMcpBridge requires :tools")))
  (local data-dir (or opts.data-dir (error "FennelValidationMcpBridge requires :data-dir")))
  (Core.OpencodeMcpBridge
    {:name "FennelValidationMcpBridge"
     :tools tools
     :data-dir data-dir
     :config-dir-name "fennel-validation-opencode-config"
     :mcp-key "space-fennel-validation"
     :permissions native-tool-permissions
     :host (or opts.host "127.0.0.1")
     :http-server-factory opts.http-server-factory
     :mcp-server-factory opts.mcp-server-factory}))

{:FennelValidationMcpBridge FennelValidationMcpBridge}
