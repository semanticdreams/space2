(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local J (require :json-utils))
(local HomeWorld (require :home-world))
(local {: GraphMapManager} (require :graph/map-manager))
(local glm (require :glm))
(local tests [])
(local source-key "string-entity:s")
(local target-key "code-entity:c")
(local operation {:kind "morph" :source-key source-key :target-key target-key :retiring [source-key]
                  :reference-plan {:rewrites [] :identities []}})

(fn with-world [s f]
  (s.string-store:create-entity {:id "s" :value "(+ 1 2)"})
  (local dir (fs.join-path s.base-dir "worlds" "loaded"))
  (fs.create-dirs dir)
  (local world (HomeWorld {:id "loaded" :dir dir}))
  (world:save-state)
  (J.write-json! (fs.join-path s.base-dir "worlds" "index.json")
                {:worlds [{:id "loaded" :type "home" :name "Loaded"}]})
  (fn native [graph _map]
    (local maps (GraphMapManager {:graph graph :data-dir dir}))
    (set world.runtime {:graph graph :graph-map-manager maps})
    (set world.initialized? true)
    (fn context [] {})
    (fn create [opts] (assert (= opts.id world.id)) world)
    (local manager ((require :world-manager)
      {:root-dir (fs.join-path s.base-dir "worlds") :context-fn context :create-world create}))
    (manager:get-world-entry world.id)
    (local (ok result) (pcall f {:stores s :world world :graph graph :maps maps :manager manager}))
    (set world.runtime nil)
    (maps:drop)
    (if ok result (error result)))
  (H.with-graph s native))

(fn service [fixture]
  (local owner ((require :reference-lifecycle/world-owner)
                {:stores fixture.stores :world-manager fixture.manager}))
  (local runtime ((require :reference-lifecycle/runtime-owner)
                  {:stores fixture.stores :world-manager fixture.manager}))
  (H.ready fixture.stores owner runtime))

(fn add [name f]
  (fn root-fixture [root] (with-world (H.stores root) f))
  (fn run [] (H.with-root root-fixture))
  (table.insert tests {:name (.. "reference lifecycle projections " name) :fn run}))

(add "shared core exposure survives coordinator replacement" (fn core-exposure [fixture]
  (local graph fixture.graph)
  (assert (graph:load-by-key source-key))
  (local lifecycle (service fixture))
  (local result (lifecycle:replace! source-key {:name "" :language "fnl" :source "(+ 1 2)" :kernel 0}))
  (assert (not (graph:lookup source-key)) "source adapter must retire")
  (assert (graph:lookup result.code-key) "previously exposed shared Core must retain replacement participation")))

(fn populate-maps [fixture]
  (local s fixture.stores)
  (each [_ id (ipairs ["a" "b" "x" "hidden"])]
    (s.string-store:create-entity {:id id :value id}))
  (s.identity-store:create-entity {:id "I1" :target-key source-key})
  (s.identity-store:create-entity {:id "I2" :target-key "identity:I1"})
  (s.identity-store:create-entity {:id "alias" :target-key source-key})
  (each [_ row (ipairs [["incoming" "string-entity:a" "identity:I1"]
                        ["parallel" "string-entity:a" "identity:alias"]
                        ["upstream" "string-entity:b" "identity:I2"]
                        ["outgoing" "identity:I1" "string-entity:b"]
                        ["hidden" "identity:I1" "string-entity:hidden"]])]
    (s.link-store:create-entity {:id (. row 1) :source-key (. row 2) :target-key (. row 3)}))
  (local maps fixture.maps)
  (local main (maps:get-active-map))
  (main:restore-state {:nodes [source-key "string-entity:a" "string-entity:b"]
                       :edges [{:source "string-entity:a" :target "string-entity:b"
                                :label "explicit" :weight 7 :opaque {:text source-key :flag false}}]})
  (maps:create-map! "second" "Second")
  (maps:switch-map! "second")
  (local second (maps:get-active-map))
  (second:load-by-key source-key)
  (second:load-by-key "string-entity:a")
  (maps:create-map! "unrelated" "Unrelated")
  (maps:switch-map! "unrelated")
  (local unrelated (maps:get-active-map))
  (unrelated:load-by-key "string-entity:x")
  (maps:create-map! "uninstantiated" "Uninstantiated")
  (maps:switch-map! "second")
  nil)

;; The native switch owns both adapters only during maps-will-change. Never keep
;; a map handle after its manager has dropped it.
(fn with-participating-maps [fixture f]
  (populate-maps fixture)
  (local maps fixture.maps)
  (var called? false)
  (fn switching [event]
    (when (= event.active-id "main")
      (set called? true)
      (local main (assert (maps:get-instantiated-map "main")))
      (local second (assert (maps:get-instantiated-map "second")))
      (assert (= second (maps:get-active-map)))
      (assert (not (maps:get-instantiated-map "unrelated")))
      (assert (not (maps:get-instantiated-map "uninstantiated")))
      (f {:main main :second second})))
  (local handler (maps.maps-will-change:connect switching))
  (local (ok result) (pcall maps.switch-map! maps "main"))
  (maps.maps-will-change:disconnect handler true)
  (assert called?)
  (if ok result (error result)))

(fn runtime-owner [fixture]
  ((require :reference-lifecycle/runtime-owner) {:stores fixture.stores :world-manager fixture.manager}))

(add "frozen captures isolate instantiated participating maps" (fn frozen-maps [fixture]
  (fn check [native]
  (local owner (runtime-owner fixture))
  (local before (J.stable-json (fixture.maps:snapshot-reference-state)))
  (local preparation (H.no-writes #(owner:prepare (owner:inventory) operation)))
  (assert (= (# preparation.changes) 0))
  (local ids (icollect [_ capture (ipairs preparation.runtime-state)] capture.map-id))
  (table.sort ids)
  (assert (= (J.stable-json ids) (J.stable-json ["main" "second"]))
          "capture only affected instantiated native map IDs")
  (each [_ capture (ipairs preparation.runtime-state)]
    (assert (= capture.owner "runtime"))
    (assert (= capture.world-id "loaded"))
    (assert (= capture.before.record nil))
    (assert (= capture.after.record nil))
    (assert (= (# capture.before.maps.maps) 1))
    (assert (= (. capture.after.maps.maps 1 :id) capture.map-id)))
  (assert (= before (J.stable-json (fixture.maps:snapshot-reference-state))))
  (assert (native.second:lookup source-key)))
  (with-participating-maps fixture check)))

(fn link-ids [graph]
  (local ids {})
  (each [_ edge (ipairs graph.edges)]
    (when (and edge._opts edge._opts.from-link-entity)
      (assert (not (. ids edge._opts.from-link-entity)) "parallel link IDs must remain unique")
      (tset ids edge._opts.from-link-entity edge)))
  ids)

(add "map links reconcile upstream aliases parallel IDs and explicit attributes" (fn native-links [fixture]
  (fn check [native]
  (local lifecycle (service fixture))
  (local result (lifecycle:replace! source-key {:name "" :language "fnl" :source "(+ 1 2)" :kernel 0}))
  (assert (native.main:lookup result.code-key))
  (assert (native.second:lookup result.code-key))
  (assert (not (fixture.maps:get-instantiated-map "unrelated")))
  (H.no-writes #(native.main:reconcile-link-projections!))
  (local ids (link-ids native.main))
  (each [_ id (ipairs ["incoming" "parallel" "upstream" "outgoing"])]
    (assert (. ids id) (.. "missing exact derived link ID: " id)))
  (assert (not (. ids "hidden")))
  (assert (not (native.main:lookup "string-entity:hidden")))
  (local explicit (. (native.main:capture-state) :edges 1))
  (assert (= explicit.weight 7))
  (assert (= explicit.label "explicit"))
  (assert (= explicit.opaque.flag false))
  (assert (= explicit.opaque.text source-key))
  (fixture.stores.link-store:delete-entity "incoming")
  (H.no-writes #(native.main:reconcile-link-projections!))
  (local remaining (link-ids native.main))
  (assert (not (. remaining "incoming")))
  (assert (. remaining "parallel"))
  (assert (= (. (native.main:capture-state) :edges 1 :weight) 7)))
  (with-participating-maps fixture check)))

(add "core link reconciliation never hydrates hidden endpoints" (fn core-links [fixture]
  (populate-maps fixture)
  (local graph fixture.graph)
  (graph:load-by-key source-key)
  (graph:load-by-key "string-entity:a")
  (graph:load-by-key "string-entity:b")
  (H.no-writes #(graph:reconcile-link-projections!))
  (local ids (link-ids graph))
  (each [_ id (ipairs ["incoming" "parallel" "upstream" "outgoing"])] (assert (. ids id)))
  (assert (not (. ids "hidden")))
  (assert (not (graph:lookup "string-entity:hidden")))
  (assert (not (graph:lookup "identity:I2")))
  (H.no-writes #(graph:reconcile-link-projections!))
  (assert (= (# graph.edges) 4))))

(fn same [actual expected]
  (assert (= (J.stable-json actual) (J.stable-json expected))
          (.. "values differ: " (J.stable-json actual) " != " (J.stable-json expected))))

(fn native-view-icons []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1} :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph 4242 glyph}})
  (fn resolve [_self _name] {:type :font :codepoint 4242 :font font})
  {:resolve resolve})

(fn with-view [fixture f]
  (local FocusManager (. (require :focus) :FocusManager))
  (local focus (FocusManager {:root-name "reference-projections"}))
  (local scope (focus:create-scope {:name "reference-projections-scope"}))
  (local camera ((require :camera) {:position (glm.vec3 7 8 100)}))
  (local ctx ((require :build-context)
    {:clickables ((require :clickables)) :focus-manager focus :focus-scope scope
     :layout-root ((. (require :layout) :LayoutRoot) {:log-dirt? false})
     :hoverables app.hoverables
     :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                    :label-color (glm.vec4 1 1 1 1) :label-target-pixels 13
                    :label-min-scale 4 :edge-color (glm.vec4 0.6 0.6 0.6 1)}
             :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}}))
  (set ctx.icons (native-view-icons))
  (local graph-map (fixture.maps:get-active-map))
  (local view ((require :graph/view) {:graph-map graph-map :ctx ctx :camera camera :data-dir fixture.world.dir}))
  (fn inspect []
    (H.with-fields fixture.world.runtime {:graph-view view :graph-map graph-map} #(f view)))
  (local (ok result) (pcall inspect))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (view:drop) (camera:drop) (focus:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn retained-view [marker]
  {:marker marker :selected_node_keys [source-key] :focused_node_key source-key :focused_node_key_present? true
   :views {:open-views []}
   :mode_states {:spatial {:camera {:position [7 8 100]} :note source-key :extra_panels []}}})

(fn view-fixture! [fixture]
  (local graph-map (fixture.maps:get-active-map))
  (graph-map:restore-state {:nodes [source-key] :edges [] :selected_node_keys [source-key]
                            :focused_node_key source-key :outline_root_keys [source-key]})
  (fixture.maps:create-map! "other" "Other")
  (local rt fixture.world.runtime)
  (set rt.graph-view-states {:main (retained-view "retained main") :other (retained-view "retained other")})
  (set rt.graph-view-state (retained-view "retained single"))
  (set rt.activity-session-state {:graph {:graph-view-state (retained-view "runtime single")
                                         :graph-view-states {:main (retained-view "runtime main")
                                                             :other (retained-view "runtime other")}}})
  (set fixture.world.state.activity.sessions.graph
       {:graph-view-state (retained-view "activity single")
        :graph-view-states {:main (retained-view "activity main") :other (retained-view "activity other")}}))

(fn map-capture [preparation id]
  (local found (icollect [_ capture (ipairs preparation.runtime-state)] (when (= capture.map-id id) capture)))
  (assert (= (# found) 1) "must capture exactly one native map namespace")
  (. found 1))

(add "native view roles freeze only their map namespace" (fn view-roles [fixture]
  (view-fixture! fixture)
  (fn inspect [view]
    (local owner (runtime-owner fixture))
    (local before (H.snapshot-tree fixture.stores.base-dir))
    (local prep (H.no-writes #(owner:prepare (owner:inventory) operation)))
    (local capture (map-capture prep "main"))
    (local roles (assert capture.before.views "native map must freeze its view mirrors"))
    (assert roles.current)
    (same (. roles.retained :main) (retained-view "retained main"))
    (assert (not (. roles.retained :other)))
    (assert (not (. roles.activity.graph-view-states :other)))
    (assert (not (. roles.runtime-session.graph-view-states :other)))
    (assert (not (. capture.before.metadata :other)))
    (assert (. capture.before.metadata :main))
    (same (. capture.after.views.retained :main :selected_node_keys) [target-key])
    (same (H.snapshot-tree fixture.stores.base-dir) before)
    (local position view.runtime.camera.position)
    (same [position.x position.y position.z] [7 8 100]))
  (with-view fixture inspect)))

(add "frozen native view replay retains metadata focus and unrelated sessions" (fn view-replay [fixture]
  (view-fixture! fixture)
  (fixture.stores.code-store:create-entity {:id "c" :name "" :source "(+ 1 2)" :language "fnl" :kernel 0})
  (fn inspect [view]
    (local owner (runtime-owner fixture))
    (local metadata (view.persistence:snapshot-state))
    (set metadata.positions {source-key [11 12 0]})
    (set metadata.sizes {source-key [33 17]})
    (set metadata.presentations {source-key "expanded"})
    (view.persistence:install-state! metadata)
    (local prep (H.no-writes #(owner:prepare (owner:inventory) operation)))
    (local frozen (J.stable-json prep.runtime-state))
    (local capture (map-capture prep "main"))
    (assert capture.after.metadata "map preparation must freeze the native persistence cache")
    (local rt fixture.world.runtime)
    (set rt.graph-view-states.other.marker "later unrelated edit")
    (local before (H.snapshot-tree fixture.stores.base-dir))
    (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state}))
    (assert (= rt.graph-view-states.other.marker "later unrelated edit"))
    (same rt.graph-view-states.main.selected_node_keys [target-key])
    (assert (= rt.graph-view-state.focused_node_key target-key))
    (assert (= rt.activity-session-state.graph.graph-view-state.focused_node_key target-key))
    (same (view.persistence:snapshot-state) (. capture.after.metadata :main))
    (assert (= view.graph-map.focused_node_key target-key))
    (same view.graph-map.selected_node_keys [target-key])
    (local installed (view:snapshot-reference-state))
    (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state}))
    (same (view:snapshot-reference-state) installed)
    (assert (= frozen (J.stable-json prep.runtime-state)))
    (same (H.snapshot-tree fixture.stores.base-dir) before))
  (with-view fixture inspect)))

(add "core preserves explicit equal endpoint edges and legacy link callbacks" (fn core-explicit [fixture]
  (local graph fixture.graph)
  (local s fixture.stores)
  (s.string-store:create-entity {:id "a" :value "a"})
  (s.link-store:create-entity {:id "one" :source-key source-key :target-key "string-entity:a"})
  (s.link-store:create-entity {:id "two" :source-key source-key :target-key "string-entity:a"})
  (local source (graph:load-by-key source-key))
  ;; Node-add discovery requires both endpoints (the Task2 link-store contract).
  (local target (assert (graph:load-by-key "string-entity:a")))
  (local explicit ((. (require :graph/edge) :GraphEdge) {:source source :target target :label "authored"}))
  (graph:add-edge explicit)
  (H.no-writes #(graph:reconcile-link-projections!))
  (assert (= (# graph.edges) 3))
  (assert (= (. graph.edge-map (.. source-key "->string-entity:a")) explicit))
  (same (. (graph:snapshot-reference-state) :edges 1 :label) "authored")
  (s.link-store:delete-entity "one")
  (H.no-writes #(graph:reconcile-link-projections!))
  (assert (= (# graph.edges) 2))
  (assert (. (link-ids graph) :two))
  (assert (= (. graph.edge-map (.. source-key "->string-entity:a")) explicit))))

(local replacement {:name "" :language "fnl" :source "(+ 1 2)" :kernel 0})

(fn pending [s] ((require :reference-lifecycle/pending) s.base-dir))

(add "runtime error retains frozen captures and reserved code on retry" (fn retry-runtime [fixture]
  (local graph fixture.graph)
  (graph:load-by-key source-key)
  (local lifecycle (service fixture))
  (fn fail-on-replacement [event]
    (when (= (string.sub event.node.key 1 12) "code-entity:")
      ;; A real callback reentering the serialized service must fail explicitly.
      (lifecycle:replace! source-key replacement)))
  (local handler (graph.node-added:connect fail-on-replacement))
  (H.assert-error "reference lifecycle busy" #(lifecycle:replace! source-key replacement))
  (graph.node-added:disconnect handler true)
  (local intent (: (pending fixture.stores) :read))
  (assert intent "runtime install failure must retain pending intent")
  (local frozen (J.stable-json intent.runtime-state))
  (assert (> (# intent.runtime-state) 0))
  (assert (fixture.stores.string-store:get-entity "s") "source must retire after runtime success")
  (local reserved intent.operation.target-key)
  (local result (lifecycle:replace! source-key replacement))
  (assert (= result.code-key reserved))
  (assert (= (# (fixture.stores.code-store:list-entities)) 1))
  (assert (graph:lookup reserved))
  (assert (= frozen (J.stable-json intent.runtime-state)))
  (assert (not (: (pending fixture.stores) :read)))))

(add "retirement failure cold restart defers unloaded maps to durable activation" (fn cold-restart [fixture]
  (local map (fixture.maps:get-active-map))
  (map:load-by-key source-key)
  (local lifecycle (service fixture))
  (local path (. (fixture.stores.string-store:snapshot-entity "s") :path))
  (H.with-fs-failure "remove" path #(H.assert-error "permission denied" #(lifecycle:replace! source-key replacement)))
  (local intent (: (pending fixture.stores) :read))
  (local reserved intent.operation.target-key)
  (assert (map:lookup reserved) "failure must occur after real runtime installation")
  (local s (H.stores fixture.stores.base-dir))
  (fn forbidden [...] (error "cold replay must not activate worlds"))
  (local manager ((require :world-manager) {:root-dir (fs.join-path s.base-dir "worlds")
                                           :context-fn forbidden :create-world forbidden}))
  (local world-owner ((require :reference-lifecycle/world-owner) {:stores s :world-manager manager}))
  (local runtime ((require :reference-lifecycle/runtime-owner) {:stores s :world-manager manager}))
  (local cold (H.lifecycle s world-owner runtime))
  (cold:start!)
  (assert (not (: (pending s) :read)))
  (assert (not (s.string-store:get-entity "s")))
  (assert (= (# (s.code-store:list-entities)) 1))
  (local world (HomeWorld {:id "loaded" :dir fixture.world.dir}))
  (world:init {})
  (local restored (icollect [_ key (ipairs (. world.state.graph.maps 1 :nodes))] (when (= key reserved) key)))
  (assert (= (# restored) 1) "initialized world must load the frozen reserved key before activation")
  (fn activate [graph _map]
    (local maps (GraphMapManager {:graph graph :data-dir world.dir :state world.state.graph}))
    (local active (maps:get-active-map))
    (assert (active:lookup reserved) "normal activation must consume durable WorldOwner after-image")
    (assert (not (active:lookup source-key)))
    (maps:drop))
  (H.with-graph s activate)))

(add "replay skips unloaded maps without activating or replacing current view" (fn skipped-map [fixture]
  (view-fixture! fixture)
  (fixture.stores.code-store:create-entity {:id "c" :name "" :source "(+ 1 2)" :language "fnl" :kernel 0})
  (local owner (runtime-owner fixture))
  (local prep (with-view fixture (fn capture [_view] (owner:prepare (owner:inventory) operation))))
  (fixture.maps:switch-map! "other")
  (local current (fixture.maps:get-active-map))
  (assert (not (fixture.maps:get-instantiated-map "main")))
  (fn inspect [view]
    (local before (view:snapshot-reference-state))
    (local tree (H.snapshot-tree fixture.stores.base-dir))
    (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state}))
    (same (view:snapshot-reference-state) before)
    (same (H.snapshot-tree fixture.stores.base-dir) tree)
    (assert (= (fixture.maps:get-active-map) current))
    (assert (not (current:lookup target-key)))
    (assert (not (fixture.maps:get-instantiated-map "main"))))
  (with-view fixture inspect)))

(fn containers! [fixture]
  (local s fixture.stores)
  (s.identity-store:create-entity {:id "direct" :target-key source-key})
  (s.identity-store:create-entity {:id "upstream" :target-key "identity:direct"})
  (s.list-store:create-entity {:id "mounted" :items ["identity:upstream"]})
  (s.list-store:create-entity {:id "unopened" :items ["identity:upstream"]})
  (s.dict-store:create-entity {:id "mounted" :items {:slot "identity:upstream"}})
  (s.dict-store:create-entity {:id "unopened" :items {:slot "identity:upstream"}})
  (s.notebook-store:create-notebook {:id "mounted" :items ["identity:upstream"]})
  (s.notebook-store:create-notebook {:id "unopened" :items ["identity:upstream"]})
  (local map (fixture.maps:get-active-map))
  (icollect [_ key (ipairs ["list-entity:mounted" "dict-entity:mounted" "notebook:mounted"])]
    (assert (map:load-by-key key))))

(fn assert-container-connectivity [map nodes key]
  (each [_ node (ipairs nodes)]
    (local address (.. node.key "->" key))
    (assert (. map.edge-map address) (.. "missing committed container connectivity: " address))))

(add "committed container projections refresh upstream aliases without authoring" (fn container-aliases [fixture]
  (local nodes (containers! fixture))
  (local map (fixture.maps:get-active-map))
  (fixture.stores.code-store:create-entity {:id "c" :name "" :source "(+ 1 2)" :language "fnl" :kernel 0})
  (map:load-by-key target-key)
  (assert-container-connectivity map nodes source-key)
  (local tree (H.snapshot-tree fixture.stores.base-dir))
  (fixture.stores.identity-store:update-entity "direct" {:target-key target-key})
  (assert-container-connectivity map nodes target-key)
  (each [_ node (ipairs nodes)] (assert (not (. map.edge-map (.. node.key "->" source-key)))))
  (local after (H.snapshot-tree fixture.stores.base-dir))
  (each [path bytes (pairs tree)]
    (when (not (= path "entities/identity/direct.json"))
      (assert (= (. after path) bytes) (.. "projection refresh authored owning bytes: " path))))
  ;; Existing genuine explicit identity-delete cleanup remains enabled until Task7.
  (fixture.stores.identity-store:delete-entity "upstream")
  (assert (= (# (. (fixture.stores.list-store:get-entity "mounted") :items)) 0))
  (assert (= (# (. (fixture.stores.notebook-store:get-notebook "mounted") :items)) 0))))

(add "projection removal and clear keep complete owning bytes identical" (fn projection-only [fixture]
  (containers! fixture)
  (local s fixture.stores)
  (s.code-store:create-entity {:id "workflow-code" :name "" :source "42" :language "fnl" :kernel 0})
  (s.link-store:create-entity {:id "relationship" :source-key source-key :target-key "list-entity:mounted"})
  (s.workflow-store:create-definition {:id "workflow" :steps [{:id "step" :name "Step" :code-entity-id "workflow-code"}]})
  (set fixture.world.state.board {:items [{:id "subject" :type "string-entity" :subject-key source-key
                                           :position [1 2 0] :size [30 20 0] :state {:opaque false}}]
                                  :connectors []})
  (fixture.world:save-state)
  (local map (fixture.maps:get-active-map))
  (local tree (H.snapshot-tree fixture.stores.base-dir))
  (local state (map:capture-state))
  (set state.nodes (icollect [_ key (ipairs state.nodes)] (when (not (= key source-key)) key)))
  (set state.edges [])
  (H.no-writes #(map:install-reference-state! state))
  (same (H.snapshot-tree fixture.stores.base-dir) tree)
  (H.no-writes #(map:install-reference-state! {:nodes [] :edges []}))
  (same (H.snapshot-tree fixture.stores.base-dir) tree)
  (assert (= (map:node-count) 0))))

(fn board-roles! [fixture]
  (local state {:items [{:id "source" :type "string-entity" :subject-key source-key :state {:opaque false}}
                        {:id "keep" :type "string-entity" :subject-key "string-entity:keep" :state {:marker "keep"}}]
               :connectors [{:id "visual" :source-item-id "source" :target-item-id "keep" :kind "visual" :state {}}]})
  (fixture.stores.string-store:create-entity {:id "keep" :value "keep"})
  (local R (require :reference-lifecycle/record-utils))
  (set fixture.world.state.board (R.clone state))
  (set fixture.world.state.activity.sessions.board {:board-state (R.clone state)})
  (local rt fixture.world.runtime)
  (set rt.board ((. (require :board/core) :Board) {:state state}))
  (set rt.board-state (R.clone state))
  (set rt.activity-session-state {:board {:board-state (R.clone state)}})
  state)

(add "supplied board capture installs every separate mirror without IO" (fn install-board-roles [fixture]
  (board-roles! fixture)
  (local owner (runtime-owner fixture))
  (local prep (H.no-writes #(owner:prepare (owner:inventory) operation)))
  (local captures (icollect [_ capture (ipairs prep.runtime-state)] (when (= capture.map-id false) capture)))
  (assert (= (# captures) 1))
  (local expected (. captures 1 :after :board))
  (local rt fixture.world.runtime)
  (local kept (. rt.board.items :keep))
  (local tree (H.snapshot-tree fixture.stores.base-dir))
  (H.no-writes #(owner:reconcile! {:runtime-state captures}))
  (same fixture.world.state.board expected.state)
  (same fixture.world.state.activity.sessions.board.board-state expected.activity)
  (same rt.board-state expected.retained)
  (same rt.activity-session-state.board.board-state expected.runtime-session)
  (same (rt.board:capture-state) expected.model)
  (assert (= (. rt.board.items :keep) kept))
  (H.no-writes #(owner:reconcile! {:runtime-state captures}))
  (same (H.snapshot-tree fixture.stores.base-dir) tree)))

(add "core opaque delta updates explicit attributes and preserves survivors idempotently" (fn core-delta [fixture]
  (local graph fixture.graph)
  (fixture.stores.string-store:create-entity {:id "keep" :value "keep"})
  (local source (graph:load-by-key source-key))
  (local kept (graph:load-by-key "string-entity:keep"))
  (local state {:nodes [source-key kept.key]
               :edges [{:source source-key :target kept.key :label "before" :color [0.1 0.2 0.3 1]
                        :weight 7 :opaque {:text source-key :flag false} :_opts {:from-link-entity "opaque-not-provenance"}}]})
  (H.no-writes #(graph:install-reference-state! state))
  (local edge (. graph.edges 1))
  (assert (= edge._opts nil))
  (set (. state.edges 1 :label) "after")
  (set (. state.edges 1 :color) [0 1 0 1])
  (set (. state.edges 1 :weight) 11)
  (H.no-writes #(graph:install-reference-state! state))
  (assert (= (. graph.edges 1) edge))
  (assert (= (graph:lookup source-key) source))
  (assert (= (graph:lookup kept.key) kept))
  (assert (= edge.label "after") "Core delta must synchronize live explicit attributes")
  (same (. (graph:snapshot-reference-state) :edges) state.edges)
  (H.no-writes #(graph:install-reference-state! state))
  (same (. (graph:snapshot-reference-state) :edges) state.edges)))

(add "pending before runtime replays identical frozen native view captures" (fn before-runtime [fixture]
  (view-fixture! fixture)
  (fn inspect [view]
    (local lifecycle (service fixture))
    (local path (.. fixture.world.state-path ".tmp"))
    (H.with-fs-failure "write-file" path #(H.assert-error "permission denied" #(lifecycle:replace! source-key replacement)))
    (local intent (: (pending fixture.stores) :read))
    (local frozen (J.stable-json intent.runtime-state))
    (assert (fixture.stores.string-store:get-entity "s"))
    (assert (not (view.graph-map:lookup intent.operation.target-key)))
    (local capture (map-capture intent "main"))
    (local result (lifecycle:replace! source-key replacement))
    (assert (= result.code-key intent.operation.target-key))
    (assert (= (# (fixture.stores.code-store:list-entities)) 1))
    (same (view.persistence:snapshot-state) (. capture.after.metadata :main))
    (same view.graph-map.selected_node_keys [result.code-key])
    (assert (= frozen (J.stable-json intent.runtime-state)))
    (assert (not (: (pending fixture.stores) :read))))
  (with-view fixture inspect)))

(add "third loaded unrelated world never acquires replacement participation" (fn unrelated-world [fixture]
  (local s fixture.stores)
  (s.string-store:create-entity {:id "other" :value "Other"})
  (local dir (fs.join-path s.base-dir "worlds" "other"))
  (fs.create-dirs dir)
  (local other (HomeWorld {:id "other" :dir dir}))
  (other:save-state)
  (local maps (GraphMapManager {:graph fixture.graph :data-dir dir}))
  (local unrelated (maps:get-active-map))
  (unrelated:load-by-key "string-entity:other")
  (set other.runtime {:graph fixture.graph :graph-map-manager maps})
  (fn context [] {})
  (fn create [opts] (if (= opts.id "loaded") fixture.world (assert (= opts.id "other")) other))
  (local manager ((require :world-manager) {:root-dir (fs.join-path s.base-dir "worlds") :context-fn context :create-world create}))
  (manager:get-world-entry "loaded") (manager:get-world-entry "other")
  (fn check [native]
    (H.with-fields fixture {:manager manager} (fn replace []
      (local lifecycle (service fixture))
      (local before (unrelated:capture-state))
      (local result (lifecycle:replace! source-key replacement))
      (assert (native.main:lookup result.code-key))
      (assert (native.second:lookup result.code-key))
      (assert (not (unrelated:lookup result.code-key)))
      (same (unrelated:capture-state) before))))
  (local (ok err) (pcall with-participating-maps fixture check))
  (set other.runtime nil)
  (maps:drop)
  (when (not ok) (error err))))

(add "mounted and unopened containers have identical coordinated deletion" (fn delete-equivalence [fixture]
  (containers! fixture)
  (local s fixture.stores)
  (local lifecycle (service fixture))
  (local notifications {})
  (fn changed [row]
    (assert row.id "owning notification requires record ID")
    (tset notifications row.id (+ (or (. notifications row.id) 0) 1)))
  (local handler (s.list-store.list-entity-items-changed:connect changed))
  (lifecycle:delete! source-key)
  (s.list-store.list-entity-items-changed:disconnect handler true)
  (each [_ id (ipairs ["mounted" "unopened"])]
    (same (. (s.list-store:get-entity id) :items) [])
    (same (. (s.notebook-store:get-notebook id) :items) [])
    (assert (= (next (. (s.dict-store:get-entity id) :items)) nil))
    (assert (= (. notifications id) 1) "coordinator must not double-edit mounted owning records"))
  (assert (not (s.identity-store:get-entity "direct")))
  (assert (not (s.identity-store:get-entity "upstream")))))

(fn find-input [widget]
  (assert (or (= widget nil) (= (type widget) :table)) "native widget traversal requires table")
  (when (= (type widget) :table)
    (var found widget.input)
    (when (and (not found) widget.child) (set found (find-input widget.child)))
    (each [_ child (ipairs (or widget.children [])) &until found]
      (set found (find-input (or child.element child))))
    found))

(add "real open panels retain survivor Input focus through morph and retry" (fn panel-focus [fixture]
  (view-fixture! fixture)
  (fixture.stores.string-store:create-entity {:id "keep" :value "Survivor"})
  (local map (fixture.maps:get-active-map))
  (local keep (map:load-by-key "string-entity:keep"))
  (fn inspect [view]
    (local lifecycle (service fixture))
    (local source (map:lookup source-key))
    (view.views:open source) (view.views:open keep)
    (local original (. view.views.node-views source :dialog))
    (local survivor (. view.views.node-views keep :dialog))
    (local source-input (assert (find-input original) "native source panel must build real Input"))
    (local survivor-input (assert (find-input survivor) "native survivor panel must build real Input"))
    (survivor-input:request-focus)
    (local focused survivor-input.focus-node)
    (local manager focused.manager)
    (assert (= (manager:get-focused-node) focused))
    (local source-path (. (fixture.stores.string-store:snapshot-entity "s") :path))
    (H.with-fs-failure "remove" source-path #(H.assert-error "permission denied" #(lifecycle:replace! source-key replacement)))
    (local intent (: (pending fixture.stores) :read))
    (local reserved intent.operation.target-key)
    (local code (assert (map:lookup reserved)))
    (assert (. view.views.node-views code) "native source panel must be replaced with code panel")
    (assert (= (. view.views.node-views keep :dialog) survivor))
    (assert (= (manager:get-focused-node) focused) "morph must retain surviving Input focus, not force graph shell focus")
    (assert (= source-input.focus-node nil) "retired Input must drop its native focus registration")
    (local frozen (J.stable-json intent.runtime-state))
    (lifecycle:replace! source-key replacement)
    (assert (= (manager:get-focused-node) focused))
    (assert (= (. view.views.node-views keep :dialog) survivor))
    (assert (= frozen (J.stable-json intent.runtime-state)))
    (local ordinary (view:capture-state))
    (local keys (icollect [_ row (ipairs ordinary.views.open-views)] row.node-key))
    (same keys [reserved keep.key]))
  (with-view fixture inspect)))

(add "upstream list island refresh stays projection only and nonloading" (fn island-chain [fixture]
  (local nodes (containers! fixture))
  (local node (. nodes 1))
  (local map (fixture.maps:get-active-map))
  (node:expand-items-as-island)
  (local original (map:get-island "ordered-list:mounted"))
  (fixture.stores.code-store:create-entity {:id "c" :name "" :source "42" :language "fnl" :kernel 0})
  (map:load-by-key target-key)
  (fixture.stores.identity-store:update-entity "direct" {:target-key target-key})
  (local island (map:get-island original.id))
  (same island.members [target-key])
  (same island.state original.state)
  (local tree (H.snapshot-tree fixture.stores.base-dir))
  (H.no-writes #(node:refresh-reference-projection!))
  (same (H.snapshot-tree fixture.stores.base-dir) tree)))

(add "supplied runtime replay never reads world or metadata snapshots" (fn replay-no-read [fixture]
  (view-fixture! fixture)
  (fixture.stores.code-store:create-entity {:id "c" :name "" :source "42" :language "fnl" :kernel 0})
  (local owner (runtime-owner fixture))
  (fn inspect [view]
    (local prep (owner:prepare (owner:inventory) operation))
    (local frozen (J.stable-json prep))
    (local tree (H.snapshot-tree fixture.stores.base-dir))
    (fn install [] (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state})))
    (fn metadata-unreadable [] (H.with-fs-failure "read-file" view.persistence.metadata-path install))
    (H.with-fs-failure "read-file" fixture.world.state-path metadata-unreadable)
    (same (H.snapshot-tree fixture.stores.base-dir) tree)
    (assert (= frozen (J.stable-json prep)))
    (same view.graph-map.selected_node_keys [target-key]))
  (with-view fixture inspect)))

(fn metadata-change [owner]
  (local prep (owner:prepare (owner:inventory) operation))
  (local rows (icollect [_ change (ipairs prep.changes)]
    (when (= change.address "world-metadata:loaded:main") change)))
  (assert (= (# rows) 1) "loaded native metadata must prepare exactly one owning change")
  (. rows 1))

(add "first metadata after image creates only its validated owning parent" (fn metadata-parent [fixture]
  (view-fixture! fixture)
  (fn inspect [view]
    (local owner ((require :reference-lifecycle/world-owner) {:stores fixture.stores :world-manager fixture.manager}))
    (local path view.persistence.metadata-path)
    (local parent (fs.parent path))
    (assert (not (fs.exists parent)) "first native metadata parent must initially be absent")
    (assert (not (fs.exists path)))
    (local change (H.no-writes #(metadata-change owner)))
    (local frozen (J.stable-json change))
    (local invalid ((. (require :reference-lifecycle/record-utils) :clone) change))
    (set invalid.after-check "invalid")
    (H.no-writes #(H.assert-error "after-check" #(owner:apply! invalid)))
    (assert (not (fs.exists parent)) "candidate validation must precede directory creation")
    (owner:apply! change)
    (assert (fs.exists parent))
    (local json (require :json))
    (same (json.loads (fs.read-file path)) (json.loads change.after-bytes))
    (same (view.persistence:snapshot-state) (json.loads change.after-bytes))
    (H.no-writes #(owner:apply! change))
    (H.no-writes #(owner:reconcile! {:changes [change]}))
    (assert (= frozen (J.stable-json change))))
  (with-view fixture inspect)))

(add "metadata mkdir failure retains cache and frozen change through retry" (fn metadata-parent-failure [fixture]
  (view-fixture! fixture)
  (fn inspect [view]
    (local owner ((require :reference-lifecycle/world-owner) {:stores fixture.stores :world-manager fixture.manager}))
    (local path view.persistence.metadata-path)
    (local parent (fs.parent path))
    (assert (not (fs.exists parent)) "mkdir failure starts before first native metadata parent")
    (assert (not (fs.exists path)))
    (local change (H.no-writes #(metadata-change owner)))
    (local frozen (J.stable-json change))
    (local before (view.persistence:snapshot-state))
    (H.with-fs-failure "create-dirs" parent #(H.assert-error "permission denied: create-dirs" #(owner:apply! change)))
    (assert (not (fs.exists parent)))
    (assert (not (fs.exists path)))
    (same (view.persistence:snapshot-state) before)
    (H.with-fs-failure "write-file" (.. path ".tmp") #(H.assert-error "permission denied: write-file" #(owner:apply! change)))
    (assert (not (fs.exists path)))
    (same (view.persistence:snapshot-state) before)
    (assert (= frozen (J.stable-json change)))
    (owner:apply! change)
    (local json (require :json))
    (same (view.persistence:snapshot-state) (json.loads change.after-bytes))
    (assert (= frozen (J.stable-json change)))
    (H.no-writes #(owner:apply! change))
    (H.no-writes #(owner:reconcile! {:changes [change]})))
  (with-view fixture inspect)))

(fn create-container! [fixture kind items]
  (local s fixture.stores)
  (if (= kind "notebook") (s.notebook-store:create-notebook {:id "holder" :items items})
      (= kind "dict") (s.dict-store:create-entity {:id "holder" :items {:first (. items 1) :second (. items 2)}})
      (s.list-store:create-entity {:id "holder" :items items}))
  (.. (if (= kind "notebook") "notebook" (.. kind "-entity")) ":holder"))

(fn assert-authored-edge [map key edge row]
  (assert (= (. map.edge-map key) edge) "projection refresh must retain authored survivor edge object")
  (assert (= edge.label row.label) "projection refresh must retain live authored label")
  (local color (glm.vec4 (table.unpack row.color)))
  (assert (= edge.color color) "projection refresh must retain live authored color")
  (local rows (icollect [_ candidate (ipairs (. (map:capture-state) :edges))]
    (when (and (= candidate.source row.source) (= candidate.target row.target)) candidate)))
  (same rows [row]))

(fn explicit-survivor [fixture kind]
  (local s fixture.stores)
  (s.string-store:create-entity {:id "keep" :value "Keep"})
  (s.string-store:create-entity {:id "again" :value "Again"})
  (local holder (create-container! fixture kind ["string-entity:keep"]))
  (local map (fixture.maps:get-active-map))
  (map:restore-state {:nodes [source-key "string-entity:again" holder "string-entity:keep"] :edges []})
  (local lifecycle (service fixture))
  (local row {:source holder :target "string-entity:keep" :label "Authored survivor" :color [0 0.5 1 1]
             :weight 17 :opaque {:text source-key :flag false}})
  (local state (map:capture-state))
  (set state.edges [row])
  ;; Restore a native authored row after container expansion, not provenance.
  (map:restore-state state)
  (local key (.. holder "->string-entity:keep"))
  (local edge (assert (. map.edge-map key)))
  (local source-path (. (s.string-store:snapshot-entity "s") :path))
  (H.with-fs-failure "remove" source-path #(H.assert-error "permission denied" #(lifecycle:replace! source-key replacement)))
  (assert-authored-edge map key edge row)
  (local intent (: (pending s) :read))
  (local frozen (J.stable-json intent.runtime-state))
  (lifecycle:replace! source-key replacement)
  (assert-authored-edge map key edge row)
  (local owner (runtime-owner fixture))
  (H.no-writes #(owner:reconcile! intent))
  (H.no-writes #(owner:reconcile! intent))
  (assert-authored-edge map key edge row)
  (assert (= frozen (J.stable-json intent.runtime-state)))
  (lifecycle:replace! "string-entity:again" {:name "" :language "fnl" :source "Again" :kernel 0})
  (assert-authored-edge map key edge row)
  ;; Removing committed membership must not remove an authored replacement at an
  ;; address that the old container projection once owned.
  (if (= kind "notebook") (s.notebook-store:update-notebook "holder" {:items []})
      (= kind "dict") (s.dict-store:update-entity "holder" {:items {}})
      (s.list-store:update-entity "holder" {:items []}))
  (assert-authored-edge map key edge row))

(fn removed-member [fixture kind]
  (local s fixture.stores)
  (var loads 0)
  (local hidden "task6-hidden:member")
  (fn load-hidden [key]
    (assert (= key hidden))
    (set loads (+ loads 1))
    ((. (require :graph/node-base) :GraphNode) {:key key :label "Hidden member"}))
  (fixture.graph:register-key-loader "task6-hidden" load-hidden)
  (local holder (create-container! fixture kind [source-key hidden]))
  (local map (fixture.maps:get-active-map))
  (local node (assert (map:load-by-key holder)))
  (assert (map:lookup hidden) "explicit container expansion must initially expose its member")
  (map:remove-nodes [(map:lookup hidden)])
  (assert (not (map:lookup hidden)))
  (s.code-store:create-entity {:id "c" :source "(+ 1 2)" :language "fnl" :name "" :kernel 0})
  (local owner (runtime-owner fixture))
  (local prep (H.no-writes #(owner:prepare (owner:inventory) operation)))
  (local capture (map-capture prep "main"))
  (local frozen (J.stable-json prep))
  (set loads 0)
  (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state}))
  (assert (= loads 0) "passive replacement reconciliation must never invoke the hidden loader")
  (assert (not (map:lookup hidden)))
  (local expected (icollect [_ key (ipairs (. capture.after.maps.maps 1 :nodes))] key))
  (table.sort expected)
  (same (. (map:capture-state) :nodes) expected)
  (assert (= (map:lookup holder) node))
  (H.no-writes #(owner:reconcile! {:runtime-state prep.runtime-state}))
  (assert (= loads 0))
  (assert (= frozen (J.stable-json prep)))
  ;; The owning relationship remains; explicit expansion is still the deliberate
  ;; loading API after passive reconciliation leaves participation unchanged.
  (node:add-item-nodes)
  (assert (= loads 1))
  (assert (map:lookup hidden)))

(each [_ kind (ipairs ["list" "dict" "notebook"])]
  (fn explicit [fixture] (explicit-survivor fixture kind))
  (fn removed [fixture] (removed-member fixture kind))
  (add (.. "review " kind " explicit survivor ownership") explicit)
  (add (.. "review " kind " replay never loads removed member") removed))

(fn foreign-runtime [fixture foreign-stores manager?]
  (fn check [graph _map]
    (local rt {:graph graph})
    (when manager? (set rt.graph-map-manager fixture.maps))
    (local tree (H.snapshot-tree fixture.stores.base-dir))
    (local foreign-tree (H.snapshot-tree foreign-stores.base-dir))
    (local before (graph:capture-state))
    (fn preflight [] (H.no-writes #(H.assert-error "reference composition" #(runtime-owner fixture))))
    (H.with-fields fixture.world {:runtime rt} preflight)
    (same (graph:capture-state) before)
    (same (H.snapshot-tree fixture.stores.base-dir) tree)
    (same (H.snapshot-tree foreign-stores.base-dir) foreign-tree))
  (H.with-graph foreign-stores check))

(add "review different root runtime graph rejected with manager" (fn different-root [fixture]
  (H.with-root (fn foreign [root] (foreign-runtime fixture (H.stores root) true)))))
(add "review distinct stores runtime graph rejected with manager" (fn distinct-stores [fixture]
  (foreign-runtime fixture (H.stores fixture.stores.base-dir) true)))
(add "review different root graph only runtime rejected" (fn graph-only-root [fixture]
  (H.with-root (fn foreign [root] (foreign-runtime fixture (H.stores root) false)))))
(add "review distinct stores graph only runtime rejected" (fn graph-only-stores [fixture]
  (foreign-runtime fixture (H.stores fixture.stores.base-dir) false)))
(add "review distinct core with canonical stores rejected with manager" (fn distinct-core [fixture]
  (foreign-runtime fixture fixture.stores true)))

(add "review list publication follows native point registration" (fn point-order [fixture]
  (local s fixture.stores)
  (local holder (create-container! fixture "list" [source-key]))
  (local map (fixture.maps:get-active-map))
  (local node (map:load-by-key holder))
  (node:expand-items-as-island)
  (local next-key "string-entity:next")
  (var current-view nil)
  (var publications 0)
  (var early? false)
  (fn published [payload]
    (each [_ key (ipairs payload.island.members)]
      (when (= key next-key)
        (set publications (+ publications 1))
        (when (not (. current-view.points (map:lookup key))) (set early? true)))))
  ;; Observe before the native view's island listener; this records early
  ;; publication even when that listener subsequently raises a layout error.
  (local handler (map.island-updated:connect published))
  (fn inspect [view]
    (set current-view view)
    (s.string-store:create-entity {:id "next" :value "Next"})
    (s.list-store:add-item "holder" next-key)
    (assert (> publications 0) "owning membership addition must publish an updated island")
    (assert (not early?) "island publication must follow native member point registration")
    (assert (. view.points (map:lookup next-key)))
    (same (. (map:get-island "ordered-list:holder") :members) [source-key next-key]))
  (local (ok err) (pcall with-view fixture inspect))
  (map.island-updated:disconnect handler true)
  (when (not ok) (error err))))

tests
