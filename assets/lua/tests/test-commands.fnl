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
(add-test "Command hints hide prefixes without available descendants"
          command-hints-hide-prefixes-without-available-descendants)

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "commands" :tests tests})))

{:name "commands" :tests tests :main main}
