(local Common (require :graph/extensions/builtins/common))
(local HostedAppLauncherNode (require :graph/nodes/hosted-app-launcher))

(local schemes ["hosted-app-launcher"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn make-launcher-node []
  (HostedAppLauncherNode {}))

(fn install-loaders [_options graph ctx]
  [(graph:register-key-loader
     "hosted-app-launcher"
     (Common.exact-key-loader "hosted-app-launcher:workspace"
                              make-launcher-node)
     (loader-opts ctx))])

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-hosted-apps"
      :unit-id "builtin-graph-hosted-apps"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
