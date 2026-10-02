(local SnackbarManager (require :snackbar-manager))
(local SnackbarHost (require :snackbar-host))
(local SnackbarTheme (require :snackbar-theme))

(fn current-context-snackbar-theme? [ctx]
  (and ctx ctx.theme ctx.theme.snackbar))

(fn make-host-options [manager options scope-theme ctx]
  {:manager manager
   :theme (if (current-context-snackbar-theme? ctx) nil scope-theme)
   :placement options.placement
   :spacing options.spacing
   :max-width options.max-width
   :content-builder options.content-builder})

(fn make-host-builder [manager options scope-theme]
  (fn build [ctx]
    ((SnackbarHost (make-host-options manager options scope-theme ctx)) ctx)))

(fn scope-theme-overrides [options]
  (local overrides {})
  (each [key value (pairs options)]
    (when (and (not (= key :theme))
               (not (= key :content-builder)))
      (set (. overrides key) value)))
  overrides)

(fn create-scope [opts]
  (local options (if opts opts {}))
  (local scope-theme (SnackbarTheme.resolve options.theme (scope-theme-overrides options)))
  (local manager (SnackbarManager scope-theme))
  (local host-builder (make-host-builder manager options scope-theme))
  (local scope {:manager manager
                :host-builder host-builder
                :dropped? false})
  (set scope.drop
       (fn [self]
         (when (not self.dropped?)
           (manager:drop)
           (set self.dropped? true))
         true))
  scope)

{:SnackbarManager SnackbarManager
 :SnackbarHost SnackbarHost
 :SnackbarTheme SnackbarTheme
 :create-scope create-scope}
