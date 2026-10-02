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

(table.insert tests {:name "SnackbarManager.show requires content"
                     :fn show-requires-content})
(table.insert tests {:name "SnackbarManager normalizes message to text"
                     :fn message-normalizes-to-text})
(table.insert tests {:name "SnackbarManager preserves explicit ids"
                     :fn explicit-id-is-preserved})
(table.insert tests {:name "SnackbarManager generates stable string ids"
                     :fn generated-ids-are-stable-strings})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "snackbar-manager"
                     :tests tests}))

{:main main}
