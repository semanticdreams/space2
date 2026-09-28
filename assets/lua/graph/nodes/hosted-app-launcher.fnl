(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local SourceResolver (require :app-host.source-resolver))
(local HostedSourceLauncher (require :app-host.hosted-source-launcher))

(local NODE-KEY "hosted-app-launcher:workspace")

(fn copy-selected-keys [graph-map]
  (assert graph-map "copy-selected-keys requires graph-map")
  (local selected (if graph-map.selected_node_keys graph-map.selected_node_keys []))
  (icollect [_ key (ipairs selected)] key))

(fn source-label [source]
  (assert source "source-label requires source")
  (if source.label
      source.label
      source.module-name
      source.module-name
      source.entry-path
      source.entry-path
      source.path
      source.path
      "hosted app"))

(fn disabled-status [result]
  {:status :disabled
   :reason (and result result.reason)
   :message (if (and result result.message)
                result.message
                "select one filesystem app source")})

(fn ready-status [source]
  {:status :ready
   :message (.. "Ready to launch " (source-label source))
   :source source})

(fn launched-status [source]
  {:status :launched
   :message (.. "Hosted app launched: " (source-label source))
   :source source})

(fn error-status [message source]
  {:status :error
   :message (tostring message)
   :source source})

(fn hosted-state [node]
  (assert node._hosted-app-launcher "HostedAppLauncherNode missing internal state"))

(fn set-status! [node next-status]
  (local state (hosted-state node))
  (set state.status next-status)
  (state.status-changed:emit state.status)
  state.status)

(fn resolve-current-selection [node]
  (local state (hosted-state node))
  (assert state.graph-map "HostedAppLauncherNode requires a mounted GraphMap")
  (state.resolver.resolve-selection state.graph-map (copy-selected-keys state.graph-map)))

(fn refresh-selection [self]
  (local result (resolve-current-selection self))
  (if (and result result.ok?)
      (set-status! self (ready-status result))
      (set-status! self (disabled-status result))))

(fn current-status [self]
  (. (hosted-state self) :status))

(fn launch-source [self source opts]
  (local state (hosted-state self))
  (local (ok session-or-error)
    (pcall state.launcher.open-source source opts))
  (if ok
      (do
        (set-status! self (launched-status source))
        session-or-error)
      (do
        (set-status! self (error-status session-or-error source))
        nil)))

(fn open-selected [self opts]
  (local result (resolve-current-selection self))
  (if (not (and result result.ok?))
      (do
        (set-status! self (disabled-status result))
        nil)
      (launch-source self result opts)))

(fn selection-changed [self _payload]
  (self:refresh-selection))

(fn make-selection-handler [self]
  (fn [payload]
    (selection-changed self payload)))

(fn mount-launcher-node [self graph-map]
  (local state (hosted-state self))
  (state.original-mount self graph-map)
  (set state.graph-map graph-map)
  (when (and graph-map graph-map.selection-changed graph-map.selection-changed.connect)
    (set state.selection-handler
         (graph-map.selection-changed:connect (make-selection-handler self))))
  self)

(fn unmount-launcher-node [self]
  (local state (hosted-state self))
  (when (and state.graph-map state.selection-handler state.graph-map.selection-changed)
    (state.graph-map.selection-changed:disconnect state.selection-handler true)
    (set state.selection-handler nil))
  (set state.graph-map nil)
  (state.original-unmount self))

(fn drop-launcher-node [self]
  (local state (hosted-state self))
  (when self.unmount
    (self:unmount))
  (state.status-changed:clear)
  (state.original-drop self))

(fn HostedAppLauncherNode [opts]
  (local options (if opts opts {}))
  (local resolver (if options.source-resolver options.source-resolver SourceResolver))
  (local launcher (if options.source-launcher options.source-launcher HostedSourceLauncher))
  (assert (= (type resolver.resolve-selection) :function)
          "HostedAppLauncherNode requires source-resolver.resolve-selection")
  (assert (= (type launcher.open-source) :function)
          "HostedAppLauncherNode requires source-launcher.open-source")
  (local status-changed (Signal))
  (local node
    (GraphNode {:key NODE-KEY
                :label "Hosted App Launcher"
                :color (glm.vec4 0.34 0.45 0.74 1)
                :sub-color (glm.vec4 0.45 0.58 0.9 1)
                :kind-badge "HOST"}))
  (set node._hosted-app-launcher
       {:resolver resolver
        :launcher launcher
        :graph-map nil
        :selection-handler nil
        :status {:status :disabled
                 :message "select one filesystem app source"}
        :status-changed status-changed
        :original-mount node.mount
        :original-unmount node.unmount
        :original-drop node.drop})
  (set node.status-changed status-changed)
  (set node.mount mount-launcher-node)
  (set node.unmount unmount-launcher-node)
  (set node.refresh-selection refresh-selection)
  (set node.current-status current-status)
  (set node.open-selected open-selected)
  (set node.drop drop-launcher-node)
  node)

HostedAppLauncherNode
