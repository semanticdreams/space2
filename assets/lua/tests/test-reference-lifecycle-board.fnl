(local H (require :tests/test-reference-lifecycle-helpers))
(local J (require :json-utils))
(local fs (require :fs))
(local glm (require :glm))
(local {: Board} (require :board/core))
(local BoardView (require :board/view))
(local Registry (require :board/registry))
(local BuiltinString (require :board/builtin-string-entity))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local {: FocusManager} (require :focus))
(local HomeWorld (require :home-world))
(local BoardActivity (require :board-activity-unit))
(local ObjectSelector (require :object-selector))
(local json (require :json))
(local Activities (require :activities))
(local tests [])
(local source-text " \n(+ 1 2)\n ")

(fn same [actual expected]
  (assert (= (J.stable-json actual) (J.stable-json expected))
          (.. (J.stable-json actual) " != " (J.stable-json expected))))

(fn state [subject]
  {:items [{:id "source" :type "string-entity" :subject-key subject
            :position [11 12 0] :rotation [1 0 0 0] :size [33 17 0]
            :state {:opaque {:source "string-entity:s" :enabled false}
                    :cursor-state {:index 2 :anchor false} :saved-layout {:source "string-entity:s"}}}
           {:id "a" :type "string-entity" :subject-key "string-entity:a"
            :position [50 0 0] :rotation [1 0 0 0] :size [32 16 0] :state {:marker "A"}}
           {:id "b" :type "string-entity" :subject-key "string-entity:b"
            :position [90 0 0] :rotation [1 0 0 0] :size [32 16 0] :state {:marker "B"}}]
   :connectors [{:id "K" :kind "semantic-link" :semantic-link-id "k"
                 :source-item-id "a" :target-item-id "b" :state {:marker "semantic"}}
                {:id "T" :kind "visual" :source-item-id "source" :target-item-id "a"}]})

(fn with-renderer [f]
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus (FocusManager {:root-name "reference-lifecycle-board"}))
  (local canvas (Canvas {:camera camera :focus-manager focus}))
  (local (ok result) (pcall f canvas))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (canvas:drop) (focus:drop) (camera:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn with-mounted-fixture [s subject canvas f]
  (local board (Board {:state (state subject)}))
  (local selector (ObjectSelector {:ctx canvas.build-context :pointer-target canvas}))
  (local owned [])
  (fn mount [state lifecycle]
    (assert board "native fixture requires board")
    (local model (or state board))
    (local view (BoardView {:board model :canvas canvas :ctx canvas.build-context
                           :selector selector :lifecycle lifecycle
                           :string-store s.string-store :code-store s.code-store
                           :identity-store s.identity-store :link-store s.link-store}))
    (table.insert owned view)
    view)
  (local fixture {:stores s :board board :canvas canvas :subject subject :owned owned :mount mount
                 :selector selector})
  (local (ok result) (pcall f fixture))
  (local (drop-ok drop-error) (pcall (fn cleanup []
    (for [index (# owned) 1 -1] (: (. owned index) :drop))
    (selector:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn with-registry [f]
  (local previous-board app.board-registry)
  (local previous-activity app.activity-registry)
  (local previous-signal app.activities-changed)
  (set app.board-registry nil)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (local (ok result) (pcall (fn run [] (BoardActivity.load-board-activity!) (f))))
  (local (drop-ok drop-error) (pcall BoardActivity.unload-board-activity!))
  (set app.board-registry previous-board)
  (set app.activity-registry previous-activity)
  (set app.activities-changed previous-signal)
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn with-fixture-root [root identity? f]
  (local s (H.stores root))
    (s.string-store:create-entity {:id "s" :value source-text})
    (s.string-store:create-entity {:id "a" :value "A"})
    (s.string-store:create-entity {:id "b" :value "B"})
    (s.link-store:create-entity {:id "k" :source-key "string-entity:a" :target-key "string-entity:b"})
    (local subject (if identity? (s.identity-store:ensure-key "string-entity:s") "string-entity:s"))
    ;; Registry owns all types and its Signal. Restore only after owned views drop.
    (fn renderer [canvas] (with-mounted-fixture s subject canvas f))
    (fn registry [] (with-renderer renderer))
    (with-registry registry))

(fn with-fixture [identity? f]
  (H.with-root #(with-fixture-root $1 identity? f)))

(fn add [name identity? f]
  (table.insert tests {:name (.. "reference lifecycle board " name)
                       :fn #(with-fixture identity? f)}))

(add "injected raw source renders owned editable value" false (fn render [fixture]
  (local view (fixture.mount))
  (local body (. view.item-records "source" :element))
  (assert (= (body.input:get-text) source-text) "native Input must read injected owning StringStore")
  (body.input:set-text "edited")
  (assert (= (. (fixture.stores.string-store:get-entity "s") :value) "edited"))))

(add "identity source renders owned editable value" true (fn render [fixture]
  (local view (fixture.mount))
  (assert (= (: (. view.item-records "source" :element :input) :get-text) source-text)
          "native identity source must resolve through injected IdentityStore")))

(add "subject update replaces native body not survivor widgets" false (fn update [fixture]
  (local view (fixture.mount))
  (local source (. view.item-records "source" :element))
  (local a (. view.item-records "a" :element))
  (fixture.stores.string-store:create-entity {:id "next" :value "next source"})
  (fixture.board:update-item-subject "source" "string-entity:next" "string-entity")
  (local next (. view.item-records "source" :element))
  (assert (not (= next source)) "subject update must replace the native editable body")
  (assert (= (next.input:get-text) "next source"))
  (assert (= (. view.item-records "a" :element) a) "unrelated native widget must be held")))

(fn start-world [fixture]
  (local s fixture.stores)
  (local root (fs.join-path s.base-dir "worlds"))
  (local dir (fs.join-path root "loaded"))
  (fs.create-dirs dir)
  (local world (HomeWorld {:id "loaded" :dir dir}))
  (set world.state.board (fixture.board:capture-state))
  (world:save-state)
  (set world.runtime {:board fixture.board :board-state (fixture.board:capture-state)})
  (set world.initialized? true)
  (J.write-json! (fs.join-path root "index.json") {:worlds [{:id "loaded" :type "home" :name "Loaded"}]})
  (local manager ((require :world-manager)
    {:root-dir root :context-fn (fn context [] {}) :create-world (fn create [_opts] world)}))
  (manager:get-world-entry "loaded")
  (local owner ((require :reference-lifecycle/world-owner) {:stores s :world-manager manager}))
  (local service (H.lifecycle s owner))
  (local raw {:board (fixture.board:capture-state) :tree (H.snapshot-tree s.base-dir)
              :strings (icollect [_ id (ipairs ["s" "a" "b"])] (s.string-store:snapshot-entity id))})
  (service:start!)
  (local migrated (fixture.board:capture-state))
  (local expected ((. (require :reference-lifecycle/record-utils) :clone) raw.board))
  (each [index item (ipairs migrated.items)]
    (H.assert-reference s.identity-store item.subject-key (. raw.board.items index :subject-key))
    (set (. expected.items index :subject-key) item.subject-key))
  (same migrated expected)
  (same raw.strings (icollect [_ id (ipairs ["s" "a" "b"])] (s.string-store:snapshot-entity id)))
  (set fixture.raw-baseline raw)
  (set fixture.migration-baseline {:board migrated :tree (H.snapshot-tree s.base-dir)})
  (when (os.getenv "SPACE_TASK5_UI_EVIDENCE")
    (print (.. "[REFERENCE-BOARD-STAGES] " (J.stable-json
      {:raw raw :migration fixture.migration-baseline}))))
  (set fixture.world world)
  service)

(fn add-composition [name identity? f]
  (table.insert tests {:name (.. "reference lifecycle composition Board " name)
                       :fn #(with-fixture identity? f)}))

(add-composition "ordinary identity subject deletion cleans incoming" false (fn delete [fixture]
  (local s fixture.stores)
  (s.list-store:create-entity {:id "holder" :items [fixture.subject]})
  (local lifecycle (start-world fixture))
  (local view (fixture.mount nil lifecycle))
  (set fixture.world.runtime.board-view view)
  (local removed (view:remove-item "source"))
  (assert (= (# (. (s.list-store:snapshot-entity "holder") :value :items)) 0)
          "Board ordinary removal must coordinate incoming cleanup")
  (assert (= removed.id "source"))
  (assert (= (s.string-store:get-entity "s") nil))))

(add-composition "authoring uses canonical stores and stable subjects" false (fn create [fixture]
  (local lifecycle (start-world fixture))
  (local view (fixture.mount nil lifecycle))
  (local item (view:add-string-entity {:value "new canonical value"}))
  (assert (= (string.sub item.subject-key 1 9) "identity:") "Board authoring must emit stable subject")
  (local terminal (fixture.stores.identity-store:resolve-key item.subject-key))
  (local id (string.match terminal "^string%-entity:(.+)$"))
  (assert (= (. (fixture.stores.string-store:get-entity id) :value) "new canonical value"))))

(add-composition "ownership conflict precedes removal effects" true (fn conflict [fixture]
  (local lifecycle (H.ready (H.stores fixture.stores.base-dir)))
  (local view (fixture.mount nil lifecycle))
  (local before (J.stable-json (H.snapshot-tree fixture.stores.base-dir)))
  (H.assert-error "reference lifecycle" #(view:remove-item "source"))
  (assert (= before (J.stable-json (H.snapshot-tree fixture.stores.base-dir))))
  (assert fixture.board.items.source)))

(fn text-value [text]
  (assert text "native code body must own Text, not the retired editable Input")
  (local utf8 (require :utf8))
  (table.concat (icollect [_ cp (ipairs (text:get-codepoints))] (utf8.char cp))))

(add "logical morph replaces editable body with live readonly source" false (fn morph [fixture]
  (local service (start-world fixture))
  (local view (fixture.mount))
  (set fixture.world.runtime.board-view view)
  (local old (. view.item-records "source" :element))
  (local survivor (. view.item-records "a" :element))
  (local survivor-record (. view.item-records "a"))
  (local selectable survivor-record.selectable)
  (assert selectable "fixture must exercise real native selection handles")
  (fixture.selector:set-selected [selectable])
  (local before (fixture.board:capture-state))
  (local result (service:replace! "string-entity:s" {:name "" :source source-text :language "fnl" :kernel 0}))
  (local body (. view.item-records "source" :element))
  (assert (= (text-value body.text) source-text))
  (assert (= body.input nil) "code source must not use readonly Input")
  (assert (not (= body old)) "logical morph must retire old editable widget")
  (assert (= (. view.item-records "a" :element) survivor))
  (assert (= (. view.item-records "a") survivor-record))
  (assert (= survivor-record.selectable selectable))
  (assert (= (. view.selected-items 1) fixture.board.items.a))
  (view.layer.layout:measurer)
  (view.layer.layout:layouter)
  (assert (= body.text.layout.parent body.layout) "code composite must contain owned Text layout")
  (assert (= body.layout.position.x 11))
  (assert (= body.layout.position.y 12))
  (assert (= body.layout.size.x 33))
  (assert (= body.text.layout.root body.layout.root))
  (same fixture.board.items.source.state (. before.items 1 :state))
  (same (. (fixture.board:capture-state) :connectors) before.connectors)
  (body.text.layout:measurer)
  (local width body.text.layout.measure.x)
  (local source "longer replacement code source than the original\n  keep whitespace  ")
  (local before-source-update (H.snapshot-tree fixture.stores.base-dir))
  (var string-updates 0)
  (local updates fixture.stores.string-store.string-entity-updated)
  (local handler (updates:connect (fn changed [_entity] (set string-updates (+ string-updates 1)))))
  (local (ok err) (pcall (fn update-source []
    (fixture.stores.code-store:update-entity result.code-entity.id {:source source}))))
  (updates:disconnect handler true)
  (when (not ok) (error err))
  (assert (= string-updates 0) "readonly source updates must never publish String writes")
  (local after-source-update (H.snapshot-tree fixture.stores.base-dir))
  (local path (.. "entities/code/" result.code-entity.id ".json"))
  (assert (. after-source-update path) "actual CodeStore source record must be persisted")
  (tset after-source-update path (. before-source-update path))
  (same after-source-update before-source-update)
  (assert (= (text-value body.text) source) "CodeStore event must refresh actual visible Text")
  (body.text.layout:measurer)
  (assert (> body.text.layout.measure.x width) "actual native Text geometry must refresh")
  (assert (= (fixture.stores.string-store:get-entity "s") nil))))

(add "stable alias retarget changes supported body binding" true (fn retarget [fixture]
  (local s fixture.stores)
  (local view (fixture.mount))
  (s.code-store:create-entity {:id "c" :name "" :source source-text :language "fnl" :kernel 0})
  (local alias (s.identity-store:create-entity {:id "alias" :target-key "code-entity:c"}))
  (s.identity-store:update-entity (string.sub fixture.subject 10) {:target-key "identity:alias"})
  (local code (. view.item-records "source" :element))
  (assert (= (text-value code.text) source-text))
  (s.identity-store:update-entity alias.id {:target-key "string-entity:a"})
  (local input (. view.item-records "source" :element :input))
  (assert (= (input:get-text) "A") "same identity key must bind new terminal")
  (s.code-store:update-entity "c" {:source "old code no longer displayed"})
  (assert (= (input:get-text) "A"))
  (H.assert-error "Unsupported board entity subject"
    #(s.identity-store:update-entity alias.id {:target-key "external:unsupported"}))
  (assert (= (. view.item-records "source" :element :input) input)
          "unsupported retarget must not erase the held widget")
  (assert fixture.board.items.source "unsupported data must retain its native row")))

(add "native snapshot and cold rebuild retain owning data" false (fn snapshot [fixture]
  (local service (start-world fixture))
  (local view (fixture.mount))
  (set fixture.world.runtime.board-view view)
  (local before-tree (H.snapshot-tree fixture.stores.base-dir))
  (local before-state (fixture.board:capture-state))
  (local before-item fixture.board.items.source)
  (local observed (H.no-writes #(fixture.world:snapshot-reference-state)))
  (same before-tree (H.snapshot-tree fixture.stores.base-dir))
  (same before-state (fixture.board:capture-state))
  (assert (= fixture.board.items.source before-item))
  (same observed.board.model before-state)
  (local result (service:replace! "string-entity:s" {:name "" :source source-text :language "fnl" :kernel 0}))
  (local after-tree (H.snapshot-tree fixture.stores.base-dir))
  (local captured (view:capture-state))
  (set fixture.world.state.board captured)
  (fixture.world:save-state)
  (local cold (HomeWorld {:id "loaded" :dir fixture.world.dir}))
  (cold:init {})
  (local model (Board {:state cold.state.board}))
  (local reopened (fixture.mount model))
  (assert (= (text-value (. reopened.item-records "source" :element :text)) source-text))
  (assert (= (. reopened.item-records "source" :element :input) nil))
  (assert (= (fixture.stores.identity-store:resolve-key model.items.source.subject-key) result.code-key))
  (same model.items.source.state (. before-state.items 1 :state))
  (local fresh (H.stores fixture.stores.base-dir))
  (same (fixture.stores.string-store:snapshot-entity "a") (fresh.string-store:snapshot-entity "a"))
  (local persisted (json.loads (fs.read-file fixture.world.state-path)))
  (same persisted.board captured)
  (assert (next after-tree))))

(add "logical deletion drops only source and incident visual connector" false (fn delete [fixture]
  (local service (start-world fixture))
  (local view (fixture.mount))
  (set fixture.world.runtime.board-view view)
  (local a (. view.item-records "a" :element))
  (local b (. view.item-records "b" :element))
  (local link (. view.connector-records "K" :line))
  (local bytes (fixture.stores.string-store:snapshot-entity "a"))
  (service:delete! "string-entity:s")
  (assert (= fixture.board.items.source nil))
  (assert (= (. view.item-records "source") nil))
  (assert (= (. view.item-records "a" :element) a))
  (assert (= (. view.item-records "b" :element) b))
  (assert (= (. view.connector-records "K" :line) link))
  (assert (= fixture.board.connectors.T nil))
  (assert (= (. view.connector-records "T") nil))
  (same (fixture.stores.string-store:snapshot-entity "a") bytes)))

(add "provider conflicts fail before rendering or writes" false (fn conflicts [fixture]
  (H.with-root (fn other-root [root]
    (local other (H.stores root))
    (local before (H.snapshot-tree fixture.stores.base-dir))
    (fn attempt [field value]
      (local opts {:board fixture.board :canvas fixture.canvas :link-store fixture.stores.link-store
                   :identity-store fixture.stores.identity-store :string-store fixture.stores.string-store})
      (tset opts field value)
      (BoardView opts))
    (H.assert-error "conflicts" #(attempt :identity-store other.identity-store))
    (H.assert-error "root mismatch" #(attempt :string-store other.string-store))
    (H.assert-error "root mismatch" #(attempt :code-store other.code-store))
    (same before (H.snapshot-tree fixture.stores.base-dir))))))

(add "drop disconnects source subscriptions and native buffers" false (fn cleanup [fixture]
  (local service (start-world fixture))
  (local view (fixture.mount))
  (local old (. view.item-records "source" :element :input))
  (local result (service:replace! "string-entity:s" {:name "" :source source-text :language "fnl" :kernel 0}))
  (old:on-text-input {:text "must not write retired string"})
  (assert (= (fixture.stores.string-store:get-entity "s") nil))
  (local text (. view.item-records "source" :element :text))
  (assert (= (text-value text) source-text))
  (view.layer.layout:measurer)
  (view.layer.layout:layouter)
  (view:drop)
  (table.remove fixture.owned)
  (local tree (H.snapshot-tree fixture.stores.base-dir))
  (fixture.stores.code-store:update-entity result.code-entity.id {:source "after drop"})
  (assert (= (text-value text) source-text) "dropped Text must not receive owning events")
  (H.assert-error "called after drop" #(view:update 0))
  (local draw (fixture.canvas.build-context:get-text-ssbo-draw-list))
  (assert (= (# draw) 0) "owned native text buffers must be released")
  (assert (next tree))))

(add "transform update retains native bodies and selection handles" false (fn transform [fixture]
  (local view (fixture.mount))
  (local record (. view.item-records "source"))
  (local body record.element)
  (local selectable record.selectable)
  (fixture.board:update-item-transform "source" {:position (glm.vec3 99 98 0) :size (glm.vec3 44 22 0)})
  (assert (= (. view.item-records "source") record))
  (assert (= record.element body))
  (assert (= record.selectable selectable))
  (view.layer.layout:measurer)
  (view.layer.layout:layouter)
  (assert (= body.layout.position.x 99))
  (assert (= body.layout.position.y 98))
  (assert (= body.layout.size.x 44))))

(add "ordinary world deactivation retains opaque owning rows" false (fn deactivate [fixture]
  (local service (start-world fixture))
  (local view (fixture.mount))
  (local world fixture.world)
  (set world.runtime.board-view view)
  (set world.state.board.opaque-root {:text "string-entity:s" :enabled false})
  (set (. world.state.board.items 1 :extension) {:text "string-entity:s" :enabled false})
  (set (. world.state.board.connectors 1 :extension) {:text "string-entity:s" :enabled false})
  (world:save-state)
  (service:replace! "string-entity:s" {:name "" :source source-text :language "fnl" :kernel 0})
  (local expected ((. (require :reference-lifecycle/record-utils) :clone) world.state.board))
  (local survivor (. view.item-records "a" :element))
  (world:deactivate {})
  (same world.state.board expected)
  (assert (= (. view.item-records "a" :element) survivor))
  (world:save-state)
  (local cold (HomeWorld {:id "loaded" :dir world.dir}))
  (cold:init {})
  (same cold.state.board expected)
  (local native (fixture.mount (Board {:state cold.state.board})))
  (assert (= (text-value (. native.item-records "source" :element :text)) source-text))))

;; Scene is only the activity-slot scaffold used by test-board. Board, Canvas,
;; native layouts, registry, stores and lifecycle remain real throughout.
(fn scene-slots []
  {:ensure-activity-slot (fn ensure [_self _id] {})
   :activate-activity-slot (fn activate [_self _id] {})
   :deactivate-activity-slot (fn deactivate [_self _id _opts] nil)
   :capture-activity-slot-state (fn capture [_self _id] {})
   :restore-activity-slot-state (fn restore [_self _id _state] true)})

(fn with-live-activity [fixture f]
  (local previous-runtime app.active-world-runtime)
  (local previous-canvas app.canvas)
  (local previous-board app.board)
  (local previous-view app.board-view)
  (local previous-id app.active-activity-id)
  (local previous-surface app.active-interaction-surface)
  (local s fixture.stores)
  (local runtime {:canvas fixture.canvas :scene (scene-slots)
                  :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}}
                  :board-state fixture.world.state.board :string-store s.string-store :code-store s.code-store
                  :identity-store s.identity-store :link-store s.link-store})
  (set app.active-world-runtime runtime)
  (set app.canvas fixture.canvas)
  (set app.active-activity-id nil)
  (local (ok result) (pcall (fn run [] (Activities.activate-activity "board") (f runtime))))
  (local (drop-ok drop-error) (pcall (fn cleanup []
    (BoardActivity.unload-board-activity!)
    (when runtime.board-view
      (local slot (fixture.canvas:activity-slot "board"))
      (when slot (set slot.root nil))
      (runtime.board-view:drop)
      (set runtime.board-view nil)))))
  (set app.active-world-runtime previous-runtime)
  (set app.canvas previous-canvas)
  (set app.board previous-board)
  (set app.board-view previous-view)
  (set app.active-activity-id previous-id)
  (set app.active-interaction-surface previous-surface)
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(add "activity composition retains code through native slot reactivation" false (fn activity [fixture]
  (local service (start-world fixture))
  (with-live-activity fixture (fn mounted [runtime]
    (set fixture.world.runtime runtime)
    (local view runtime.board-view)
    (assert (= view.string-store fixture.stores.string-store))
    (assert (= view.code-store fixture.stores.code-store))
    (assert (= view.identity-store fixture.stores.identity-store))
    (assert (= (: (. view.item-records "source" :element :input) :get-text) source-text))
    (service:replace! "string-entity:s" {:name "" :source source-text :language "fnl" :kernel 0})
    (local code (. view.item-records "source" :element))
    (local before (H.snapshot-tree fixture.stores.base-dir))
    (local snapshot (BoardActivity.snapshot-board-activity!))
    (same before (H.snapshot-tree fixture.stores.base-dir))
    (assert (= (. snapshot.board-state.items 1 :type) "code-entity"))
    (Activities.deactivate-active-activity)
    (assert (= runtime.board-view view) "native slot deactivation must retain owned view")
    (Activities.activate-activity "board")
    (assert (= runtime.board-view view))
    (assert (= (. view.item-records "source" :element) code))
    (assert (= (text-value code.text) source-text))
    (same before (H.snapshot-tree fixture.stores.base-dir))))))

(fn mount-ownership-view [fixture board providers]
  (local s fixture.stores)
  (local options {:board board :canvas fixture.canvas :ctx fixture.canvas.build-context
                  :identity-store s.identity-store :link-store s.link-store
                  :string-store s.string-store :code-store s.code-store})
  (each [field value (pairs providers)] (tset options field (if (= value false) nil value)))
  (local view (BoardView options))
  (table.insert fixture.owned view)
  (set fixture.world.runtime.board-view view)
  view)

(fn reject-composed-ownership [fixture service role]
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local board (fixture.board:capture-state))
  (local view fixture.world.runtime.board-view)
  (local visible (view:capture-state))
  (H.no-writes (fn reject []
    (local message (H.assert-error role #(service:start!)))
    (assert (string.find message fixture.world.dir 1 true) "ownership failure must identify world path")
    (H.assert-error role #(service:replace! "string-entity:s"
      {:name "" :source source-text :language "fnl" :kernel 0}))))
  (same before (H.snapshot-tree fixture.stores.base-dir))
  (same board (fixture.board:capture-state))
  (same visible (view:capture-state))
  (assert (= (service._pending:read) nil) "ownership mismatch must precede pending intent"))

(add "composed ownership rejects distinct native board before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local other (Board {:state (fixture.board:capture-state)}))
  (same (other:capture-state) (fixture.board:capture-state))
  (mount-ownership-view fixture other {})
  (reject-composed-ownership fixture service "board-view board instance mismatch")))

(add "composed ownership requires mounted native board before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (mount-ownership-view fixture fixture.board {})
  (set fixture.world.runtime.board nil)
  (reject-composed-ownership fixture service "board-view requires runtime.board")))

(add "composed ownership rejects same root code provider before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local s fixture.stores)
  (s.code-store:create-entity {:id "visible" :source source-text :name "" :language "fnl" :kernel 0})
  (local other ((. (require :entities/code) :CodeEntityStore) {:base-dir s.base-dir}))
  (fixture.board:add-item {:id "code" :type "code-entity" :subject-key "code-entity:visible"})
  (local view (mount-ownership-view fixture fixture.board {:code-store other}))
  (local body (. view.item-records "code" :element))
  (assert (= body.store other))
  (assert (= (text-value body.text) source-text))
  (other:update-entity "visible" {:source "alternate provider signal"})
  (assert (= (text-value body.text) "alternate provider signal"))
  (assert (not (= other s.code-store)))
  (reject-composed-ownership fixture service "board-view code-store instance mismatch")
  (view:drop) (table.remove fixture.owned)
  (other:update-entity "visible" {:source "after rejected composition and drop"})
  (assert (= (text-value body.text) "alternate provider signal") "dropped rejected view must disconnect actual provider")
  (assert (= (# (fixture.canvas.build-context:get-text-ssbo-draw-list)) 0))))

(add "composed ownership rejects configured unused code provider before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local other ((. (require :entities/code) :CodeEntityStore) {:base-dir fixture.stores.base-dir}))
  (mount-ownership-view fixture fixture.board {:code-store other})
  (reject-composed-ownership fixture service "board-view code-store instance mismatch")))

(add "composed ownership rejects same root string provider before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local other ((. (require :entities/string) :StringEntityStore) {:base-dir fixture.stores.base-dir}))
  (local view (mount-ownership-view fixture fixture.board {:string-store other}))
  (assert (= (: (. view.item-records "source" :element :input) :get-text) source-text))
  (reject-composed-ownership fixture service "board-view string-store instance mismatch")))

(add "composed ownership rejects same root link and identity providers before effects" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local s fixture.stores)
  (local link ((. (require :entities/link) :LinkEntityStore)
    {:base-dir s.base-dir :identity-store s.identity-store}))
  (local view (mount-ownership-view fixture fixture.board {:link-store link}))
  (reject-composed-ownership fixture service "board-view link-store instance mismatch")
  (view:drop) (table.remove fixture.owned)
  (local other (H.stores s.base-dir))
  (mount-ownership-view fixture fixture.board {:link-store other.link-store :identity-store other.identity-store})
  (reject-composed-ownership fixture service "board-view identity-store instance mismatch")))

(add "composed ownership canonical preflight leaves unused code unacquired" false (fn ownership [fixture]
  (local service (start-world fixture))
  (local view (mount-ownership-view fixture fixture.board {:code-store false}))
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local providers (H.no-writes #(view:reference-providers)))
  (assert (= providers.board fixture.board))
  (assert (= providers.code-store false) "unused code provider must remain unacquired")
  (assert (= providers.string-store fixture.stores.string-store))
  (assert (= providers.link-store fixture.stores.link-store))
  (assert (= providers.identity-store fixture.stores.identity-store))
  (H.no-writes (fn validate [] (service:start!) (service._owners.worlds:inventory)))
  (assert (= (. (view:reference-providers) :code-store) false))
  (set providers.string-store false)
  (assert (= (. (view:reference-providers) :string-store) fixture.stores.string-store))
  (same before (H.snapshot-tree fixture.stores.base-dir))))

(fn add-rollback [name f]
  (fn rooted [root]
    (local s (H.stores root))
    (s.string-store:create-entity {:id "keep" :value "preexisting"})
    (s.identity-store:create-entity {:id "keep" :target-key "string-entity:keep"})
    (local board (Board {}))
    (board:add-item {:id "keep" :type "string-entity" :subject-key "identity:keep"})
    (f s board))
  (table.insert tests {:name (.. "reference lifecycle composition Board rollback " name)
                       :fn #(H.with-root rooted)}))

(fn rollback-state [s board]
  {:tree (H.snapshot-tree s.base-dir) :board (board:capture-state)})
(fn rollback-options [s entity]
  {:string-store s.string-store :identity-store s.identity-store :value "attempt"
   :entity entity :position [math.huge 0 0]})
(fn rejected-signal [signal f]
  (local handler (signal:connect (fn reject [_record] (error "creation listener failed"))))
  (local (ok result) (pcall f))
  (signal:disconnect handler true)
  (if ok result (error result)))

(add-rollback "invalid transform restores owning records" (fn invalid [s board]
  (local before (rollback-state s board))
  (H.assert-error "finite" #(BuiltinString.create-string-entity board (rollback-options s nil)))
  (same before (rollback-state s board))))

(add-rollback "item-added failure restores owning records" (fn listener [s board]
  (local before (rollback-state s board))
  (local options (rollback-options s nil))
  (set options.position [0 0 0])
  (fn create [] (H.assert-error "creation listener failed" #(BuiltinString.create-string-entity board options)))
  (rejected-signal board.item-added create)
  (same before (rollback-state s board))))

(add-rollback "identity enumeration failure retires new string" (fn enumeration [s board]
  (local before (rollback-state s board))
  (fn create [] (H.assert-error "permission denied" #(BuiltinString.create-string-entity board (rollback-options s nil))))
  (H.with-fs-failure :list-dir s.identity-store.entities-dir create)
  (same before (rollback-state s board))))

(add-rollback "identity write failure retires new string" (fn write-failure [s board]
  (local before (rollback-state s board))
  (local write fs.write-file)
  (fn reject [path bytes]
    (if (= (fs.parent path) s.identity-store.entities-dir) (error "identity write denied") (write path bytes)))
  (fn create [] (H.assert-error "identity write denied" #(BuiltinString.create-string-entity board (rollback-options s nil))))
  (H.with-fields fs {:write-file reject} create)
  (same before (rollback-state s board))))

(add-rollback "supplied string survives new identity rollback" (fn supplied [s board]
  (local entity (s.string-store:create-entity {:id "supplied" :value "supplied"}))
  (local before (rollback-state s board))
  (H.assert-error "finite" #(BuiltinString.create-string-entity board (rollback-options s entity)))
  (assert (= (s.string-store:get-entity "supplied") entity))
  (same before (rollback-state s board))))

(add-rollback "reused identity and supplied string survive" (fn reused [s board]
  (local entity (s.string-store:get-entity "keep"))
  (local identity (s.identity-store:get-entity "keep"))
  (local before (rollback-state s board))
  (H.assert-error "finite" #(BuiltinString.create-string-entity board (rollback-options s entity)))
  (assert (= (s.string-store:get-entity "keep") entity))
  (assert (= (s.identity-store:get-entity "keep") identity))
  (same before (rollback-state s board))))

(add-rollback "identity publication failure restores owning records" (fn publication [s board]
  (local before (rollback-state s board))
  (fn create [] (H.assert-error "creation listener failed" #(BuiltinString.create-string-entity board (rollback-options s nil))))
  (rejected-signal s.identity-store.identity-created create)
  (same before (rollback-state s board))))

(add-rollback "cleanup failure is explicit and reference safe" (fn cleanup-failure [s board]
  (local before (rollback-state s board))
  (var created-string nil) (var created-identity nil)
  (s.string-store.string-entity-created:connect (fn observe [record] (set created-string record)))
  (s.identity-store.identity-created:connect (fn observe [record] (set created-identity record)))
  (local remove fs.remove)
  (fn reject [path]
    (if (= (fs.parent path) s.identity-store.entities-dir) (error "identity rollback denied") (remove path)))
  (fn create []
    (local message (H.assert-error "rollback failed" #(BuiltinString.create-string-entity board (rollback-options s nil))))
    (assert (string.find message "identity rollback denied" 1 true)))
  (H.with-fields fs {:remove reject} create)
  (assert (s.string-store:get-entity created-string.id) "failed identity cleanup must not dangle its target")
  (assert (= (s.identity-store:get-entity created-identity.id) created-identity))
  (assert (= created-identity.target-key (.. "string-entity:" created-string.id)))
  (local after (rollback-state s board))
  (same before.board after.board)
  (each [path bytes (pairs before.tree)] (assert (= (. after.tree path) bytes)))))

{:tests tests :main (fn [] ((. (require :tests/runner) :run) tests))}
