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

(fn copy-action-descriptor [action]
  (assert (= (type action) :table) "SnackbarManager.show actions must be tables")
  (assert (or action.label action.text) "SnackbarManager.show actions require :label or :text")
  (local copy {})
  (each [key value (pairs action)]
    (set (. copy key) value))
  copy)

(fn copy-actions [actions]
  (when actions
    (assert (= (type actions) :table) "SnackbarManager.show actions must be an array")
    (local copy [])
    (each [_ action (ipairs actions)]
      (table.insert copy (copy-action-descriptor action)))
    copy))

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

(fn default-duration-ms [policy]
  (if (not (= policy.default-duration-ms nil))
      policy.default-duration-ms
      policy.duration-ms))

(fn request-text [request]
  (if (not (= request.text nil))
      request.text
      request.message))

(fn assert-active [state]
  (assert (not state.dropped?) "SnackbarManager is dropped"))

(fn generated-id [state]
  (var id (.. "snackbar-" state.next-id))
  (while (. state.handles id)
    (set state.next-id (+ state.next-id 1))
    (set id (.. "snackbar-" state.next-id)))
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

(fn remove-by-replace-key [entries replace-key]
  (local removed [])
  (when (not (= replace-key nil))
    (var idx 1)
    (while (<= idx (length entries))
      (local entry (. entries idx))
      (if (= entry.replace-key replace-key)
          (table.insert removed (table.remove entries idx))
          (set idx (+ idx 1)))))
  removed)

(fn has-replace-key-id? [entries replace-key id]
  (var found? false)
  (when (not (= replace-key nil))
    (each [_ entry (ipairs entries)]
      (when (and (= entry.id id)
                 (= entry.replace-key replace-key))
        (set found? true))))
  found?)

(fn mark-dropped [handle reason]
  (when handle
    (set handle.dropped? true)
    (set handle.drop-reason reason)))

(fn cancel-timer [state id]
  (local timer (. state.timers id))
  (when timer
    (timer:drop)
    (set (. state.timers id) nil)))

(fn numeric-priority [entry]
  (if (= (type entry.priority) :number) entry.priority 0))

(fn entry-before? [state left right]
  (if state.priority-order?
      (do
        (local left-priority (numeric-priority left))
        (local right-priority (numeric-priority right))
        (if (not (= left-priority right-priority))
            (> left-priority right-priority)
            (> left.sequence right.sequence)))
      (if state.newest-first?
          (> left.sequence right.sequence)
          (< left.sequence right.sequence))))

(fn sort-visible [state]
  (table.sort state.visible (fn [left right] (entry-before? state left right))))

(fn sort-queued [state]
  (when state.priority-order?
    (table.sort state.queued (fn [left right] (entry-before? state left right)))))

(fn sort-entries [state]
  (sort-visible state)
  (sort-queued state))

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
                     (default-duration-ms state.policy)
                     request.duration-ms)
    :persistent? (if (= request.persistent? nil) false request.persistent?)
    :priority (if (= request.priority nil) 0 request.priority)
    :replace-key request.replace-key
    :sequence state.next-sequence
    :actions (copy-actions request.actions)
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
  (when (and (not entry.persistent?)
             (= (type entry.duration-ms) :number)
             (> entry.duration-ms 0))
    (schedule-timeout state manager entry)))

(fn promote-queued [state manager]
  (while (and (< (length state.visible) state.max-visible)
              (> (length state.queued) 0))
    (local entry (table.remove state.queued 1))
    (table.insert state.visible entry)
    (schedule-entry state manager entry)
    (sort-visible state)))

(fn make-handle [manager entry]
  {:id entry.id
   :entry entry
   :dropped? false
   :drop-reason nil
    :dismiss (fn [_self reason]
               (manager:dismiss entry.id reason))})

(fn retire-entry [state entry reason]
  (cancel-timer state entry.id)
  (mark-dropped (. state.handles entry.id) reason)
  (set (. state.handles entry.id) nil))

(fn remove-replace-key-matches [state replace-key]
  (when (not (= replace-key nil))
    (each [_ entry (ipairs (remove-by-replace-key state.visible replace-key))]
      (retire-entry state entry :replaced))
    (each [_ entry (ipairs (remove-by-replace-key state.queued replace-key))]
      (retire-entry state entry :replaced))))

(fn replacing-live-id? [state entry]
  (if (has-replace-key-id? state.visible entry.replace-key entry.id)
      true
      (has-replace-key-id? state.queued entry.replace-key entry.id)))

(fn assert-insertable-id [state entry]
  (assert (if (. state.handles entry.id)
              (replacing-live-id? state entry)
              true)
          (.. "SnackbarManager.show duplicate live id: " (tostring entry.id))))

(fn oldest-visible-index [state]
  (var oldest-index nil)
  (var oldest-sequence nil)
  (each [idx entry (ipairs state.visible)]
    (when (if (= oldest-sequence nil)
              true
              (< entry.sequence oldest-sequence))
      (set oldest-index idx)
      (set oldest-sequence entry.sequence)))
  oldest-index)

(fn enqueue-entry [state entry]
  (if (< (length state.queued) state.max-queued)
      (do
        (table.insert state.queued entry)
        (sort-queued state)
        true)
      false))

(fn insert-visible [state manager entry]
  (table.insert state.visible entry)
  (sort-visible state)
  (schedule-entry state manager entry))

(fn resolve-overflow-mode [state request]
  (if (not (= request.mode nil))
      request.mode
      (if (not (= state.policy.overflow-mode nil))
          state.policy.overflow-mode
          :queue)))

(fn show-entry [state manager request]
  (assert-active state)
  (local entry (normalize-entry state request))
  (assert-insertable-id state entry)
  (remove-replace-key-matches state entry.replace-key)
  (local handle (make-handle manager entry))
  (set state.next-sequence (+ state.next-sequence 1))
  (set (. state.handles entry.id) handle)
  (if (< (length state.visible) state.max-visible)
      (do
        (insert-visible state manager entry))
      (do
        (local mode (resolve-overflow-mode state request))
        (if (= mode :drop)
            (do
              (mark-dropped handle :visible-full)
              (set (. state.handles entry.id) nil))
            (= mode :replace)
            (do
              (local oldest-index (oldest-visible-index state))
              (if oldest-index
                  (do
                    (local replaced (table.remove state.visible oldest-index))
                    (retire-entry state replaced :replaced)
                    (insert-visible state manager entry))
                  (do
                    (mark-dropped handle :visible-full)
                    (set (. state.handles entry.id) nil))))
            (when (not (enqueue-entry state entry))
              (mark-dropped handle :queue-full)
              (set (. state.handles entry.id) nil)))))
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
        (sort-entries state)
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
    :next-sequence 1
    :max-visible (positive-limit policy.max-visible 3)
    :max-queued (positive-limit policy.max-queued 20)
    :newest-first? (not (= policy.newest-first? false))
    :priority-order? (if policy.priority-order? true false)})

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
