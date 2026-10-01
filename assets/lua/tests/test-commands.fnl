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

(fn command-hints-derive-from-availability-and-prefix []
  (local provider {:commands {"demo.a" {:id "demo.a"
                                         :label "alpha"
                                         :run always-run}
                             "demo.b" {:id "demo.b"
                                         :label "beta"
                                         :available? unavailable?
                                         :run always-run}}
                   :bindings [{:keys ["g" "a"] :command "demo.a" :label "alpha" :priority 20}
                              {:keys ["g" "b"] :command "demo.b" :label "beta" :priority 10}]})
  (local composed (Commands.compose [provider] {}))
  (local section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
  (assert section "Prefix hint section should exist")
  (assert (= (length section.entries) 1) "Unavailable command should be hidden")
  (assert (= (. section.entries 1 :key) "a"))
  (assert (= (. section.entries 1 :label) "alpha")))

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
(add-test "Command hints hide prefixes without available descendants"
          command-hints-hide-prefixes-without-available-descendants)

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "commands" :tests tests})))

{:name "commands" :tests tests :main main}
