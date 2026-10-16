(local H (require :tests/test-reference-lifecycle-helpers))
(local J (require :json-utils))
(local Graph (require :graph/core))
(local {: GraphMap} (require :graph/map))
(local StringNode (. (require :graph/nodes/string-entity) :StringEntityNode))
(local tests [])

(fn add [name f]
  (fn rooted [root] (f (H.stores root)))
  (table.insert tests {:name (.. "reference lifecycle composition action " name)
                       :fn #(H.with-root rooted)}))

(fn subject! [s]
  (s.string-store:create-entity {:id "s" :value "(+ 1 2)"})
  (s.list-store:create-entity {:id "holder" :items ["string-entity:s"]}))

(fn node [s lifecycle]
  (StringNode {:entity-id "s" :store s.string-store :lifecycle lifecycle}))

(fn unchanged-error [s fragment f]
  (local before (J.stable-json (H.snapshot-tree s.base-dir)))
  (H.assert-error fragment f)
  (assert (= before (J.stable-json (H.snapshot-tree s.base-dir))) "conflict must precede every durable effect"))

(fn native-graph [s lifecycle]
  (Graph {:identity-store s.identity-store :string-store s.string-store :link-store s.link-store
          :lifecycle lifecycle :entity-events? false :morphs {}}))

(fn with-node [s lifecycle f]
  (local adapter (node s lifecycle))
  (local (ok result) (pcall f adapter))
  (adapter:drop)
  (if ok result (error result)))

(add "detached requires explicit service" (fn detached [s]
  (subject! s)
  (with-node s nil #(unchanged-error s "requires reference lifecycle" (fn delete [] ($1:delete-entity))))))

(add "detached matching service cleans incoming" (fn explicit [s]
  (subject! s)
  (local lifecycle (H.ready s))
  (fn action [adapter]
    (local deleted (adapter:delete-entity))
    (assert (= (# (. (s.list-store:snapshot-entity "holder") :value :items)) 0) "explicit frontend must clean incoming")
    (assert (= deleted.id "s"))
    (assert (= (adapter:resolve-reference-lifecycle!) lifecycle)))
  (with-node s lifecycle action)))

(fn mounted-conflict [s mutate]
  (subject! s)
  (local lifecycle (H.ready s))
  (local graph (native-graph s lifecycle))
  (local map (GraphMap {:graph graph :lifecycle lifecycle}))
  (local adapter (node s lifecycle))
  (adapter:mount map)
  (local (ok result) (pcall (fn check []
    (mutate adapter lifecycle)
    (unchanged-error s "reference lifecycle" #(adapter:delete-entity)))))
  (adapter:drop) (map:drop) (graph:drop)
  (if ok result (error result)))

(add "node graph service conflict before effects" (fn conflict [s]
  (mounted-conflict s (fn change [adapter _service] (set adapter.lifecycle (H.ready s))))))

(add "same root substitute store before effects" (fn substitute [s]
  (mounted-conflict s (fn change [adapter _service]
    (set adapter.store ((. (require :entities/string) :StringEntityStore) {:base-dir s.base-dir}))))))

(add "different root store before effects" (fn other-root [s]
  (fn other [root]
    (mounted-conflict s (fn change [adapter _service]
      (set adapter.store ((. (require :entities/string) :StringEntityStore) {:base-dir root})))))
  (H.with-root other)))

(add "changed identity dependency before effects" (fn identity-dependency [s]
  (subject! s)
  (local lifecycle (H.ready s))
  (s.list-store:create-entity {:id "victim"})
  (local adapter ((. (require :graph/nodes/list-entity) :ListEntityNode)
                  {:entity-id "victim" :store s.list-store :lifecycle lifecycle}))
  (local replacement ((. (require :entities/identity) :IdentityStore) {:base-dir s.base-dir}))
  (local (ok result) (pcall (fn check []
    (H.with-fields s.list-store {:identity-store replacement}
      #(unchanged-error s "reference lifecycle" (fn delete [] (adapter:delete-entity)))))))
  (adapter:drop)
  (if ok result (error result))))

(add "GraphMap shared Graph conflict before effects" (fn map-conflict [s]
  (local graph (native-graph s (H.ready s)))
  (local other (H.ready s))
  (var map nil)
  (fn create [] (set map (GraphMap {:graph graph :lifecycle other})))
  (fn check [] (unchanged-error s "reference lifecycle" create))
  (local (ok result) (pcall check))
  (when map (map:drop)) (graph:drop)
  (if ok result (error result))))

(add "explicit identity delete preserves represented object" (fn identity-delete [s]
  (subject! s)
  (s.identity-store:create-entity {:id "explicit" :target-key "string-entity:s"})
  (s.identity-store:create-entity {:id "upstream" :target-key "identity:explicit"})
  (s.list-store:create-entity {:id "alias-holder" :items ["identity:upstream"]})
  (local lifecycle (H.ready s))
  (local adapter ((. (require :graph/nodes/identity) :IdentityNode)
                  {:entity-id "explicit" :store s.identity-store :lifecycle lifecycle}))
  (fn action []
    (adapter:delete-entity)
    (assert (= (# (. (s.list-store:snapshot-entity "alias-holder") :value :items)) 0)
            "identity frontend must remove upstream live incoming membership")
    (assert (s.string-store:get-entity "s"))
    (assert (= (s.identity-store:get-entity "upstream") nil)))
  (local (ok result) (pcall action))
  (adapter:drop)
  (if ok result (error result))))

(fn map-only [s clear?]
  (subject! s)
  (s.dict-store:create-entity {:id "d" :items {:slot "string-entity:s"}})
  (s.notebook-store:create-notebook {:id "n" :items ["string-entity:s"]})
  (fn check [graph map]
    (assert graph.entity-events? "map-only guard must run actual default callbacks")
    (each [_ key (ipairs ["list-entity:holder" "dict-entity:d" "notebook:n" "string-entity:s"])]
      (assert (map:load-by-key key)))
    (local before (J.stable-json (H.snapshot-tree s.base-dir)))
    (if clear? (map:clear!) (map:remove-nodes [(map:lookup "string-entity:s")]))
    (assert (= before (J.stable-json (H.snapshot-tree s.base-dir))) "ordinary map operation must preserve owning bytes"))
  (H.with-graph s check {:lifecycle (H.ready s) :morphs {}}))
(add "map removal preserves domain bytes" #(map-only $1 false))
(add "map clear preserves domain bytes" #(map-only $1 true))

(add "workflow step delete prunes incoming" (fn step-delete [s]
  (local definition (s.workflow-store:create-definition {:id "w" :name "Workflow"}))
  (s.workflow-store:add-step definition.id {:id "step" :name "Step" :code-entity-id "c"})
  (s.list-store:create-entity {:id "step-holder" :items ["workflow-step:w:step"]})
  (local lifecycle (H.ready s))
  (local graph (native-graph s lifecycle))
  ((. (require :graph/nodes/workflow-step) :register-loader) graph {:store s.workflow-store :lifecycle lifecycle})
  (local map (GraphMap {:graph graph}))
  (local adapter (assert (map:load-by-key "workflow-step:w:step")))
  (fn action []
    (local deleted (adapter:delete-step-from-graph {}))
    (assert (= (# (. (s.list-store:snapshot-entity "step-holder") :value :items)) 0)
            "workflow step frontend must clean incoming references")
    (assert (= deleted.id "step")))
  (local (ok result) (pcall action))
  (map:drop) (graph:drop)
  (if ok result (error result))))

(add "morph uses canonical service" (fn morph [s]
  (subject! s)
  (local lifecycle (H.ready s))
  (var committed nil)
  (lifecycle.committed:connect (fn observe [result] (set committed result)))
  (local morphs ((. (require :morphs/init) :Morphs) {}))
  ((require :morphs/string-entity-to-code-entity) morphs)
  (fn action [adapter]
    (local result (morphs:apply adapter "code-entity" {:lifecycle lifecycle
      :string-store s.string-store :code-store s.code-store :identity-store s.identity-store}))
    (local held (. (s.list-store:snapshot-entity "holder") :value :items 1))
    (assert (= (s.identity-store:resolve-key held) result.code-key) "morph frontend must preserve incoming meaning")
    (assert (= committed result) "native morph must complete through the canonical lifecycle service")
    (assert (= result.source-key "string-entity:s"))
    (assert (= result.source-id "s")))
  (with-node s lifecycle action)))

(fn fail-completion [s lifecycle clear? action]
  (if clear?
      (H.with-fs-failure :remove ((. (require :fs) :join-path) s.base-dir "reference-lifecycle" "pending.json")
        #(H.assert-error "permission denied" action))
      (do
        (local handler (lifecycle.committed:connect (fn reject [_result] (error "frontend committed failure"))))
        (local (ok result) (pcall H.assert-error "frontend committed failure" action))
        (lifecycle.committed:disconnect handler true)
        (if ok result (error result)))))

(fn retry-without-preparation [action]
  (fn forbidden [...] (error "frontend retry attempted fresh preparation"))
  (H.with-fields (require :reference-lifecycle/plan) {:prepare forbidden} action))

(fn retry-morph [s clear?]
  (subject! s)
  (local lifecycle (H.ready s))
  (local morphs ((. (require :morphs/init) :Morphs) {}))
  ((require :morphs/string-entity-to-code-entity) morphs)
  (var committed nil) (var notifications 0) (var morph-events 0)
  (lifecycle.committed:connect (fn observe [result] (set committed result) (set notifications (+ notifications 1))))
  (morphs.morphed:connect (fn observe [_result] (set morph-events (+ morph-events 1))))
  (fn action [adapter]
    (fn apply [] (morphs:apply adapter "code-entity" {:lifecycle lifecycle}))
    (fail-completion s lifecycle clear? apply)
    (local intent (assert (lifecycle._pending:read)))
    (local frozen (J.stable-json intent))
    (assert (= (s.string-store:get-entity "s") nil) "failure boundary must follow retirement")
    (local replacement committed.code-entity)
    (local original-result (J.stable-json committed))
    (local after (H.snapshot-tree s.base-dir))
    (fn no-live-source [...] (error "retry read retired live string"))
    (local result (H.with-fields s.string-store {:get-entity no-live-source :create-entity no-live-source}
                    #(retry-without-preparation apply)))
    (assert (= (J.stable-json intent) frozen))
    (assert (= result.code-key intent.operation.target-key))
    (assert (= result.code-entity replacement))
    (assert (= (J.stable-json result) original-result) "retry must retain every original MorphResult field")
    (assert (= (J.stable-json result.updated-identity-keys) (J.stable-json intent.operation.updated-identity-keys)))
    (assert (= result.source-id "s")) (assert (= result.source-key "string-entity:s"))
    (assert (= result.target-key result.code-key)) (assert (= result.target-type "code-entity"))
    (assert (= (# (s.code-store:list-entities)) 1))
    (assert (= (lifecycle._pending:read) nil))
    (tset after "reference-lifecycle/pending.json" nil)
    (assert (= (J.stable-json after) (J.stable-json (H.snapshot-tree s.base-dir))))
    (assert (= notifications 2)) (assert (= morph-events 1)))
  (with-node s lifecycle action))

(fn retry-step [s clear?]
  (s.code-store:create-entity {:id "c"})
  (s.workflow-store:create-definition {:id "w" :steps [{:id "step" :code-entity-id "c"}
                                                      {:id "keep" :code-entity-id "c"}]
                                      :edges [{:id "incident" :source-step-id "step" :target-step-id "keep"}]})
  (local run (s.workflow-store:create-run "w" {} {}))
  (s.workflow-store:upsert-run-step run.id "step" {:status :succeeded})
  (s.workflow-store:append-event run.id {:kind :step-succeeded :step-id "step"})
  (s.list-store:create-entity {:id "holder" :items ["workflow-step:w:step"]})
  (local lifecycle (H.ready s))
  (local adapter ((. (require :graph/nodes/workflow-step) :WorkflowStepNode)
                  {:definition-id "w" :step-id "step" :store s.workflow-store :lifecycle lifecycle}))
  (var committed nil)
  (lifecycle.committed:connect (fn observe [result] (set committed result)))
  (fn action []
    (fn apply [] (adapter:delete-step-from-graph {}))
    (fail-completion s lifecycle clear? apply)
    (local intent (assert (lifecycle._pending:read)))
    (local frozen (J.stable-json intent))
    (local original-record (J.stable-json committed.source-record))
    (assert (= (adapter:get-step) nil) "failure boundary must follow workflow source removal")
    (local after (H.snapshot-tree s.base-dir))
    (fn no-live-step [...] (error "retry read retired workflow step"))
    (local result (H.with-fields adapter {:get-step no-live-step} #(retry-without-preparation apply)))
    (assert (= result.id committed.source-record.id))
    (assert (= result.id "step"))
    (assert (= (J.stable-json result) original-record))
    (assert (= (J.stable-json intent) frozen))
    (assert (= (lifecycle._pending:read) nil))
    (tset after "reference-lifecycle/pending.json" nil)
    (assert (= (J.stable-json after) (J.stable-json (H.snapshot-tree s.base-dir))))
    (assert (= (. (s.workflow-store:get-definition "w") :steps 1 :id) "keep"))
    (assert (= (# (. (s.workflow-store:get-definition "w") :edges)) 0))
    (assert (= (# (. (s.list-store:get-entity "holder") :items)) 0))
    (assert (s.workflow-store:get-run run.id))
    (assert (s.code-store:get-entity "c")))
  (local (ok result) (pcall action))
  (adapter:drop)
  (if ok result (error result)))

(add "retry morph committed" #(retry-morph $1 false))
(add "retry morph pending clear" #(retry-morph $1 true))
(add "retry workflow step committed" #(retry-step $1 false))
(add "retry workflow step pending clear" #(retry-step $1 true))

(fn expect-gl [mock name expected]
  (local args (icollect [_ call (ipairs (mock:get-gl-calls name))] call.args))
  (assert (= (J.stable-json args) (J.stable-json expected)) (.. "FXAA native call mismatch: " name)))

(fn check-fxaa-allocations [mock first second]
  (expect-gl mock "glTexImage2D"
    [{:target 0x0DE1 :level 0 :internal-format 0x1907 :width 640 :height 480 :border 0 :format 0x1907 :type 0x1401}
     {:target 0x0DE1 :level 0 :internal-format 0x1907 :width 800 :height 600 :border 0 :format 0x1907 :type 0x1401}])
  (expect-gl mock "glRenderbufferStorage"
    [{:target 0x8D41 :format 0x1902 :width 640 :height 480}
     {:target 0x8D41 :format 0x1902 :width 800 :height 600}])
  (expect-gl mock "glFramebufferTexture2D"
    [{:target 0x8D40 :attachment 0x8CE0 :textarget 0x0DE1 :texture first.texture :level 0}
     {:target 0x8D40 :attachment 0x8CE0 :textarget 0x0DE1 :texture second.texture :level 0}])
  (expect-gl mock "glFramebufferRenderbuffer"
    [{:target 0x8D40 :attachment 0x8D00 :renderbuffertarget 0x8D41 :renderbuffer first.depth}
     {:target 0x8D40 :attachment 0x8D00 :renderbuffertarget 0x8D41 :renderbuffer second.depth}])
  (local parameters [])
  (for [_ 1 2]
    (each [_ row (ipairs [[0x2801 0x2601] [0x2800 0x2601] [0x2802 0x812F] [0x2803 0x812F]])]
      (table.insert parameters {:target 0x0DE1 :pname (. row 1) :param (. row 2)})))
  (expect-gl mock "glTexParameteri" parameters)
  (expect-gl mock "checkFramebuffer" [{} {}]))

(fn fxaa-resources [mock fxaa index]
  (local call (. (mock:get-gl-calls "glGenTextures") index))
  (assert (= call.args.count 1))
  (assert (= (type call.args.handle) :number))
  {:fbo (fxaa:get-fbo) :depth (fxaa:get-depth-rbo) :texture call.args.handle})

(fn fxaa-lifecycle [mock create release]
  (local fxaa (create))
  (fxaa:on-viewport-changed {:width 640 :height 480})
  (assert (fxaa:ready?))
  (assert (= (fxaa:get-width) 640)) (assert (= (fxaa:get-height) 480))
  (local first (fxaa-resources mock fxaa 1))
  (local count (# mock.state.gl-calls))
  (fxaa:on-viewport-changed {:width 640 :height 480})
  (assert (= (# mock.state.gl-calls) count) "same viewport must not reallocate")
  (fxaa:on-viewport-changed {:width 800 :height 600})
  (local second (fxaa-resources mock fxaa 2))
  (assert (not (= first.texture second.texture)))
  (check-fxaa-allocations mock first second)
  (fxaa:render)
  (expect-gl mock "glDrawArrays" [{:mode 0x0005 :start 0 :count 4}])
  (local shader (. (mock:get-shader-loads) 1 :args :shader))
  (local steps (icollect [_ call (ipairs shader.calls)]
    (when (= call.name "setVector2f") {:uniform call.args.uniform :value call.args.value})))
  (assert (= (J.stable-json steps) (J.stable-json [{:uniform "u_texelStep" :value [(/ 1 800) (/ 1 600)]}])))
  (release)
  (expect-gl mock "glDeleteFramebuffers" [{:framebuffer first.fbo} {:framebuffer second.fbo}])
  (expect-gl mock "glDeleteRenderbuffers" [{:renderbuffer first.depth} {:renderbuffer second.depth}])
  (expect-gl mock "glDeleteTextures" [{:texture first.texture} {:texture second.texture}])
  (local vao (. (mock:get-gl-calls "glGenVertexArrays") 1 :args :handle))
  (expect-gl mock "glDeleteVertexArrays" [{:array vao}]))

(fn renderer-contract []
  (local mock ((require :mock-opengl)))
  (var fxaa nil)
  (fn create [] (set fxaa ((require :fxaa))) fxaa)
  (fn release [] (fxaa:drop) (set fxaa nil))
  (fn run [] (fxaa-lifecycle mock create release))
  (mock:install)
  (local (ok result) (pcall H.with-fields package.loaded {:fxaa false} run))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (when fxaa (release)))))
  (mock:restore)
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(table.insert tests {:name "reference lifecycle composition renderer nonzero viewport FXAA contract" :fn renderer-contract})

(local default-modules [:entities/identity :entities/string :entities/code :entities/list :entities/dict
                        :entities/link :notebooks/store :workflows/store])

(fn fresh-defaults [f]
  (local cleared {})
  (each [_ name (ipairs default-modules)] (require name) (tset cleared name false))
  (H.with-fields package.loaded cleared f))

(fn startup-fixture [root f]
  (local Main (require :main))
  (local Bootstrap (require :app-bootstrap))
  (local dirs (require :appdirs))
  (local previous-dir app.user-data-dir)
  (fn directory [_name] root)
  (fn run [] (f Main root))
  (fn cleanup []
    (Main.drop)
    (Bootstrap.init-themes) (Bootstrap.init-lights) (Bootstrap.init-input-systems)
    (set app.user-data-dir previous-dir))
  (fn scoped []
    (local (ok result) (pcall run))
    (local (drop-ok drop-error) (pcall cleanup))
    (if (not ok) (error result) (not drop-ok) (error drop-error) result))
  (fn viewport-scoped []
    (H.with-fields app {:viewport {:x 0 :y 0 :width 640 :height 480}} #(fresh-defaults scoped)))
  (H.with-fields dirs {:user-data-dir directory} viewport-scoped))

(fn add-startup [name f]
  (fn rooted [root] (startup-fixture root f))
  (table.insert tests {:name (.. "reference lifecycle composition startup " name)
                       :fn #(H.with-root rooted) :timeout-seconds 300}))

(add-startup "canonical code cache and native runtime providers" (fn cache [Main root]
  (Main.init)
  (assert (and (> app.viewport.width 0) (> app.viewport.height 0)) "startup must exercise nonzero native renderers")
  (local canonical ((. (require :entities/code) :get-default) {:base-dir root}))
  (assert (= app.code-store canonical) "Main must use the same lazy default CodeStore object")
  (local service (assert app.reference-lifecycle "Main must activate five real lifecycle owners"))
  (assert (= (# service.owners) 5))
  (each [_ field (ipairs [:list-store :dict-store :link-store :notebook-store])]
    (assert (= (. app field :identity-store) app.identity-store)))
  (local graph app.active-world-runtime.graph)
  (assert (= graph.reference-lifecycle service))
  (assert (= app.graph-map.reference-lifecycle service))
  (assert (= graph.identity-store app.identity-store))
  (assert (= graph.link-store app.link-store))
  (assert (= graph.string-store app.string-store))
  (canonical:create-entity {:id "cached"})
  (local adapter (assert (app.graph-map:load-by-key "code-entity:cached")))
  (adapter:delete-entity)
  (assert (= (canonical:get-entity "cached") nil))
  (assert (= (app.code-store:get-entity "cached") nil))))

(add-startup "drop removes only owned prompt enrichers" (fn prompt-lifetime [Main _root]
  (local Prompt (require :llm/agent/prompt-utils))
  (fn unrelated [_ctx] "unrelated fixture context")
  (Prompt.register-enricher :task7-unrelated unrelated)
  (fn action []
    (Main.init)
    (assert (string.find (Prompt.format-context {:app app}) "active world available" 1 true)
            "actual startup must register its owned prompt enrichment")
    (Main.drop)
    (assert (= (Prompt.format-context {}) "unrelated fixture context")
            "drop must remove only Main-owned enrichers")
    (Main.drop)
    (assert (= (Prompt.format-context {}) "unrelated fixture context") "targeted teardown must be idempotent"))
  (local (ok result) (pcall action))
  (Prompt.remove-enricher :task7-unrelated)
  (if ok result (error result))))

(add-startup "migration precedes visible world activation" (fn migration [Main root]
  (local s (H.stores root))
  (s.string-store:create-entity {:id "s" :value "before activation"})
  (H.raw-list s "legacy" ["string-entity:s"])
  (Main.init)
  (local store ((. (require :entities/list) :get-default) {:base-dir root}))
  (local key (. (store:snapshot-entity "legacy") :value :items 1))
  (assert (= (string.sub key 1 9) "identity:") "startup must migrate legacy incoming references before exposing worlds")
  (assert (= (store.identity-store:resolve-key key) "string-entity:s"))
  (assert app.active-world-runtime)
  (assert app.reference-lifecycle._state.ready?)))

(fn pending-delete! [root conflict?]
  (local fs (require :fs))
  (local s (H.stores root))
  (subject! s)
  (local service (H.ready s))
  (local path (. (s.string-store:snapshot-entity "s") :path))
  (fn delete []
    (H.assert-error "permission denied" #(service:delete! "string-entity:s")))
  (H.with-fs-failure :remove path delete)
  (when conflict?
    (local candidate ((. (require :reference-lifecycle/record-utils) :clone)
                       (. (s.string-store:snapshot-entity "s") :value)))
    (set candidate.value "external conflicting edit")
    (fs.write-file path (s.string-store:serialize-entity candidate)))
  s)

(add-startup "pending recovery precedes visible world activation" (fn recovery [Main root]
  (pending-delete! root false)
  (Main.init)
  (local store ((. (require :entities/string) :get-default) {:base-dir root}))
  (assert (= (store:get-entity "s") nil) "startup must finish pending source retirement before exposing worlds")
  (assert app.active-world-runtime)))

(add-startup "pending conflict blocks world exposure" (fn conflict [Main root]
  (pending-delete! root true)
  (local (ok result) (pcall Main.init))
  (assert (not ok) "startup conflict must prevent activation")
  (assert (string.find (tostring result) "pending conflict" 1 true) (tostring result))
  (assert (= app.active-world-runtime nil))
  (assert (= (app.world-manager:active-world-id) nil))))

(add-startup "default code root mismatch blocks activation" (fn root-mismatch [Main root]
  (local fs (require :fs))
  ((. (require :entities/code) :get-default) {:base-dir (fs.join-path root "other")})
  (local (ok result) (pcall Main.init))
  (assert (not ok) "canonical default root mismatch must fail before activation")
  (assert (string.find (tostring result) "code" 1 true) (tostring result))
  (assert (= app.active-world-runtime nil))))

{:tests tests}
