(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))

;; Temporary loaders must cover manager construction, which restores the active
;; native map. Permanent installation still belongs to HomeWorld's runtime.
(fn create [world ctx registry]
  (assert registry "HomeWorld requires app.graph-extension-registry before graph map restore")
  (local graph (Graph {:with-start false :entity-events? false :lifecycle ctx.lifecycle
                      :string-store ctx.string-store :link-store ctx.link-store :identity-store ctx.identity-store}))
  (local restore-runtime {:graph graph})
  (var restore-runtime-installed? false)
  (local (install-ok install-result) (pcall #(registry:install-runtime restore-runtime)))
  (if install-ok
      (set restore-runtime-installed? true)
      (do (graph:drop) (error install-result)))
  (local (map-manager-ok graph-map-manager)
    (pcall #(GraphMapManager.GraphMapManager
              {:graph graph :state (or world.state.graph {}) :data-dir world.dir})))
  (when restore-runtime-installed?
    (registry:uninstall-runtime restore-runtime))
  (when (not map-manager-ok)
    (graph:drop)
    (error graph-map-manager))
  (values graph graph-map-manager (graph-map-manager:get-active-map)))

{:create create}
