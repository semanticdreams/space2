(local Keymap (require :commands/keymap))
(local Commands (require :commands/core))

(local tests [])

(fn add-test [name f]
  (table.insert tests {:name name :fn f}))

(fn keymap-resolves-prefix-command-and-missing-sequences []
  (local tree (Keymap.build [{:keys ["g" "p" "e"]
                              :command "graph.preview.expand-selected"
                              :label "expand-preview"
                              :priority 10}
                             {:keys ["q"]
                              :command "core.quit"
                              :label "quit"
                              :priority 20}]))
  (local g (Keymap.resolve tree ["g"]))
  (assert (= g.kind :prefix) "g should resolve as a prefix")
  (local gpe (Keymap.resolve tree ["g" "p" "e"]))
  (assert (= gpe.kind :command) "g p e should resolve to command")
  (assert (= gpe.command-id "graph.preview.expand-selected"))
  (local missing (Keymap.resolve tree ["x"]))
  (assert (= missing.kind :missing) "unknown sequence should be missing"))

(var ran-demo-command 0)

(fn demo-available? [ctx]
  (= ctx.allowed? true))

(fn run-demo [_ctx]
  (set ran-demo-command (+ ran-demo-command 1))
  true)

(fn commands-execute-only-available-commands []
  (set ran-demo-command 0)
  (local provider {:commands {"demo.run" {:id "demo.run"
                                           :label "run-demo"
                                           :available? demo-available?
                                           :run run-demo}}
                   :bindings [{:keys ["d"]
                               :command "demo.run"
                               :label "run-demo"
                               :priority 10}]})
  (local composed (Commands.compose [provider] {:allowed? false}))
  (assert (not (Commands.run composed "demo.run" {:allowed? false}))
          "Unavailable command should not run")
  (assert (= ran-demo-command 0) "Unavailable command should not mutate")
  (assert (Commands.run composed "demo.run" {:allowed? true})
          "Available command should run")
  (assert (= ran-demo-command 1) "Available command should mutate once"))

(fn always-run [_ctx]
  true)

(fn unavailable? [_ctx]
  false)

(local graph-provider-test-view {:selected-node-count (fn [_self] 1)})

(fn selected-graph-view []
  graph-provider-test-view)

(fn make-graph-selection-test-view [opts]
  (local options (assert opts "make-graph-selection-test-view requires opts"))
  (local calls {:select 0
                :add 0
                :remove 0
                :toggle 0
                :clear 0})
  (local view {:calls calls
               :selected-node-count (fn [_self]
                                      (assert (not (= options.selected-count nil))
                                              "make-graph-selection-test-view requires selected-count")
                                      options.selected-count)})
  (set view.has-focused-node?
       (fn [_self] (= options.focused? true)))
  (set view.focused-node-selected?
       (fn [_self] (= options.focused-selected? true)))
  (set view.select-focused-node-only
       (fn [_self] (set calls.select (+ calls.select 1)) true))
  (set view.add-focused-node-to-selection
       (fn [_self] (set calls.add (+ calls.add 1)) true))
  (set view.remove-focused-node-from-selection
       (fn [_self] (set calls.remove (+ calls.remove 1)) true))
  (set view.toggle-focused-node-selection
       (fn [_self] (set calls.toggle (+ calls.toggle 1)) true))
  (set view.clear-selection
       (fn [_self] (set calls.clear (+ calls.clear 1)) true))
  view)

(fn find-hint-entry [section key]
  (assert section "find-hint-entry requires section")
  (assert section.entries "find-hint-entry requires section entries")
  (var found nil)
  (each [_ entry (ipairs section.entries)]
    (when (= entry.key key)
      (set found entry)))
  found)

(fn assert-hint [section key label]
  (local entry (find-hint-entry section key))
  (assert entry (string.format "Expected hint %s" key))
  (assert (= entry.label label)
          (string.format "Expected hint %s label %s" key label)))

(fn graph-selection-composed [view]
  (local GraphCommands (require :graph/commands))
  (fn graph-view-resolver [] view)
  (Commands.compose [(GraphCommands.provider {:graph-view graph-view-resolver})] {}))

(fn command-hints-derive-from-availability-and-prefix []
  (local provider {:commands {"demo.a" {:id "demo.a"
                                          :label "alpha"
                                          :run always-run}
                             "demo.b" {:id "demo.b"
                                         :label "beta"
                                         :available? unavailable?
                                         :run always-run}}
                    :prefixes [{:keys ["g"] :label "graph" :priority 10}]
                    :bindings [{:keys ["g" "a"] :command "demo.a" :label "alpha" :priority 20}
                               {:keys ["g" "b"] :command "demo.b" :label "beta" :priority 10}]})
  (local composed (Commands.compose [provider] {}))
  (local root-section (Commands.hint-section composed [] {} {:id :mode :title "MODE"}))
  (assert root-section "Root hint section should exist")
  (assert (= (. root-section.entries 1 :key) "g"))
  (assert (= (. root-section.entries 1 :label) "graph"))
  (local section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert section "Prefix hint section should exist")
  (assert (= (length section.entries) 1) "Unavailable command should be hidden")
  (assert (= (. section.entries 1 :key) "a"))
  (assert (= (. section.entries 1 :label) "alpha")))

(fn graph-provider-prefix-hints-use-prefix-labels []
  (local GraphCommands (require :graph/commands))
  (local provider (GraphCommands.provider {:graph-view selected-graph-view}))
  (local composed (Commands.compose [provider] {}))
  (local root-section (Commands.hint-section composed [] {} {:id :mode :title "MODE"}))
  (assert root-section "Graph provider root hint section should exist")
  (assert (= (. root-section.entries 1 :key) "g"))
  (assert (= (. root-section.entries 1 :label) "graph"))
  (local graph-section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert graph-section "Graph provider nested hint section should exist")
  (assert (= (. graph-section.entries 1 :key) "p"))
  (assert (= (. graph-section.entries 1 :label) "preview")))

(fn graph-provider-selection-prefix-hints-include-selection-commands []
  (local composed (graph-selection-composed (make-graph-selection-test-view {:selected-count 1
                                                                             :focused? true
                                                                             :focused-selected? true})))
  (local graph-section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert graph-section "Graph provider graph hints should exist")
  (assert-hint graph-section "p" "preview")
  (assert-hint graph-section "s" "selection")
  (local selection-section (Commands.hint-section composed ["g" "s"] {} {:id :mode :title "MODE"}))
  (assert selection-section "Graph provider selection hints should exist")
  (assert-hint selection-section "s" "select")
  (assert-hint selection-section "a" "add")
  (assert-hint selection-section "r" "remove")
  (assert-hint selection-section "t" "toggle")
  (assert-hint selection-section "c" "clear"))

(fn graph-provider-selection-availability-follows-focus-and-selection []
  (local no-focus (graph-selection-composed (make-graph-selection-test-view {:selected-count 0
                                                                             :focused? false
                                                                             :focused-selected? false})))
  (assert (not (Commands.available? no-focus "graph.selection.select-focused" {})))
  (assert (not (Commands.available? no-focus "graph.selection.add-focused" {})))
  (assert (not (Commands.available? no-focus "graph.selection.remove-focused" {})))
  (assert (not (Commands.available? no-focus "graph.selection.toggle-focused" {})))
  (local focused-empty (graph-selection-composed (make-graph-selection-test-view {:selected-count 0
                                                                                 :focused? true
                                                                                 :focused-selected? false})))
  (assert (Commands.available? focused-empty "graph.selection.select-focused" {}))
  (assert (Commands.available? focused-empty "graph.selection.add-focused" {}))
  (assert (not (Commands.available? focused-empty "graph.selection.remove-focused" {})))
  (assert (Commands.available? focused-empty "graph.selection.toggle-focused" {}))
  (assert (not (Commands.available? focused-empty "graph.selection.clear" {})))
  (local focused-selected (graph-selection-composed (make-graph-selection-test-view {:selected-count 1
                                                                                    :focused? true
                                                                                    :focused-selected? true})))
  (assert (Commands.available? focused-selected "graph.selection.select-focused" {}))
  (assert (Commands.available? focused-selected "graph.selection.add-focused" {}))
  (assert (Commands.available? focused-selected "graph.selection.remove-focused" {}))
  (assert (Commands.available? focused-selected "graph.selection.toggle-focused" {}))
  (assert (Commands.available? focused-selected "graph.selection.clear" {})))

(fn graph-provider-selection-commands-run-view-methods []
  (local view (make-graph-selection-test-view {:selected-count 1
                                               :focused? true
                                               :focused-selected? true}))
  (local composed (graph-selection-composed view))
  (local ids ["graph.selection.select-focused"
              "graph.selection.add-focused"
              "graph.selection.remove-focused"
              "graph.selection.toggle-focused"
              "graph.selection.clear"])
  (local fields [:select :add :remove :toggle :clear])
  (each [index id (ipairs ids)]
    (local before {})
    (each [_ field (ipairs fields)]
      (set (. before field) (. view.calls field)))
    (assert (Commands.run composed id {}) (string.format "%s should run" id))
    (each [field-index field (ipairs fields)]
      (local expected (if (= field-index index)
                          (+ (. before field) 1)
                          (. before field)))
      (assert (= (. view.calls field) expected)
               (string.format "%s should update only matching counter" id)))))

(fn expanded-action-noop [])

(fn expanded-focused-actions []
  [{:name "one" :fn expanded-action-noop}
   {:name "two" :fn expanded-action-noop}
   {:name "three" :fn expanded-action-noop}])

(fn make-expanded-graph-view-stub [opts]
  (local options (if opts opts {}))
  (local calls {:open 0 :menu 0 :toggle 0 :copy 0 :remove 0 :slot [] :center 0 :layout 0})
  {:calls calls
    :selected-node-count (fn [_self] 1)
    :has-focused-node? (fn [_self] true)
    :focused-node (fn [_self] options.focused-node)
    :focused-node-selected? (fn [_self] true)
   :open-focused-node (fn [_self] (set calls.open (+ calls.open 1)) true)
   :open-focused-node-menu (fn [_self] (set calls.menu (+ calls.menu 1)) true)
   :toggle-focused-node-preview (fn [_self] (set calls.toggle (+ calls.toggle 1)) true)
   :copy-focused-node-key (fn [_self] (set calls.copy (+ calls.copy 1)) true)
   :remove-focused-node-from-map (fn [_self] (set calls.remove (+ calls.remove 1)) true)
   :focused-node-actions (fn [_self] (expanded-focused-actions))
   :run-focused-node-action-slot (fn [_self index]
                                   (table.insert calls.slot index)
                                   true)
   :reveal-focused-node (fn [_self] (set calls.center (+ calls.center 1)) true)
   :start-layout (fn [_self] (set calls.layout (+ calls.layout 1)) true)})

(fn default-expanded-map-options [opts]
  (if opts opts {}))

(fn selected-node-keys-for-expanded-map [options]
  (if options.selected-node-keys options.selected-node-keys ["focus"]))

(fn make-expanded-map-stub [opts]
  (local options (default-expanded-map-options opts))
  (local calls {:add-start 0 :clear 0 :capture 0})
  {:calls calls
   :selected_node_keys (selected-node-keys-for-expanded-map options)
   :focused_node_key options.focused-node-key
   :add-start-node! (fn [_self]
                      (set calls.add-start (+ calls.add-start 1))
                      true)
   :clear! (fn [_self]
             (set calls.clear (+ calls.clear 1))
             true)
    :clearable? (fn [_self] (= options.clearable? true))
    :capture-selected-subgraph-state (fn [_self capture-opts]
                                       (set calls.capture (+ calls.capture 1))
                                       {:captured-focus (if capture-opts.focused-node-key-provided?
                                                           capture-opts.focused-node-key
                                                           options.focused-node-key)})})

(fn make-expanded-manager-stub []
  (local calls {:create []})
  {:calls calls
   :create-and-switch-map! (fn [_self opts]
                             (table.insert calls.create opts)
                             true)})

(var expanded-resolver-view nil)
(var expanded-resolver-map nil)
(var expanded-resolver-manager nil)

(fn resolve-expanded-view [] expanded-resolver-view)
(fn resolve-expanded-map [] expanded-resolver-map)
(fn resolve-expanded-manager [] expanded-resolver-manager)

(fn expanded-graph-composed [view graph-map manager]
  (local GraphCommands (require :graph/commands))
  (set expanded-resolver-view view)
  (set expanded-resolver-map graph-map)
  (set expanded-resolver-manager manager)
  (Commands.compose [(GraphCommands.provider {:graph-view resolve-expanded-view
                                               :graph-map resolve-expanded-map
                                               :graph-map-manager resolve-expanded-manager})]
                    {}))

(fn graph-provider-prefix-hints-include-expanded-namespaces []
  (local view (make-expanded-graph-view-stub))
  (local graph-map (make-expanded-map-stub {:focused-node-key "focus" :clearable? true}))
  (local manager (make-expanded-manager-stub))
  (local composed (expanded-graph-composed view graph-map manager))
  (local graph-section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert graph-section "Graph provider graph hints should exist")
  (assert-hint graph-section "p" "preview")
  (assert-hint graph-section "s" "selection")
  (assert-hint graph-section "n" "node")
  (assert-hint graph-section "v" "view")
  (assert-hint graph-section "m" "map"))

(fn graph-provider-node-commands-route-to-graph-view []
  (local view (make-expanded-graph-view-stub))
  (local composed (expanded-graph-composed view (make-expanded-map-stub {:focused-node-key "focus"}) (make-expanded-manager-stub)))
  (each [_ id (ipairs ["graph.node.open-focused"
                       "graph.node.menu-focused"
                       "graph.node.toggle-focused-preview"
                       "graph.node.copy-focused-key"
                       "graph.node.remove-focused-from-map"
                       "graph.node.action-3"])]
    (assert (Commands.run composed id {}) (.. id " should run")))
  (assert (= view.calls.open 1) "open command should route once")
  (assert (= view.calls.menu 1) "menu command should route once")
  (assert (= view.calls.toggle 1) "toggle command should route once")
  (assert (= view.calls.copy 1) "copy command should route once")
  (assert (= view.calls.remove 1) "remove command should route once")
  (assert (= (. view.calls.slot 1) 3) "action-3 should pass slot index 3"))

(fn graph-provider-view-commands-route-to-graph-view []
  (local view (make-expanded-graph-view-stub))
  (local composed (expanded-graph-composed view (make-expanded-map-stub {:focused-node-key "focus"}) (make-expanded-manager-stub)))
  (assert (Commands.run composed "graph.view.center-focused" {}) "center-focused should run")
  (assert (Commands.run composed "graph.view.start-layout" {}) "start-layout should run")
  (assert (= view.calls.center 1) "center-focused should reveal focused node")
  (assert (= view.calls.layout 1) "start-layout should route to graph view"))

(fn graph-provider-map-commands-route-to-active-map-and-manager []
  (local view (make-expanded-graph-view-stub {:focused-node {:key "current-focus"}}))
  (local graph-map (make-expanded-map-stub {:focused-node-key "stale-focus" :clearable? true}))
  (local manager (make-expanded-manager-stub))
  (local composed (expanded-graph-composed view graph-map manager))
  (assert (Commands.run composed "graph.map.add-start" {}) "add-start should run")
  (assert (= graph-map.calls.add-start 1) "add-start should route to active map")
  (assert (Commands.run composed "graph.map.new-empty" {}) "new-empty should run")
  (assert (= (. manager.calls.create 1 :name) nil) "new-empty should pass nil name")
  (assert (= (. manager.calls.create 1 :state) nil) "new-empty should pass no state")
  (assert (Commands.run composed "graph.map.from-selection" {}) "from-selection should run")
  (assert (= graph-map.calls.capture 1) "from-selection should capture active map selection")
  (assert (= (. manager.calls.create 2 :name) "Selection") "from-selection should name new map")
  (assert (= (. manager.calls.create 2 :state :captured-focus) "current-focus")
          "from-selection should pass current graph view focused key")
  (assert (Commands.run composed "graph.map.clear-active" {}) "clear-active should run")
  (assert (= graph-map.calls.clear 1) "clear-active should route to active map")
  (assert (not (Commands.available? (expanded-graph-composed nil graph-map manager) "graph.map.add-start" {}))
          "map commands should require graph view")
  (assert (not (Commands.available? (expanded-graph-composed view nil manager) "graph.map.add-start" {}))
          "add-start should require active map")
  (assert (not (Commands.available? (expanded-graph-composed view graph-map nil) "graph.map.new-empty" {}))
          "new-empty should require manager")
  (assert (not (Commands.available? (expanded-graph-composed view (make-expanded-map-stub {:selected-node-keys [] :focused-node-key "focus"}) manager) "graph.map.from-selection" {}))
          "from-selection should require selection")
  (local selection-only-map (make-expanded-map-stub {:selected-node-keys ["selected"]
                                                     :focused-node-key "stale-focus"}))
  (assert (Commands.available? (expanded-graph-composed (make-expanded-graph-view-stub) selection-only-map manager) "graph.map.from-selection" {})
          "from-selection should be available for selection without focus")
  (assert (Commands.run (expanded-graph-composed (make-expanded-graph-view-stub) selection-only-map manager) "graph.map.from-selection" {})
          "from-selection should run for selection without focus")
  (assert (= (. manager.calls.create 3 :state :captured-focus) nil)
          "from-selection should not pass stale map focus when graph view has no focused node")
  (assert (not (Commands.available? (expanded-graph-composed view (make-expanded-map-stub {:focused-node-key "focus" :clearable? false}) manager) "graph.map.clear-active" {}))
          "clear-active should require clearable map"))

(fn command-hints-hide-prefixes-without-available-descendants []
  (local provider {:commands {"demo.deep" {:id "demo.deep"
                                            :label "deep"
                                            :available? unavailable?
                                            :run always-run}}
                   :bindings [{:keys ["g" "p" "e"]
                               :command "demo.deep"
                               :label "deep"
                               :priority 10}]})
  (local composed (Commands.compose [provider] {}))
  (local root-section (Commands.hint-section composed [] {} {:id :mode :title "MODE"}))
  (local graph-section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert (not root-section) "Root prefix with only unavailable descendants should be hidden")
  (assert (not graph-section) "Nested prefix with only unavailable descendants should be hidden"))

(add-test "Keymap resolves prefix command and missing sequences"
          keymap-resolves-prefix-command-and-missing-sequences)
(add-test "Commands execute only available commands"
          commands-execute-only-available-commands)
(add-test "Command hints derive from availability and prefix"
          command-hints-derive-from-availability-and-prefix)
(add-test "Graph provider prefix hints use prefix labels"
          graph-provider-prefix-hints-use-prefix-labels)
(add-test "Graph provider selection prefix hints include selection commands"
          graph-provider-selection-prefix-hints-include-selection-commands)
(add-test "Graph provider selection availability follows focus and selection"
          graph-provider-selection-availability-follows-focus-and-selection)
(add-test "Graph provider selection commands run view methods"
           graph-provider-selection-commands-run-view-methods)
(add-test "Graph provider prefix hints include expanded namespaces"
          graph-provider-prefix-hints-include-expanded-namespaces)
(add-test "Graph provider node commands route to graph view"
          graph-provider-node-commands-route-to-graph-view)
(add-test "Graph provider view commands route to graph view"
          graph-provider-view-commands-route-to-graph-view)
(add-test "Graph provider map commands route to active map and manager"
          graph-provider-map-commands-route-to-active-map-and-manager)
(add-test "Command hints hide prefixes without available descendants"
          command-hints-hide-prefixes-without-available-descendants)

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "commands" :tests tests})))

{:name "commands" :tests tests :main main}
