(local SnackbarManager (require :snackbar-manager))
(local SnackbarHost (require :snackbar-host))
(local SnackbarTheme (require :snackbar-theme))

(fn create-scope [opts]
  (local options (if opts opts {}))
  (local manager (SnackbarManager options))
  (local host-builder (SnackbarHost {:manager manager
                                     :theme options.theme
                                     :placement options.placement
                                     :spacing options.spacing
                                     :max-width options.max-width
                                     :content-builder options.content-builder}))
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
