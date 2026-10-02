(local tests [])
(local SnackbarManager (require :snackbar-manager))

(fn assert-error-contains [body expected]
  (local (ok err) (pcall body))
  (assert (not ok) "Expected function to fail")
  (assert (and (= (type err) :string)
               (string.find err expected 1 true))
          (.. "Expected error to contain '" expected "', got '" (tostring err) "'")))

(fn show-requires-content []
  (local manager (SnackbarManager))
  (assert-error-contains
    (fn []
      (manager:show {}))
    "SnackbarManager.show requires :text, :message, or :content-builder")
  (manager:drop))

(fn message-normalizes-to-text []
  (local manager (SnackbarManager))
  (local handle (manager:show {:message "Saved"}))
  (assert (= handle.entry.text "Saved") "message should normalize to entry.text")
  (manager:drop))

(fn explicit-id-is-preserved []
  (local manager (SnackbarManager))
  (local handle (manager:show {:id "custom" :text "Saved"}))
  (assert (= handle.id "custom") "handle.id should preserve explicit id")
  (assert (= handle.entry.id "custom") "entry.id should preserve explicit id")
  (manager:drop))

(fn generated-ids-are-stable-strings []
  (local manager (SnackbarManager))
  (local first (manager:show {:text "First"}))
  (local second (manager:show {:text "Second"}))
  (assert (= first.id "snackbar-1") "first generated id should be snackbar-1")
  (assert (= second.id "snackbar-2") "second generated id should be snackbar-2")
  (manager:drop))

(fn duplicate-explicit-id-is-rejected []
  (local manager (SnackbarManager))
  (manager:show {:id "custom" :text "First"})
  (assert-error-contains
    (fn []
      (manager:show {:id "custom" :text "Second"}))
    "SnackbarManager.show duplicate live id: custom")
  (assert (= (length (manager:visible-entries)) 1) "duplicate id should not add another visible entry")
  (manager:drop))

(fn text-snackbar-preserves-action-descriptors []
  (local manager (SnackbarManager))
  (local clicked (fn [_entry _handle _button _event] true))
  (local request-action {:label "Undo"
                         :button-variant :text
                         :on-click clicked})
  (local handle (manager:show {:text "Saved"
                               :actions [request-action]}))
  (local action (. handle.entry.actions 1))
  (assert (= handle.entry.text "Saved") "entry text should be preserved with actions")
  (assert (= (length handle.entry.actions) 1) "entry should preserve one action descriptor")
  (assert (= action.label "Undo") "action label should be preserved")
  (assert (= action.button-variant :text) "action button variant should be preserved")
  (assert (= action.on-click clicked) "action callback should be preserved")
  (assert (not (= action request-action)) "action descriptor should be copied")
  (set request-action.label "Changed")
  (assert (= action.label "Undo") "entry action should not change when request action mutates")
  (local visible-action (. (. (. (manager:visible-entries) 1) :actions) 1))
  (assert (= visible-action.label "Undo") "visible entries should include copied actions for hosts")
  (manager:drop))

(table.insert tests {:name "SnackbarManager.show requires content"
                     :fn show-requires-content})
(table.insert tests {:name "SnackbarManager normalizes message to text"
                     :fn message-normalizes-to-text})
(table.insert tests {:name "SnackbarManager preserves explicit ids"
                     :fn explicit-id-is-preserved})
(table.insert tests {:name "SnackbarManager generates stable string ids"
                      :fn generated-ids-are-stable-strings})
(table.insert tests {:name "SnackbarManager rejects duplicate explicit ids"
                     :fn duplicate-explicit-id-is-rejected})
(table.insert tests {:name "SnackbarManager preserves text action descriptors"
                     :fn text-snackbar-preserves-action-descriptors})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "snackbar-manager"
                     :tests tests}))

{:main main}
