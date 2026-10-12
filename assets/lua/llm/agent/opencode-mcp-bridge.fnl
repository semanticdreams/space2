;; Agent OpenCode MCP bridge — preserves Space Agent permissions and delegates
;; loopback server/config lifecycle to the shared OpenCode MCP bridge core.

(local fs (require :fs))
(local Core (require :llm/opencode-mcp/bridge))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn normalize-root [path]
  "Normalize an optional root value; nil/empty roots mean that scope is not configured."
  (if (= path nil)
      nil
      (= path "")
      nil
      (if (and (> (string.len path) 1)
               (= (string.sub path -1) "/"))
          (string.sub path 1 (- (string.len path) 1))
          path)))

(fn join-pattern [root suffix]
  (local normalized-root (normalize-root root))
  (assert normalized-root "join-pattern requires a root")
  (if (= (string.sub suffix 1 1) "/")
      (.. normalized-root suffix)
      (.. normalized-root "/" suffix)))

(fn space-owned-roots [opts data-dir]
  "Derive optional bounded roots from explicit Space-owned runtime paths."
  (local space-data-dir (normalize-root opts.space-data-dir))
  (local space-cache-dir (normalize-root opts.space-cache-dir))
  (var code-dir (normalize-root opts.code-dir))
  (when (and (= code-dir nil) space-data-dir)
    (set code-dir (normalize-root (fs.join-path space-data-dir "code"))))
  (var artifact-root (normalize-root opts.artifact-root))
  (when (and (= artifact-root nil) space-data-dir)
    (set artifact-root (normalize-root (fs.join-path space-data-dir "agent-artifacts"))))
  (local allowed [])
  (when space-data-dir
    (table.insert allowed (join-pattern space-data-dir "agent-sessions/**"))
    (table.insert allowed (join-pattern space-data-dir "agent-opencode/**"))
    (table.insert allowed (join-pattern space-data-dir "agent-approvals/**")))
  (when artifact-root
    (table.insert allowed (join-pattern artifact-root "**")))
  (when code-dir
    (table.insert allowed (join-pattern code-dir "**")))
  (when space-cache-dir
    (table.insert allowed (join-pattern space-cache-dir "log/**")))
  {:allowed-patterns allowed
   :artifact-root artifact-root})

(fn secret-deny-patterns [allowed-patterns]
  (local patterns [])
  (each [_ allowed-pattern (ipairs allowed-patterns)]
    (each [_ marker (ipairs ["auth" "token" "secret" "credential" "keyring"])]
      (local immediate-pattern (string.gsub allowed-pattern "%*%*$" (.. "*" marker "*")))
      (local nested-pattern (string.gsub allowed-pattern "/%*%*$" (.. "/**/*" marker "*")))
      (table.insert patterns immediate-pattern)
      (table.insert patterns nested-pattern)))
  patterns)

(fn bounded-permission-map [allowed-patterns]
  (local permissions {"*" "deny"})
  (each [_ pattern (ipairs allowed-patterns)]
    (tset permissions pattern "allow"))
  (each [_ pattern (ipairs (secret-deny-patterns allowed-patterns))]
    (tset permissions pattern "deny"))
  permissions)

(fn native-tool-permissions [allowed-patterns]
  (local bounded (bounded-permission-map allowed-patterns))
  {:invalid "deny"
   :read bounded
   :write "deny"
   :edit "deny"
   :grep bounded
   :glob bounded
   :list bounded
   :bash "deny"
   :task "deny"
   :external_directory bounded
   :todowrite "deny"
   :webfetch "deny"
   :websearch "deny"
   :lsp "deny"
   :skill "deny"
   :question "deny"})

(fn refresh-opencode-provider! [providers bridge]
  "Refresh bridge config and replace the provider stored in a provider table."
  (assert providers "refresh-opencode-provider! requires providers")
  (assert bridge "refresh-opencode-provider! requires bridge")
  (local old-provider providers.opencode)
  (when old-provider
    (tset providers :opencode nil)
    (when old-provider.close
      (old-provider.close)))
  (bridge:refresh-config!)
  (local factory (or (. providers :opencode-factory)
                     (error "refresh-opencode-provider! requires providers.opencode-factory")))
  (local provider (factory))
  (when (not provider)
    (error "refresh-opencode-provider! factory returned nil"))
  (tset providers :opencode provider)
  provider)

(fn start-core! [bridge]
  (bridge:start))

(fn AgentOpencodeMcpBridge [opts]
  (local tools (or opts.tools (error "AgentOpencodeMcpBridge requires :tools")))
  (local data-dir (or opts.data-dir (error "AgentOpencodeMcpBridge requires :data-dir")))
  (local host (or opts.host "127.0.0.1"))
  (local http-server-factory opts.http-server-factory)
  (local mcp-server-factory opts.mcp-server-factory)

  (var core nil)
  (var started? false)
  (var allowed-roots [])
  (var artifact-root nil)

  (fn permissions []
    (native-tool-permissions allowed-roots))

  (fn status-extra []
    {:artifact-root artifact-root
     :allowed-roots allowed-roots})

  (fn build-core []
    (Core.OpencodeMcpBridge
      {:name "AgentOpencodeMcpBridge"
       :tools tools
       :data-dir data-dir
       :config-dir-name "opencode-mcp-config"
       :mcp-key "space"
       :permissions permissions
        :host host
        :http-server-factory http-server-factory
        :mcp-server-factory mcp-server-factory
        :config-extra opts.config-extra
        :status-extra status-extra}))

  (fn start [self]
    (when started?
      (error "AgentOpencodeMcpBridge already started"))
    (local roots (space-owned-roots opts data-dir))
    (set allowed-roots roots.allowed-patterns)
    (set artifact-root roots.artifact-root)
    (when artifact-root
      (ensure-dir! artifact-root))
    (set core (build-core))
    (local (ok result) (pcall start-core! core))
    (when (not ok)
      (set core nil)
      (set started? false)
      (set allowed-roots [])
      (set artifact-root nil)
      (error result))
    (set started? true)
    self)

  (fn stop [self]
    (when started?
      (core:stop))
    (set started? false)
    self)

  (fn opencode-env [self]
    (when (not started?)
      (error "AgentOpencodeMcpBridge must be started before building OpenCode env"))
    (core:opencode-env))

  (fn refresh-config! [self]
    (when (not started?)
      (error "AgentOpencodeMcpBridge must be started before refreshing OpenCode config"))
    (core:refresh-config!))

  (fn current-config-path [self]
    (and core (core:config-path)))

  (fn status [self]
    (if core
        (core:status)
        {:started? false
         :host host
         :port nil
         :url nil
         :config-root nil
         :config-path nil
         :artifact-root artifact-root
         :allowed-roots allowed-roots}))

  {:start start
   :stop stop
   :opencode-env opencode-env
   :refresh-config! refresh-config!
   :config-path current-config-path
   :status status})

{:AgentOpencodeMcpBridge AgentOpencodeMcpBridge
 :refresh-opencode-provider! refresh-opencode-provider!}
