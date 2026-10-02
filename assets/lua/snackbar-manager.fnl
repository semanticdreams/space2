(local Signal (require :signal))
(local RuntimeTimers (require :runtime-timers))
(local SnackbarTheme (require :snackbar-theme))

(fn copy-array [source]
  (local target [])
  (each [_ value (ipairs source)]
    (table.insert target value))
  target)

(fn copy-entry [entry]
  (local copy {})
  (each [key value (pairs entry)]
    (set (. copy key) value))
  copy)

(fn copy-entries [source]
  (local target [])
  (each [_ entry (ipairs source)]
    (table.insert target (copy-entry entry)))
  target)

(fn positive-limit [value fallback]
  (if (and (= (type value) :number) (>= value 0))
      value
      fallback))

(fn fallback-reason [reason fallback]
  (if (= reason nil) fallback reason))

(fn request-text [request]
  (if (not (= request.text nil))
      request.text
      request.message))

(fn assert-active [state]
  (assert (not state.dropped?) "SnackbarManager is dropped"))

(fn generated-id [state]
  (local id (.. "snackbar-" state.next-id))
  (set state.next-id (+ state.next-id 1))
  id)

(fn remove-by-id [entries id]
  (var removed nil)
  (var idx 1)
  (while (<= idx (length entries))
    (local entry (. entries idx))
    (if (and (not removed) (= entry.id id))
        (set removed (table.remove entries idx))
        (set idx (+ idx 1))))
  removed)

(fn mark-dropped [handle reason]
  (when handle
    (set handle.dropped? true)
    (set handle.drop-reason reason)))

(fn cancel-timer [state id]
  (local timer (. state.timers id))
  (when timer
    (timer:drop)
    (set (. state.timers id) nil)))

(fn emit-change [state manager reason]
  (state.changed:emit {:reason reason
                       :visible (copy-entries state.visible)
                       :queued (copy-entries state.queued)
                       :manager manager}))

(fn normalize-entry [state request]
  (assert (= (type request) :table) "SnackbarManager.show requires a request table")
  (local text (request-text request))
  (assert (if (= text nil) request.content-builder true)
          "SnackbarManager.show requires :text, :message, or :content-builder")
  (local id (if (= request.id nil) (generated-id state) request.id))
  {:id id
   :text text
   :content-builder request.content-builder
   :variant (if (= request.variant nil) :info request.variant)
   :duration-ms (if (= request.duration-ms nil)
                    state.policy.duration-ms
                    request.duration-ms)
   :metadata request.metadata})

(fn resolve-id [id-or-handle]
  (if (and (= (type id-or-handle) :table) id-or-handle.id)
      id-or-handle.id
      id-or-handle))

(fn schedule-timeout [state manager entry]
  (fn timeout-callback []
    (when (not state.dropped?)
      (manager:dismiss entry.id :timeout)))
  (local timer (RuntimeTimers.Timeout {:delay-ms entry.duration-ms
                                       :callback timeout-callback}))
  (set (. state.timers entry.id) timer)
  (timer:start))

(fn schedule-entry [state manager entry]
  (when (and (= (type entry.duration-ms) :number)
             (> entry.duration-ms 0))
    (schedule-timeout state manager entry)))

(fn promote-queued [state manager]
  (while (and (< (length state.visible) state.max-visible)
              (> (length state.queued) 0))
    (local entry (table.remove state.queued 1))
    (table.insert state.visible entry)
    (schedule-entry state manager entry)))

(fn make-handle [manager entry]
  {:id entry.id
   :entry entry
   :dropped? false
   :drop-reason nil
   :dismiss (fn [_self reason]
              (manager:dismiss entry.id reason))})

(fn drop-overflow [state]
  (when (and (>= (length state.queued) state.max-queued)
             (> (length state.queued) 0))
    (local overflow (table.remove state.queued 1))
    (local overflow-handle (. state.handles overflow.id))
    (cancel-timer state overflow.id)
    (mark-dropped overflow-handle :overflow)
    (set (. state.handles overflow.id) nil)))

(fn enqueue-entry [state entry]
  (drop-overflow state)
  (when (< (length state.queued) state.max-queued)
    (table.insert state.queued entry)))

(fn show-entry [state manager request]
  (assert-active state)
  (local entry (normalize-entry state request))
  (local handle (make-handle manager entry))
  (set (. state.handles entry.id) handle)
  (if (< (length state.visible) state.max-visible)
      (do
        (table.insert state.visible entry)
        (schedule-entry state manager entry))
      (enqueue-entry state entry))
  (emit-change state manager :show)
  handle)

(fn dismiss-entry [state manager id-or-handle reason]
  (assert-active state)
  (local id (resolve-id id-or-handle))
  (var entry (remove-by-id state.visible id))
  (when (not entry)
    (set entry (remove-by-id state.queued id)))
  (if entry
      (do
        (cancel-timer state id)
        (local final-reason (fallback-reason reason :dismissed))
        (mark-dropped (. state.handles id) final-reason)
        (set (. state.handles id) nil)
        (promote-queued state manager)
        (emit-change state manager final-reason)
        true)
      false))

(fn clear-entries [state manager reason]
  (assert-active state)
  (local entries (copy-array state.visible))
  (each [_ entry (ipairs state.queued)]
    (table.insert entries entry))
  (local final-reason (fallback-reason reason :cleared))
  (each [_ entry (ipairs entries)]
    (cancel-timer state entry.id)
    (mark-dropped (. state.handles entry.id) final-reason)
    (set (. state.handles entry.id) nil))
  (local count (length entries))
  (set state.visible [])
  (set state.queued [])
  (when (> count 0)
    (emit-change state manager final-reason))
  count)

(fn subscribe-listener [state listener]
  (assert-active state)
  (assert (= (type listener) :function) "SnackbarManager.subscribe requires a listener")
  (state.changed:connect listener)
  (fn disconnect []
    (state.changed:disconnect listener true)))

(fn drop-manager [state]
  (when (not state.dropped?)
    (each [id _timer (pairs state.timers)]
      (cancel-timer state id))
    (each [_ entry (ipairs state.visible)]
      (mark-dropped (. state.handles entry.id) :manager-dropped)
      (set (. state.handles entry.id) nil))
    (each [_ entry (ipairs state.queued)]
      (mark-dropped (. state.handles entry.id) :manager-dropped)
      (set (. state.handles entry.id) nil))
    (set state.visible [])
    (set state.queued [])
    (state.changed:clear)
    (set state.dropped? true))
  true)

(fn make-state [opts]
  (local options (if opts opts {}))
  (local policy (SnackbarTheme.resolve nil options))
  {:policy policy
   :changed (Signal)
   :dropped? false
   :next-id 1
   :visible []
   :queued []
   :handles {}
   :timers {}
   :max-visible (positive-limit policy.max-visible 3)
   :max-queued (positive-limit policy.max-queued 20)})

(fn SnackbarManager [opts]
  (local state (make-state opts))
  (var manager nil)
  (set manager
       {:show (fn [_self request]
                (show-entry state manager request))
        :dismiss (fn [_self id-or-handle reason]
                   (dismiss-entry state manager id-or-handle reason))
        :clear (fn [_self reason]
                 (clear-entries state manager reason))
        :visible-entries (fn [_self]
                           (copy-entries state.visible))
        :queued-entries (fn [_self]
                          (copy-entries state.queued))
        :subscribe (fn [_self listener]
                     (subscribe-listener state listener))
        :handle-for (fn [_self id]
                      (. state.handles id))
        :drop (fn [_self]
                (drop-manager state))})
  manager)

SnackbarManager
