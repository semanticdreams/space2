(global app (or app {}))

(local Signal (require :signal))
(fn emit-activity-dock-changed! [reason previous current] (when (and app.activity-dock-changed (not (= previous current))) (app.activity-dock-changed:emit {:reason reason :previous-left-dock-builder previous :current-left-dock-builder current})) current)
(local persisted-activity-migrations {})

(fn clone-list [items]
  (icollect [_ item (ipairs (or items []))]
    item))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn noop-deactivate [_ctx _session]
  true)

(fn noop-snapshot [_ctx _session]
  nil)

(fn noop-restore [_ctx _session _state]
  true)

(fn ensure-registry []
  (when (not app.activity-registry)
    (set app.activity-registry
         {:activities {}
          :ordered-ids []
          :global-sessions {}
          :sessions {}
          :active-activity-id nil
          :activating-activity-id nil
          :active-activity-spec nil
          :active-activity-session nil
          :suppress-workspace-shell-change? false}))
  (set app.activity-registry.global-sessions
       (or app.activity-registry.global-sessions app.activity-registry.sessions {}))
  (if app.active-world-runtime
      (do
        (set app.active-world-runtime.activity-sessions
              (or app.active-world-runtime.activity-sessions {}))
        (set app.active-world-runtime.activity-session-state
             (or app.active-world-runtime.activity-session-state {}))
        (set app.activity-registry.sessions app.active-world-runtime.activity-sessions))
      (set app.activity-registry.sessions app.activity-registry.global-sessions))
  app.activity-registry)

(fn set-activating-activity! [registry activity-id]
  (set registry.activating-activity-id activity-id)
  (when app.active-world-runtime
    (set app.active-world-runtime.activating-activity-id activity-id))
  true)

(fn with-activating-activity [registry activity-id f]
  (local previous-registry-id registry.activating-activity-id)
  (local runtime app.active-world-runtime)
  (local previous-runtime-id (and runtime runtime.activating-activity-id))
  (set-activating-activity! registry activity-id)
  (local (ok result) (pcall f))
  (set registry.activating-activity-id previous-registry-id)
  (when runtime
    (set runtime.activating-activity-id previous-runtime-id))
  (if ok result (error result)))

(fn pending-session-state [activity-id]
  (and app.active-world-runtime
       app.active-world-runtime.activity-session-state
       (. app.active-world-runtime.activity-session-state activity-id)))

(fn clear-pending-session-state! [activity-id]
  (when (and app.active-world-runtime
             app.active-world-runtime.activity-session-state)
    (set (. app.active-world-runtime.activity-session-state activity-id) nil))
  true)

(fn activity-registered? [activity-id]
  (local registry (ensure-registry))
  (and (= (type activity-id) :string)
       (not (= activity-id ""))
       (. registry.activities activity-id)))

(fn clear-activity-runtime-hooks! [] (local previous-left-dock-builder app.activity-left-dock-builder)
  (set app.activity-root-actions nil)
  (set app.activity-selection-actions nil)
  (set app.activity-left-dock-builder nil)
  (set app.activity-command-hints-provider nil) (set app.activity-leader-command-providers nil)
  (set app.activity-delete-selection nil)
  (set app.activity-activate-focused nil)
  (set app.activity-drawing-enabled? nil)
  (set app.activity-context-enricher nil)
  (set app.activity-input-handlers nil)
  (set app.activity-target-enabled? nil)
  (set app.activity-update nil)
  (set app.activity-preferred-interaction-surface nil)
  (set app.activity-surface-state nil)
  (set app.activity-top-toolbar-builder nil)
  (set app.activity-object-drag-mode-provider nil)
  (set app.canvas-surface-interactive? true)
  (emit-activity-dock-changed! "activity-hooks" previous-left-dock-builder nil) true)

(fn empty-activity-hooks []
  {:root-actions nil
   :selection-actions nil
    :left-dock-builder nil
    :command-hints-provider nil :leader-command-providers nil
    :delete-selection nil
   :activate-focused nil
   :drawing-enabled? nil
   :context-enricher nil
   :input-handlers nil
   :target-enabled? nil
   :update nil
   :preferred-interaction-surface nil
   :surface-state nil
   :top-toolbar-builder nil
   :object-drag-mode-provider nil})

(fn apply-activity-surface-policy! [hooks]
  (local surface-state hooks.surface-state)
  (local preferred-surface
    (or hooks.preferred-interaction-surface
        (and surface-state (. surface-state :preferred-interaction-surface))))
  (set app.activity-preferred-interaction-surface preferred-surface)
  (set app.activity-surface-state surface-state)
  (local canvas-state (and surface-state surface-state.canvas))
  (when (and canvas-state (not (= (. canvas-state :interactive?) nil)))
    (set app.canvas-surface-interactive?
         (not (= (. canvas-state :interactive?) false))))
  (when (and canvas-state (not (= (. canvas-state :visible?) nil)))
    (if app.set-canvas-visible
        (app.set-canvas-visible (. canvas-state :visible?))
        (set app.canvas-visible? (and app.canvas
                                      (not (= (. canvas-state :visible?) false))))))
  (when preferred-surface
    (if app.set-active-interaction-surface
        (app.set-active-interaction-surface preferred-surface
                                            {:sync-canvas-visibility false})
        (set app.preferred-interaction-surface preferred-surface)))
  true)

(fn apply-activity-hooks! [hook-state]
  (local hooks (or hook-state (empty-activity-hooks))) (local previous-left-dock-builder app.activity-left-dock-builder)
  (set app.activity-root-actions hooks.root-actions)
  (set app.activity-selection-actions hooks.selection-actions)
  (set app.activity-left-dock-builder hooks.left-dock-builder)
  (set app.activity-command-hints-provider hooks.command-hints-provider) (set app.activity-leader-command-providers hooks.leader-command-providers)
  (set app.activity-delete-selection hooks.delete-selection)
  (set app.activity-activate-focused hooks.activate-focused)
  (set app.activity-drawing-enabled? hooks.drawing-enabled?)
  (set app.activity-context-enricher hooks.context-enricher)
  (set app.activity-input-handlers hooks.input-handlers)
  (set app.activity-target-enabled? hooks.target-enabled?)
  (set app.activity-update hooks.update)
  (set app.activity-top-toolbar-builder hooks.top-toolbar-builder)
  (set app.activity-object-drag-mode-provider hooks.object-drag-mode-provider)
  (if hook-state
      (apply-activity-surface-policy! hooks)
      (do
        (set app.activity-preferred-interaction-surface nil)
        (set app.activity-surface-state nil)
        (set app.canvas-surface-interactive? true)
        (when app.sync-interaction-surface-state
          (app.sync-interaction-surface-state "activity-policy-cleared" nil))))
  (emit-activity-dock-changed! "activity-hooks" previous-left-dock-builder app.activity-left-dock-builder) true)

(fn workspace-shell-state []
  {:interaction-surface app.active-interaction-surface
   :activity app.active-activity-id
   :canvas-visible? (= app.canvas-visible? true)})

(fn workspace-shell-state= [a b]
  (and a b
       (= a.interaction-surface b.interaction-surface)
       (= a.activity b.activity)
       (= a.canvas-visible? b.canvas-visible?)))

(fn emit-workspace-shell-changed! [reason previous]
  (local current (workspace-shell-state))
  (when (and app.workspace-shell-changed
             (not app.suppress-workspace-shell-change?)
             (not (workspace-shell-state= previous current)))
    (app.workspace-shell-changed:emit {:reason reason
                                       :previous previous
                                       :current current}))
  current)

(fn sync-app-active-activity! [activity-id]
  (local previous (workspace-shell-state))
  (set app.active-activity-id activity-id)
  (when app.active-world-runtime
    (set app.active-world-runtime.active-activity-id activity-id)
    (set app.active-world-runtime.requested-activity-id activity-id)
    (set app.active-world-runtime.requested-activity-known? true))
  (when (not (and app.activity-registry
                  app.activity-registry.suppress-workspace-shell-change?))
    (emit-workspace-shell-changed! "activity" previous))
  true)

(fn ensure-activities-changed-signal []
  (set app.activities-changed (or app.activities-changed (Signal)))
  app.activities-changed)

(fn emit-activities-changed! [payload]
  (when app.activities-changed
    (app.activities-changed:emit payload))
  true)

(fn assert-activity-spec-shape! [activity-spec]
  (local activity-id (assert (. activity-spec :id) "Activity spec requires :id"))
  (assert (= (type activity-id) :string)
          (.. "Activity id must be a string, got " (type activity-id)))
  (when (= (. activity-spec :show-in-switcher?) true)
    (assert (. activity-spec :icon)
            (.. "Activity " activity-id " requires :icon when shown in switcher"))
    (assert (. activity-spec :button-name)
            (.. "Activity " activity-id " requires :button-name when shown in switcher"))
    (assert (. activity-spec :label)
            (.. "Activity " activity-id " requires :label when shown in switcher")))
  (assert (= (type (or (. activity-spec :activate) (fn [] true))) :function)
          (.. "Activity " activity-id " requires :activate function"))
  activity-spec)

(fn activity-context [activity-spec opts]
  (local options (or opts {}))
  (local staged-hooks options.staged-hooks)
  (local staged-cleanup options.staged-cleanup)
  (fn set-staged-hook! [key value]
    (assert staged-hooks "Activity hook staging is only available during activation")
    (set (. staged-hooks key) value)
    value)
  (fn defer-cleanup! [cleanup]
    (assert staged-cleanup "Activity cleanup staging is only available during activation")
    (assert (= (type cleanup) :function)
            (.. "Activity cleanup must be a function, got " (type cleanup)))
    (table.insert staged-cleanup cleanup)
    cleanup)
  {:activity activity-spec
   :defer-cleanup! (fn [_self cleanup] (defer-cleanup! cleanup))
   :clear-runtime-hooks! clear-activity-runtime-hooks!
   :set-root-actions! (fn [_self value] (set-staged-hook! :root-actions value))
   :set-selection-actions! (fn [_self value] (set-staged-hook! :selection-actions value))
    :set-left-dock-builder! (fn [_self value] (set-staged-hook! :left-dock-builder value))
    :set-command-hints-provider! (fn [_self value] (set-staged-hook! :command-hints-provider value)) :set-leader-command-providers! (fn [_self value] (set-staged-hook! :leader-command-providers value))
    :set-delete-selection! (fn [_self value] (set-staged-hook! :delete-selection value))
   :set-activate-focused! (fn [_self value] (set-staged-hook! :activate-focused value))
   :set-drawing-enabled! (fn [_self value]
                           (set-staged-hook! :drawing-enabled? (and value true)))
    :set-context-enricher! (fn [_self value] (set-staged-hook! :context-enricher value))
    :set-input-handlers! (fn [_self value] (set-staged-hook! :input-handlers value))
    :set-target-enabled! (fn [_self value] (set-staged-hook! :target-enabled? value))
    :set-update! (fn [_self value] (set-staged-hook! :update value))
    :set-preferred-interaction-surface! (fn [_self value]
                                          (set-staged-hook! :preferred-interaction-surface value))
    :set-surface-state! (fn [_self value] (set-staged-hook! :surface-state value))
    :set-top-toolbar-builder! (fn [_self value] (set-staged-hook! :top-toolbar-builder value))
    :set-object-drag-mode-provider! (fn [_self value] (set-staged-hook! :object-drag-mode-provider value))})

(fn run-cleanup-stack! [cleanup-stack]
  (var first-err nil)
  (var failure-count 0)
  (for [i (length (or cleanup-stack [])) 1 -1]
    (local cleanup (. cleanup-stack i))
    (local (ok err) (pcall cleanup))
    (when (not ok)
      (set failure-count (+ failure-count 1))
      (when (= first-err nil)
        (set first-err err))))
  (when first-err
    (error (.. "Activity cleanup failed ("
               (tostring failure-count)
               " failure(s)); first: "
               (tostring first-err))))
  true)

(fn make-active-session [user-session cleanup-stack]
  {:user-session user-session
   :cleanup cleanup-stack})

(fn active-user-session [activity-session]
  (if (and (= (type activity-session) :table)
           (not (= (. activity-session :cleanup) nil))
           (= (type activity-session.cleanup) :table))
      activity-session.user-session
      activity-session))

(fn active-session-cleanup [activity-session]
  (if (and (= (type activity-session) :table)
           (= (type activity-session.cleanup) :table))
      activity-session.cleanup
      []))

(fn append-cleanup-stack! [activity-session cleanup-stack]
  (when (> (length (or cleanup-stack [])) 0)
    (local retained-cleanup (active-session-cleanup activity-session))
    (each [_ cleanup (ipairs cleanup-stack)]
      (table.insert retained-cleanup cleanup)))
  activity-session)

(fn active-activity-spec []
  (and (ensure-registry) app.activity-registry.active-activity-spec))

(fn active-activity-id []
  (and (ensure-registry) app.activity-registry.active-activity-id))

(fn active-activity-session []
  (and (ensure-registry) app.activity-registry.active-activity-session))

(fn snapshot-activity-state [activity-spec activity-session]
  ((or (. activity-spec :snapshot) noop-snapshot)
   (activity-context activity-spec)
   (active-user-session activity-session)))

(fn deactivate-active-activity []
  (local registry (ensure-registry))
  (local previous-shell-state (workspace-shell-state))
  (local activity-spec registry.active-activity-spec)
  (local activity-session registry.active-activity-session)
  (when activity-spec
    ((or (. activity-spec :deactivate) noop-deactivate)
     (activity-context activity-spec)
     (active-user-session activity-session)))
  (local previous-registry-suppress? registry.suppress-workspace-shell-change?)
  (local previous-app-suppress? app.suppress-workspace-shell-change?)
  (set registry.suppress-workspace-shell-change? true)
  (set app.suppress-workspace-shell-change? true)
  (local (ok err)
    (pcall
      (fn []
        (apply-activity-hooks! nil)
        (set registry.active-activity-id nil)
        (set registry.active-activity-spec nil)
        (set registry.active-activity-session nil)
        (sync-app-active-activity! nil))))
  (set registry.suppress-workspace-shell-change? previous-registry-suppress?)
  (set app.suppress-workspace-shell-change? previous-app-suppress?)
  (when (not ok)
    (error err))
  (emit-workspace-shell-changed! "activity" previous-shell-state)
  true)

(fn drop-activity-session! [activity-id]
  (local registry (ensure-registry))
  (local activity-session (and activity-id (. registry.sessions activity-id)))
  (when activity-session
    (run-cleanup-stack! (active-session-cleanup activity-session))
    (set (. registry.sessions activity-id) nil))
  true)

(fn drop-all-activity-sessions! []
  (local registry (ensure-registry))
  (local activity-ids [])
  (each [activity-id _session (pairs registry.sessions)]
    (table.insert activity-ids activity-id))
  (each [_ activity-id (ipairs activity-ids)]
      (drop-activity-session! activity-id))
  true)

(fn register-activity [activity-spec]
  (local registry (ensure-registry))
  (local spec (assert-activity-spec-shape! activity-spec))
  (local activity-id (. spec :id))
  (assert (not (. registry.activities activity-id))
          (.. "Duplicate activity id: " activity-id))
  (set (. registry.activities activity-id) spec)
  (table.insert registry.ordered-ids activity-id)
  (ensure-activities-changed-signal)
  (emit-activities-changed! {:reason :registered
                             :activity-id activity-id})
  spec)

(fn resolve [activity-id]
  (if (= activity-id nil)
      nil
      (do
        (assert (= (type activity-id) :string)
                (.. "Activity id must be a string, got " (type activity-id)))
        (assert (activity-registered? activity-id)
                (.. "Unknown activity: " activity-id))
        activity-id)))

(fn unregister-activity [activity-id]
  (local registry (ensure-registry))
  (local resolved-id (if (= activity-id nil) nil (resolve activity-id)))
  (when (and resolved-id (= registry.active-activity-id resolved-id))
    (deactivate-active-activity))
  (drop-activity-session! resolved-id)
  (set (. registry.activities resolved-id) nil)
  (local remaining [])
  (each [_ existing-id (ipairs registry.ordered-ids)]
    (when (not (= existing-id resolved-id))
      (table.insert remaining existing-id)))
  (set registry.ordered-ids remaining)
  (emit-activities-changed! {:reason :unregistered
                             :activity-id resolved-id})
  true)

(fn spec [activity-id]
  (if (= activity-id nil)
      nil
      (do
        (local registry (ensure-registry))
        (. registry.activities (resolve activity-id)))))

(fn activity-specs-in-order []
  (local registry (ensure-registry))
  (icollect [_ activity-id (ipairs registry.ordered-ids)]
    (. registry.activities activity-id)))

(fn switcher-activity-specs []
  (local switcher-activities [])
  (each [_ activity-spec (ipairs (activity-specs-in-order))]
    (when (= (and activity-spec (. activity-spec :show-in-switcher?)) true)
      (table.insert switcher-activities activity-spec)))
  switcher-activities)

(fn matches-id? [activity-id expected-id]
  (if (or (= activity-id nil)
          (= expected-id nil))
      (= activity-id expected-id)
      (= (resolve activity-id) (resolve expected-id))))

(fn restore-activity-session-state! [activity-spec activity-session state]
  ((or (. activity-spec :restore) noop-restore)
   (activity-context activity-spec)
   (active-user-session activity-session)
   state))

(fn activate-activity-session! [registry activity-id activity-spec staged-hooks staged-cleanup retained-session]
  (with-activating-activity
    registry
    activity-id
    (fn []
      ((or (. activity-spec :activate) (fn [_ctx] nil))
       (activity-context activity-spec
                         {:staged-hooks staged-hooks
                          :staged-cleanup staged-cleanup})
       (active-user-session retained-session)))))

(fn restore-activity-session-state-with-owner! [registry activity-id activity-spec retained-session state]
  (with-activating-activity
    registry
    activity-id
    (fn []
      (restore-activity-session-state! activity-spec retained-session state))))

(fn restore-previous-activity! [registry previous-id previous-spec previous-state]
  (if previous-spec
      (do
        (local staged-hooks (empty-activity-hooks))
        (local staged-cleanup [])
        (var retained-session (. registry.sessions previous-id))
        (local previous-session
          (activate-activity-session! registry previous-id previous-spec staged-hooks staged-cleanup retained-session))
        (apply-activity-hooks! staged-hooks)
        (set registry.active-activity-id previous-id)
        (set registry.active-activity-spec previous-spec)
        (when (not retained-session)
          (set retained-session (make-active-session previous-session staged-cleanup))
          (set (. registry.sessions previous-id) retained-session))
        (set registry.active-activity-session retained-session)
        (sync-app-active-activity! previous-id)
        (restore-activity-session-state! previous-spec retained-session previous-state))
      (do
        (set registry.active-activity-id nil)
        (set registry.active-activity-spec nil)
        (set registry.active-activity-session nil)
        (apply-activity-hooks! nil)
        (sync-app-active-activity! nil)
        nil)))

(fn with-workspace-shell-change-suppressed [registry-or-f maybe-f]
  (local registry (if maybe-f registry-or-f (ensure-registry)))
  (local f (or maybe-f registry-or-f))
  (local previous-registry-suppress? registry.suppress-workspace-shell-change?)
  (local previous-app-suppress? app.suppress-workspace-shell-change?)
  (set registry.suppress-workspace-shell-change? true)
  (set app.suppress-workspace-shell-change? true)
  (local (ok result) (pcall f))
  (set registry.suppress-workspace-shell-change? previous-registry-suppress?)
  (set app.suppress-workspace-shell-change? previous-app-suppress?)
  (if ok result (error result)))

(fn rollback-activity-switch! [registry previous-id previous-spec previous-state staged-cleanup]
  (local (cleanup-ok cleanup-err) (pcall run-cleanup-stack! staged-cleanup))
  (local (rollback-ok rollback-err)
    (pcall restore-previous-activity! registry previous-id previous-spec previous-state))
  (values cleanup-ok cleanup-err rollback-ok rollback-err))

(fn raise-activity-switch-error [prefix err cleanup-ok cleanup-err rollback-ok rollback-err]
  (var message (.. prefix (tostring err)))
  (when (not cleanup-ok)
    (set message (.. message " (cleanup failed: " (tostring cleanup-err) ")")))
  (when (not rollback-ok)
    (set message (.. message " (rollback failed: " (tostring rollback-err) ")")))
  (error message))

(fn invalidate-target-session-after-failure! [registry resolved-id had-retained-session? staged-cleanup]
  (when (or (not had-retained-session?)
            (> (length (or staged-cleanup [])) 0))
    (set (. registry.sessions resolved-id) nil))
  true)

(fn switch-activity! [registry resolved-id next-spec previous-id previous-spec previous-state previous-shell-state]
  (local session
    (with-workspace-shell-change-suppressed
      registry
      (fn []
        (local staged-hooks (empty-activity-hooks))
        (local staged-cleanup [])
        (var retained-session (. registry.sessions resolved-id))
        (local had-retained-session? (not (= retained-session nil)))
        (var previous-deactivated? false)
        (local (prepare-ok prepare-err)
          (pcall
            (fn []
              (when previous-spec
                ((or (. previous-spec :deactivate) noop-deactivate)
                 (activity-context previous-spec)
                 (active-user-session registry.active-activity-session))
                (set previous-deactivated? true))
              (apply-activity-hooks! nil)
              (set registry.active-activity-id nil)
              (set registry.active-activity-spec nil)
              (set registry.active-activity-session nil)
              (sync-app-active-activity! nil))))
        (when (not prepare-ok)
          (local (cleanup-ok cleanup-err rollback-ok rollback-err)
            (if (not previous-deactivated?)
                (values true nil true nil)
                (rollback-activity-switch! registry previous-id previous-spec previous-state staged-cleanup)))
          (raise-activity-switch-error (.. "Activity deactivation failed for " resolved-id ": ")
                                       prepare-err
                                       cleanup-ok
                                       cleanup-err
                                       rollback-ok
                                       rollback-err))
        (local (ok activity-session-or-err)
          (pcall activate-activity-session! registry resolved-id next-spec staged-hooks staged-cleanup retained-session))
        (if ok
            (do
              (var failure-prefix (.. "Activity activation failed for " resolved-id ": "))
              (local (commit-ok commit-result-or-err)
                (pcall
                  (fn []
                    (apply-activity-hooks! staged-hooks)
                    (set registry.active-activity-id resolved-id)
                    (set registry.active-activity-spec next-spec)
                    (set retained-session
                         (if had-retained-session?
                             (append-cleanup-stack! retained-session staged-cleanup)
                             (make-active-session activity-session-or-err staged-cleanup)))
                    (set (. registry.sessions resolved-id) retained-session)
                    (set registry.active-activity-session retained-session)
                    (sync-app-active-activity! resolved-id)
                    (do
                      (local Boundary (require :activity-surface-boundary))
                      (Boundary.deactivate-foreign-slots! (and app.active-world-runtime app.active-world-runtime.canvas) resolved-id)
                      (Boundary.deactivate-foreign-slots! (and app.active-world-runtime app.active-world-runtime.scene) resolved-id))
                    (local restored-state (pending-session-state resolved-id))
                    (when restored-state
                      (local (restore-ok restore-err)
                        (pcall restore-activity-session-state-with-owner!
                               registry
                               resolved-id
                               next-spec
                               retained-session
                               restored-state))
                      (if restore-ok
                          (clear-pending-session-state! resolved-id)
                          (do
                            (set failure-prefix (.. "Activity restore failed for " resolved-id ": "))
                            (error restore-err))))
                    (active-user-session retained-session))))
              (if commit-ok
                  commit-result-or-err
                  (do
                    (invalidate-target-session-after-failure! registry
                                                              resolved-id
                                                              had-retained-session?
                                                              staged-cleanup)
                    (local (cleanup-ok cleanup-err rollback-ok rollback-err)
                      (rollback-activity-switch! registry previous-id previous-spec previous-state staged-cleanup))
                    (raise-activity-switch-error failure-prefix
                                                 commit-result-or-err
                                                 cleanup-ok
                                                 cleanup-err
                                                 rollback-ok
                                                 rollback-err))))
            (do
              (invalidate-target-session-after-failure! registry resolved-id had-retained-session? staged-cleanup)
              (local (cleanup-ok cleanup-err rollback-ok rollback-err)
                (rollback-activity-switch! registry previous-id previous-spec previous-state staged-cleanup))
              (raise-activity-switch-error (.. "Activity activation failed for " resolved-id ": ")
                                           activity-session-or-err
                                            cleanup-ok
                                            cleanup-err
                                            rollback-ok
                                            rollback-err))))))
  (emit-workspace-shell-changed! "activity" previous-shell-state)
  session)

(fn activate-activity [activity-id]
  (local registry (ensure-registry))
  (local resolved-id (resolve activity-id))
  (local previous-id registry.active-activity-id)
  (local previous-spec registry.active-activity-spec)
  (local previous-shell-state (workspace-shell-state))
  (if (= resolved-id nil)
      (do
        (deactivate-active-activity)
        nil)
      (do
        (local next-spec (. registry.activities resolved-id))
        (local previous-state
          (if previous-spec
              (snapshot-activity-state previous-spec registry.active-activity-session)
              nil))
        (if (and previous-id
                 (= previous-id resolved-id)
                 registry.active-activity-session)
            (active-user-session registry.active-activity-session)
            (switch-activity! registry
                              resolved-id
                              next-spec
                              previous-id
                              previous-spec
                               previous-state
                               previous-shell-state)))))

(fn snapshot-active-activity []
  (local registry (ensure-registry))
  (if registry.active-activity-spec
      ((or (. registry.active-activity-spec :snapshot) noop-snapshot)
       (activity-context registry.active-activity-spec)
       (active-user-session registry.active-activity-session))
      nil))

(fn restore-active-activity [state]
  (local registry (ensure-registry))
  (if registry.active-activity-spec
      ((or (. registry.active-activity-spec :restore) noop-restore)
       (activity-context registry.active-activity-spec)
       (active-user-session registry.active-activity-session)
       state)
      true))

(fn snapshot-activity-sessions []
  (local registry (ensure-registry))
  (local out {})
  (when (and app.active-world-runtime
             app.active-world-runtime.activity-session-state)
    (each [activity-id state (pairs app.active-world-runtime.activity-session-state)]
      (when (not (= state nil))
        (set (. out activity-id) (clone-table state)))))
  (each [activity-id activity-session (pairs registry.sessions)]
    (local activity-spec (. registry.activities activity-id))
    (when activity-spec
      (local state (snapshot-activity-state activity-spec activity-session))
      (when (not (= state nil))
        (set (. out activity-id) state))))
  out)

(fn normalize-persisted-activity-id [activity-id]
  (if (= activity-id nil)
      (values nil false nil)
      (if (and (= (type activity-id) :string)
               (> (# activity-id) 0))
          (do
            (local migrated (. persisted-activity-migrations activity-id))
            (if migrated
                (values migrated
                        true
                        (.. "migrating persisted activity.active_id from "
                            (tostring activity-id)
                            " to "
                            migrated))
                (values activity-id false nil)))
          (values nil
                  true
                   (.. "invalid persisted activity.active_id "
                       (tostring activity-id)
                       "; clearing to nil")))))

(fn activity-status []
  (local registry (ensure-registry))
  (local activity-id registry.active-activity-id)
  {:active-activity-id activity-id
   :registered? (and (not (= activity-id nil))
                     (not (= (. registry.activities activity-id) nil)))
   :has-active-session? (not (= registry.active-activity-session nil))})

(fn reactivate-active-activity [activity-id]
  (var registry (ensure-registry))
  (local active-before activity-id)
  (local registered-after? (and (not (= active-before nil))
                                (not (= (. registry.activities active-before) nil))))
  (var evidence {:attempted false
                 :reactivation-attempted false
                 :active-activity-before active-before
                 :active-activity-after registry.active-activity-id
                 :registered-after? registered-after?
                 :has-active-session-after? (not (= registry.active-activity-session nil))
                 :reactivated false
                 :error nil})
  (when (and active-before registered-after?)
    (tset evidence :attempted true)
    (tset evidence :reactivation-attempted true)
    (local (ok err) (pcall activate-activity active-before))
    (when (not ok)
      (tset evidence :error (tostring err)))
    (set registry (ensure-registry))
    (tset evidence :active-activity-after registry.active-activity-id)
    (tset evidence :registered-after? (not (= (. registry.activities active-before) nil)))
    (tset evidence :has-active-session-after? (not (= registry.active-activity-session nil)))
    (tset evidence :reactivated (and ok
                                     (= registry.active-activity-id active-before)
                                     (not (= registry.active-activity-session nil)))))
  evidence)

{:clear-activity-runtime-hooks! clear-activity-runtime-hooks!
 :ensure-registry ensure-registry
 :ensure-activities-changed-signal ensure-activities-changed-signal
 :register-activity register-activity
 :activity-registered? activity-registered?
 :unregister-activity unregister-activity
 :resolve resolve
 :spec spec
 :activity-specs-in-order activity-specs-in-order
 :switcher-activity-specs switcher-activity-specs
 :matches-id? matches-id?
 :activate-activity activate-activity
  :deactivate-active-activity deactivate-active-activity
  :drop-activity-session! drop-activity-session!
  :drop-all-activity-sessions! drop-all-activity-sessions!
  :with-workspace-shell-change-suppressed with-workspace-shell-change-suppressed
   :active-activity-id active-activity-id
   :active-activity-spec active-activity-spec
   :active-activity-session active-activity-session
   :activity-status activity-status
   :reactivate-active-activity reactivate-active-activity
   :snapshot-active-activity snapshot-active-activity
  :restore-active-activity restore-active-activity
  :snapshot-activity-sessions snapshot-activity-sessions
  :normalize-persisted-activity-id normalize-persisted-activity-id}
