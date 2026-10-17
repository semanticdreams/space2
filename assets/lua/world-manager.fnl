(local fs (require :fs))
(local json (require :json))
(local Signal (require :signal))
(local JsonUtils (require :json-utils))
(local HomeWorld (require :home-world))
(local R (require :reference-lifecycle/record-utils))

;; Lifecycle enumeration never calls get-world-entry (which instantiates worlds).
(fn reference-worlds [root entries]
  (local base (fs.parent root))
  (local indexed {})
  (fn include! [id world]
    (R.require-id id)
    (local path (R.record-path base root id ""))
    (when world
      (assert (and (= world.id id) (= (R.comparison-path world.dir) path))
              "WorldManager loaded world id/root mismatch"))
    (local previous (. indexed id))
    (tset indexed id {:id id :dir path :world (if world world (and previous previous.world))}))
  (local index-path (R.record-path base root "index" ".json"))
  (local snapshot (R.snapshot index-path "json" json.loads))
  (when snapshot.value
    (R.require-array snapshot.value.worlds)
    (local seen {})
    (each [_ entry (ipairs snapshot.value.worlds)]
      (assert (not (. seen entry.id)) "WorldManager duplicate indexed world id")
      (include! entry.id nil)
      (tset seen entry.id true)))
  (when (fs.exists root)
    (each [_ entry (ipairs (fs.list-dir root true true))]
      (assert (not entry.error) (.. entry.path ": " (tostring entry.error)))
      (assert (not entry.is-symlink) (.. "WorldManager world symlink unsupported: " entry.path))
      (when entry.is-dir (include! entry.name nil))))
  (each [_ entry (ipairs entries)] (include! entry.id entry.world))
  (local result (icollect [_ entry (pairs indexed)] entry))
  (table.sort result (fn by-id [a b] (< a.id b.id)))
  result)

(fn normalize-world-record [record]
  (local target (or record {}))
  (local id (and target.id (tostring target.id)))
  (local type-name (or target.type "home"))
  (local name (or target.name "home"))
  (if id
      {:id id
       :type type-name
       :name name}
      nil))

(fn normalize-worlds [data]
  (var worlds [])
  (each [_ record (ipairs (or data []))]
    (local normalized (normalize-world-record record))
    (when normalized
      (table.insert worlds normalized)))
  worlds)

(fn first-unused-home-name [worlds]
  (local used {})
  (each [_ world (ipairs worlds)]
    (local name (or world.name ""))
    (local suffix (string.match name "^home%-(%d+)$"))
    (if (= name "home")
        (set (. used 1) true)
        (when suffix
          (local idx (tonumber suffix))
          (when (and idx (> idx 1))
            (set (. used idx) true)))))
  (var idx 1)
  (while (. used idx)
    (set idx (+ idx 1)))
  (if (= idx 1)
      "home"
      (.. "home-" idx)))

(fn read-world-index [index-path]
  (if (not (fs.exists index-path))
      []
      (do
        (local (ok-read content) (pcall fs.read-file index-path))
        (when (not ok-read)
          (error (string.format "WorldManager failed to read %s: %s" index-path content)))
        (local (ok-parse decoded) (pcall json.loads content))
        (when (not ok-parse)
          (error (string.format "WorldManager failed to parse %s: %s" index-path decoded)))
        (when (not (= (type decoded) :table))
          (error (string.format "WorldManager expected table in %s" index-path)))
        (when (and (not (= decoded.worlds nil))
                   (not (= (type decoded.worlds) :table)))
          (error (string.format "WorldManager expected :worlds array in %s" index-path)))
        (normalize-worlds decoded.worlds))))

(fn WorldManager [opts]
  (local options (or opts {}))
  (local root-dir (assert options.root-dir "WorldManager requires :root-dir"))
  (local create-world (or options.create-world HomeWorld))
  (local suspend-delay-ms (or options.suspend-delay-ms 3000))
  (local index-path (fs.join-path root-dir "index.json"))
  (local changed (Signal))
  (var worlds [])
  (var active-index nil)
  (var id-seq 0)
  (var manager-api nil)

  (fn world-dir [id]
    (fs.join-path root-dir id))

  (fn emit-changed []
    (changed:emit {:worlds (length worlds)
                   :active-index active-index}))

  (fn ensure-root-dir []
    (local (ok err) (pcall fs.create-dirs root-dir))
    (when (not ok)
      (error (string.format "WorldManager failed to create %s: %s" root-dir err))))

  (fn save-index []
    (ensure-root-dir)
    (local payload
      {:worlds (icollect [_ entry (ipairs worlds)]
                         {:id entry.id
                          :type entry.type
                          :name entry.name})})
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! index-path payload))))
    (when (not ok)
      (error (string.format "WorldManager failed to write %s: %s" index-path err)))
    true)

  (fn next-world-id []
    (var id nil)
    (var taken true)
    (while taken
      (set id-seq (+ id-seq 1))
      (set id (string.format "world-%d-%d" (os.time) id-seq))
      (set taken false)
      (each [_ entry (ipairs worlds)]
        (when (= entry.id id)
          (set taken true)))
      (when (and (not taken) (fs.exists (world-dir id)))
        (set taken true)))
    id)

  (fn add-world-entry [entry]
    (table.insert worlds {:id entry.id
                          :type entry.type
                          :name entry.name
                          :world nil
                          :inactive-at nil
                          :suspended? false}))

  (fn create-default-home []
    (local id (next-world-id))
    (local entry {:id id
                  :type "home"
                  :name (first-unused-home-name worlds)})
    (add-world-entry entry)
    (save-index))

  (fn ensure-initial-worlds []
    (set worlds [])
    (each [_ entry (ipairs (read-world-index index-path))]
      (add-world-entry entry))
    (when (= (length worlds) 0)
      (create-default-home)))

  (fn runtime-context []
    (assert options.context-fn "WorldManager requires :context-fn")
    (local ctx (options.context-fn))
    (assert (= (type ctx) :table) "WorldManager context-fn must return a table")
    ctx)

  (fn ensure-world-instance [entry]
    (when (not entry.world)
      (set entry.world (create-world {:id entry.id
                                      :name entry.name
                                      :type entry.type
                                      :dir (world-dir entry.id)
                                      :graph-world-manager manager-api
                                      :asset-path-resolver options.asset-path-resolver}))
      (entry.world:init (runtime-context))))

  (fn apply-active-runtime [entry]
    (local runtime (and entry entry.world (entry.world:get-runtime)))
    (when options.on-active-runtime
      (options.on-active-runtime entry runtime)))

  (fn deactivate-entry [entry reason]
    (when (and entry entry.world)
      (entry.world:deactivate (runtime-context) reason)
      (set entry.inactive-at (os.clock))
      (set entry.suspended? false)))

  (fn suspend-entry-now [entry]
    (when (and entry entry.world (not entry.suspended?))
      (entry.world:suspend (runtime-context))
      (set entry.suspended? true)
      (set entry.inactive-at nil)))

  (fn activate-index [idx]
    (local total (length worlds))
    (when (or (< idx 1) (> idx total))
      (error (string.format "WorldManager.activate-index out of bounds: %s (count=%s)"
                            idx total)))
    (when (= active-index idx)
      (lua "return true"))
    (local previous (and active-index (. worlds active-index)))
    (when previous
      (deactivate-entry previous "switch")
      (suspend-entry-now previous))
    (local entry (. worlds idx))
    (ensure-world-instance entry)
    (if entry.suspended?
        (do
          (entry.world:resume (runtime-context))
          (set entry.suspended? false))
        (entry.world:activate (runtime-context)))
    (set entry.inactive-at nil)
    (set active-index idx)
    (apply-active-runtime entry)
    (emit-changed)
    true)

  (fn activate-first []
    (if (> (length worlds) 0)
        (activate-index 1)
        false))

  (fn activate-next []
    (if (= (length worlds) 0)
        false
        (do
          (local current (or active-index 1))
          (var next (+ current 1))
          (if (> next (length worlds))
              (set next 1))
          (activate-index next))))

  (fn activate-previous []
    (if (= (length worlds) 0)
        false
        (do
          (local current (or active-index 1))
          (var prev (- current 1))
          (if (< prev 1)
              (set prev (length worlds)))
          (activate-index prev))))

  (fn activate-by-tab-number [tab-number]
    (if (and tab-number (>= tab-number 1) (<= tab-number (length worlds)))
        (activate-index tab-number)
        false))

  (fn activate-world-id [world-id]
    (if (not world-id)
        false
        (do
          (var target-index nil)
          (each [idx entry (ipairs worlds) &until target-index]
            (when (= entry.id world-id)
              (set target-index idx)))
          (if target-index
              (activate-index target-index)
              false))))

  (fn create-home-world [opts]
    (local options-arg (or opts {}))
    (local id (next-world-id))
    (local entry {:id id
                  :type "home"
                  :name (or options-arg.name (first-unused-home-name worlds))
                  :world nil
                  :inactive-at nil
                  :suspended? false})
    (ensure-root-dir)
    (local (ok err) (pcall fs.create-dirs (world-dir id)))
    (when (not ok)
      (error (string.format "WorldManager failed to create world dir %s: %s" (world-dir id) err)))
    (table.insert worlds entry)
    (save-index)
    (if (or (= options-arg.activate? nil) options-arg.activate?)
        (activate-index (length worlds))
        (emit-changed))
    entry)

  (fn close-world-index [idx]
    (if (or (< idx 1) (> idx (length worlds)))
        false
        (do
          (local entry (. worlds idx))
          (when (and entry entry.world)
            (entry.world:drop (runtime-context) "close")
            (set entry.world nil))
          (table.remove worlds idx)
          (save-index)
          (if (= (length worlds) 0)
              (do
                (set active-index nil)
                (when options.on-empty
                  (options.on-empty))
                (emit-changed)
                true)
              (do
                (if (= active-index idx)
                    (do
                      (local next-idx (math.min idx (length worlds)))
                      (set active-index nil)
                      (activate-index next-idx))
                    (do
                      (when (and active-index (> active-index idx))
                        (set active-index (- active-index 1)))
                      (emit-changed)))
                true)))))

  (fn close-active-world []
    (if active-index
        (close-world-index active-index)
        false))

  (fn update [delta]
    (local delay-seconds (/ suspend-delay-ms 1000.0))
    (each [idx entry (ipairs worlds)]
      (local world entry.world)
      (when (and world world.update)
        (world:update delta {:active? (= idx active-index)}))
      (when (and world
                 (not (= idx active-index))
                 (not entry.suspended?)
                 entry.inactive-at
                 (>= (- (os.clock) entry.inactive-at) delay-seconds))
        (world:suspend (runtime-context))
        (set entry.suspended? true))))

  (fn drop []
    (each [_ entry (ipairs worlds)]
      (when (and entry.world entry.world.drop)
        (entry.world:drop (runtime-context) "app-drop")
        (set entry.world nil)))
    (save-index)
    (set active-index nil))

  (fn list-tabs []
    (icollect [idx entry (ipairs worlds)]
      {:index idx
       :id entry.id
       :name entry.name
       :active? (= idx active-index)}))

  (fn get-world-entry [world-id]
    (var resolved nil)
    (each [_ entry (ipairs worlds)]
      (when (and (not resolved) (= entry.id world-id))
        (set resolved entry)))
    (when resolved
      (ensure-world-instance resolved))
    resolved)

  (fn count []
    (length worlds))

  (fn active-world []
    (and active-index (. worlds active-index)))

  (fn active-world-id []
    (local entry (active-world))
    (and entry entry.id))

  (ensure-initial-worlds)

  (set manager-api
        {:root-dir (R.comparison-path root-dir)
         :list-reference-worlds (fn [_self] (reference-worlds root-dir worlds))
         :activate-first (fn [_self] (activate-first))
        :activate-index (fn [_self idx] (activate-index idx))
        :activate-next (fn [_self] (activate-next))
        :activate-previous (fn [_self] (activate-previous))
        :activate-by-tab-number (fn [_self tab-number] (activate-by-tab-number tab-number))
        :activate-world-id (fn [_self world-id] (activate-world-id world-id))
        :create-home-world (fn [_self opts] (create-home-world opts))
        :close-world-index (fn [_self idx] (close-world-index idx))
        :close-active-world (fn [_self] (close-active-world))
        :update (fn [_self delta] (update delta))
        :drop (fn [_self] (drop))
        :list-tabs (fn [_self] (list-tabs))
        :get-world-entry (fn [_self world-id] (get-world-entry world-id))
        :count (fn [_self] (count))
        :active-world (fn [_self] (active-world))
        :active-world-id (fn [_self] (active-world-id))
        :changed changed})
  manager-api)

WorldManager
