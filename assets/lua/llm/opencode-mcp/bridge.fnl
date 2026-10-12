;; Shared policy-neutral OpenCode MCP bridge core.

(local fs (require :fs))
(local JsonUtils (require :json-utils))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn remote-url [host port]
  (.. "http://" host ":" (tostring port) "/mcp"))

(fn config-path [config-root]
  (fs.join-path (fs.join-path config-root "opencode") "opencode.json"))

(fn resolve-permissions [permissions]
  (if (= (type permissions) "function")
      (permissions)
      permissions))

(fn table-value? [value]
  (= (type value) "table"))

(fn copy-table [input]
  (local source (if (= input nil) {} input))
  (assert (table-value? source) "copy-table requires a table or nil")
  (local result {})
  (each [k v (pairs source)]
    (tset result k (if (table-value? v) (copy-table v) v)))
  result)

(fn merge-tables [base overlay]
  (local overlay-table (if (= overlay nil) {} overlay))
  (assert (table-value? overlay-table) "merge-tables overlay must be a table or nil")
  (local result (copy-table base))
  (each [k v (pairs overlay-table)]
    (local existing (. result k))
    (tset result k
          (if (and (table-value? existing) (table-value? v))
              (merge-tables existing v)
              (if (table-value? v) (copy-table v) v))))
  result)

(fn resolve-config-extra [config-extra]
  (if (= (type config-extra) "function")
      (config-extra)
      config-extra))

(fn validate-config-extra! [extra]
  (when (not (table-value? extra))
    (error "OpenCode config extra must be a table or nil"))
  (when (not= (. extra :permission) nil)
    (error "OpenCode config extra cannot override bridge-owned permission config"))
  (when (not= (. extra :mcp) nil)
    (error "OpenCode config extra cannot override bridge-owned MCP config"))
  extra)

(fn write-opencode-config! [config-root mcp-key url permissions config-extra]
  (local opencode-dir (fs.join-path config-root "opencode"))
  (ensure-dir! opencode-dir)
  (local mcp {})
  (tset mcp mcp-key {:type "remote"
                      :url url
                      :enabled true})
  (local resolved-extra (resolve-config-extra config-extra))
  (local extra (if (= resolved-extra nil) {} resolved-extra))
  (validate-config-extra! extra)
  (local bridge-config {:permission (resolve-permissions permissions)
                        :mcp mcp})
  (JsonUtils.write-json!
    (config-path config-root)
    (merge-tables extra bridge-config)))

(fn merge-status [extras core]
  (local status {})
  (local extra-values (if (= extras nil) {} extras))
  (each [k v (pairs extra-values)]
    (tset status k v))
  (each [k v (pairs core)]
    (tset status k v))
  status)

(fn status-extras [status-extra]
  (if (= status-extra nil)
      {}
      (= (type status-extra) "function")
      (do
        (local result (status-extra))
        (if (= result nil) {} result))
      status-extra))

(fn default-http-server-factory []
  (local http-server-mod (require :http_server))
  (http-server-mod.HttpServer))

(fn cleanup-failed-start! [server]
  (when server
    (pcall (fn [] (server:stop)))))

(fn start-server-and-write-config! [server host name config-root mcp-key permissions config-extra]
  (local started-port (server:start host 0))
  (when (not (> started-port 0))
    (error (.. name " got invalid MCP port: " (tostring started-port))))
  (local current-url (remote-url host started-port))
  (write-opencode-config! config-root mcp-key current-url permissions config-extra)
  {:port started-port :url current-url})

(fn OpencodeMcpBridge [opts]
  (assert opts "OpencodeMcpBridge requires opts")
  (local name (or opts.name "OpencodeMcpBridge"))
  (local tools (or opts.tools (error (.. name " requires :tools"))))
  (local data-dir (or opts.data-dir (error (.. name " requires :data-dir"))))
  (local config-dir-name (or opts.config-dir-name (error (.. name " requires :config-dir-name"))))
  (local mcp-key (or opts.mcp-key (error (.. name " requires :mcp-key"))))
  (local permissions (or opts.permissions (error (.. name " requires :permissions"))))
  (local host (or opts.host "127.0.0.1"))
  (local force-sse (if (= opts.force-sse false) false true))
  (local status-extra opts.status-extra)
  (local config-extra opts.config-extra)
  (local http-server-factory (or opts.http-server-factory default-http-server-factory))
  (local mcp-server-factory (or opts.mcp-server-factory
                               (fn [http-server]
                                 (local MCPHTTPServer (require :mcp/server-http))
                                 (MCPHTTPServer {:http-server http-server
                                                 :tools tools
                                                 :force-sse force-sse}))))

  (var server nil)
  (var config-root nil)
  (var port nil)
  (var url nil)
  (var started? false)

  (fn start [self]
    (when started?
      (error (.. name " already started")))
    (ensure-dir! data-dir)
    (set config-root (fs.join-path data-dir config-dir-name))
    (ensure-dir! config-root)
    (set server (mcp-server-factory (http-server-factory)))
    (local (ok result) (pcall start-server-and-write-config!
                              server host name config-root mcp-key permissions config-extra))
    (when (not ok)
      (cleanup-failed-start! server)
      (set server nil)
      (set port nil)
      (set url nil)
      (set started? false)
      (error result))
    (set port result.port)
    (set url result.url)
    (set started? true)
    self)

  (fn stop [self]
    (when server
      (server:stop))
    (set server nil)
    (set port nil)
    (set url nil)
    (set started? false)
    self)

  (fn opencode-env [_self]
    (when (not started?)
      (error (.. name " must be started before building OpenCode env")))
    {:XDG_CONFIG_HOME config-root
     :OPENCODE_CONFIG_CONTENT (fs.read-file (config-path config-root))})

  (fn refresh-config! [_self]
    (when (not started?)
      (error (.. name " must be started before refreshing OpenCode config")))
    (write-opencode-config! config-root mcp-key url permissions config-extra)
    {:config-path (config-path config-root)
     :url url})

  (fn current-config-path [_self]
    (and config-root (config-path config-root)))

  (fn status [_self]
    (merge-status
      (status-extras status-extra)
      {:started? started?
       :host host
       :port port
       :url url
       :config-root config-root
       :config-path (and config-root (config-path config-root))}))

  {:start start
   :stop stop
   :opencode-env opencode-env
   :refresh-config! refresh-config!
   :config-path current-config-path
   :status status})

{:ensure-dir! ensure-dir!
 :remote-url remote-url
 :config-path config-path
 :write-opencode-config! write-opencode-config!
 :merge-tables merge-tables
 :resolve-config-extra resolve-config-extra
 :validate-config-extra! validate-config-extra!
 :resolve-permissions resolve-permissions
 :merge-status merge-status
 :OpencodeMcpBridge OpencodeMcpBridge}
