(local Temporal (require :temporal))

(fn scheduler-error [message]
  (error (.. "[runtime-scheduler] " message)))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn function? [value]
  (= (type value) :function))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn reject-unknown-keys [label options allowed]
  (each [key _value (pairs (table-or-empty options))]
    (when (not (. allowed key))
      (scheduler-error (.. label " unknown option: " (tostring key))))))

(fn duration->nanoseconds [value label]
  (when (= value nil)
    (scheduler-error (.. label " requires duration")))
  (local nanos
    (if (= (type value) :number)
        value
        (and (= (type value) :userdata)
             (= (type value.nanoseconds) :function)
             (value:nanoseconds))))
  (when (not (and (= (type nanos) :number)
                  (= nanos (math.floor nanos))
                  (>= nanos 0)))
    (scheduler-error (.. label " requires non-negative exact duration")))
  nanos)

(fn require-callback [value label]
  (when (not (function? value))
    (scheduler-error (.. label " requires callback"))))

(fn active-job? [job]
  job.active?)

(fn sorted-jobs [jobs predicate]
  (local result [])
  (each [_id job (pairs jobs)]
    (when (predicate job)
      (table.insert result job)))
  (table.sort result
              (fn [left right]
                (if (not (= left.deadline-ns right.deadline-ns))
                    (< left.deadline-ns right.deadline-ns)
                    (< left.created-order right.created-order))))
  result)

(fn create-handle [scheduler job]
  (fn cancel [_self]
    (when job.active?
      (set job.active? false)
      (tset scheduler.jobs job.id nil))
    true)
  (fn active? [_self]
    job.active?)
  {:cancel cancel :drop cancel :active? active?})

(fn create-group-handle [jobs]
  (local state {:active? true})
  (fn cancel [_self]
    (when state.active?
      (set state.active? false)
      (each [_ handle (ipairs jobs)]
        (handle:cancel)))
    true)
  (fn active? [_self]
    (var any-active? false)
    (when state.active?
      (each [_ handle (ipairs jobs)]
        (when (handle:active?)
          (set any-active? true))))
    any-active?)
  {:cancel cancel :drop cancel :active? active? :state state})

(fn insert-job [scheduler kind delay-ns callback extra]
  (local id scheduler.next-id)
  (set scheduler.next-id (+ scheduler.next-id 1))
  (local job {:id id
              :kind kind
              :deadline-ns (+ scheduler.now-ns delay-ns)
              :created-order id
              :active? true
              :callback callback})
  (when extra
    (each [key value (pairs extra)]
      (tset job key value)))
  (tset scheduler.jobs id job)
  (create-handle scheduler job))

(fn due-job? [scheduler job]
  (and job.active? (<= job.deadline-ns scheduler.now-ns)))

(fn interval-job? [job]
  (= job.kind :interval))

(fn execute-job [scheduler job]
  (if (interval-job? job)
      (do
        (job:callback)
        (when (and job.active? (. scheduler.jobs job.id))
          (set job.deadline-ns (+ job.deadline-ns job.interval-ns))))
      (do
        (set job.active? false)
        (tset scheduler.jobs job.id nil)
        (job:callback))))

(fn drain-due [scheduler]
  (var keep-going? true)
  (while keep-going?
    (local due (sorted-jobs scheduler.jobs #(due-job? scheduler $1)))
    (if (= (# due) 0)
        (set keep-going? false)
        (each [_ job (ipairs due)]
          (when (and job.active? (. scheduler.jobs job.id))
            (execute-job scheduler job))))))

(fn schedule-once [self opts]
  (local job-options (table-or-empty opts))
  (reject-unknown-keys "schedule-once" job-options {:delay true :callback true})
  (require-callback job-options.callback "schedule-once")
  (insert-job self
              :once
              (duration->nanoseconds job-options.delay "schedule-once delay")
              job-options.callback))

(fn schedule-every [self opts]
  (local job-options (table-or-empty opts))
  (reject-unknown-keys "schedule-every" job-options {:interval true :callback true})
  (require-callback job-options.callback "schedule-every")
  (local interval-ns (duration->nanoseconds job-options.interval "schedule-every interval"))
  (when (= interval-ns 0)
    (scheduler-error "schedule-every interval requires positive duration"))
  (insert-job self :interval interval-ns job-options.callback {:interval-ns interval-ns}))

(fn recurrence-options [job-options]
  {:zone-id job-options.zone-id
   :disambiguation (if (= job-options.disambiguation nil)
                       :reject
                       job-options.disambiguation)
   :limit job-options.limit})

(fn make-recurrence-callback [group-box callback scheduled-at index]
  (fn []
    (when (if (= group-box.group nil) true group-box.group.state.active?)
      (callback {:scheduled-at scheduled-at :occurrence-index index}))))

(fn schedule-recurrence [self opts]
  (local job-options (table-or-empty opts))
  (reject-unknown-keys "schedule-recurrence"
                       job-options
                       {:recurrence-set true :zone-id true :limit true
                        :disambiguation true :callback true})
  (when (= job-options.recurrence-set nil)
    (scheduler-error "schedule-recurrence requires recurrence-set"))
  (when (= job-options.zone-id nil)
    (scheduler-error "schedule-recurrence requires zone-id"))
  (require-callback job-options.callback "schedule-recurrence")
  (local occurrences
    (Temporal.recurrence-set.occurrences job-options.recurrence-set
                                         (recurrence-options job-options)))
  (local handles [])
  (local group-box {:group nil})
  (each [index occurrence (ipairs occurrences)]
    (local scheduled-at (occurrence:instant))
    (local delay-ns (duration->nanoseconds (scheduled-at:since self.start-instant)
                                           "schedule-recurrence occurrence"))
    (table.insert handles
                  (insert-job self
                              :recurrence
                              delay-ns
                              (make-recurrence-callback group-box
                                                        job-options.callback
                                                        scheduled-at
                                                        index)
                              {:scheduled-at scheduled-at :occurrence-index index})))
  (set group-box.group (create-group-handle handles))
  group-box.group)

(fn advance [self duration]
  (set self.now-ns (+ self.now-ns (duration->nanoseconds duration "advance")))
  (drain-due self)
  true)

(fn update [self delta-ms]
  (when (not (and (finite-number? delta-ms) (>= delta-ms 0)))
    (scheduler-error "update requires non-negative finite delta-ms"))
  (local nanos (* delta-ms 1000000))
  (when (not (= nanos (math.floor nanos)))
    (scheduler-error "update requires exact nanosecond delta-ms"))
  (self:advance (Temporal.duration.from {:nanoseconds nanos})))

(fn clear [self]
  (each [_id job (pairs self.jobs)]
    (set job.active? false))
  (set self.jobs {})
  true)

(fn list [self]
  (local result [])
  (each [_ job (ipairs (sorted-jobs self.jobs active-job?))]
    (table.insert result {:id job.id
                          :kind job.kind
                          :deadline-ns job.deadline-ns
                          :active? job.active?}))
  result)

(fn create [opts]
  (local options (table-or-empty opts))
  (reject-unknown-keys "create" options {:clock true})
  (local clock (if (= options.clock nil) (Temporal.clock.system) options.clock))
  {:clock clock
   :start-instant (clock:now)
   :now-ns 0
   :next-id 1
   :jobs {}
   :schedule-once schedule-once
   :schedule-every schedule-every
   :schedule-recurrence schedule-recurrence
   :advance advance
   :update update
   :clear clear
   :drop clear
   :list list})

{:create create}
