(local glm (require :glm))
(local Utils (require :graph/view/utils))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))
(local R (require :reference-lifecycle/record-utils))
(local ReferenceState (require :graph/reference-state))

(local ensure-glm-vec3 Utils.ensure-glm-vec3)
(local position-magnitude-threshold 1e6)
(var finite-number? nil) (var assert-valid-position nil) (var assert-valid-size nil)

(fn assert-camera-number-array [map-id value count label]
    (assert (= (type value) :table) (string.format "GraphViewPersistence %s for %s camera must be a table" label map-id))
    (for [idx 1 count]
        (assert (finite-number? (rawget value idx))
                (string.format "GraphViewPersistence %s for %s camera has invalid value at %d" label map-id idx))))

(fn assert-valid-camera-state [map-id value context]
    (when (not (= value nil))
        (assert (= (type value) :table) (string.format "GraphViewPersistence %s for %s camera must be a table" context map-id))
        (assert-camera-number-array map-id value.position 3 (.. context " position"))
        (when (not (= value.rotation nil))
            (assert-camera-number-array map-id value.rotation 4 (.. context " rotation")))))

(fn clone-camera-state [map-id value]
    (when (not (= value nil))
        (assert-valid-camera-state map-id value "camera")
        (local cloned {:position [(rawget value.position 1) (rawget value.position 2) (rawget value.position 3)]})
        (when (not (= value.rotation nil))
            (set cloned.rotation [(rawget value.rotation 1) (rawget value.rotation 2) (rawget value.rotation 3) (rawget value.rotation 4)]))
        cloned))

(fn clone-view-modes [map-id view-modes]
    (local cloned {})
    (each [mode entry (pairs (or view-modes {}))]
        (assert (= (type mode) :string)
                (string.format "GraphViewPersistence view_modes for %s must be keyed by mode string" map-id))
        (assert (= (type entry) :table)
                (string.format "GraphViewPersistence view_modes.%s for %s must be a table" mode map-id))
        (local mode-entry (R.clone entry))
        (when (not (= entry.camera nil))
            (set mode-entry.camera (clone-camera-state map-id entry.camera)))
        (set (. cloned mode) mode-entry))
    cloned)

(fn reference-metadata [map-id metadata]
    (assert (= (type metadata) :table) "GraphViewPersistence install-state! requires metadata")
    (local out (R.clone metadata))
    (each [key value (pairs (or out.positions {}))]
        (assert-valid-position key value "GraphViewPersistence install-state!"))
    (each [key value (pairs (or out.sizes {}))]
        (assert-valid-size key value "GraphViewPersistence install-state!"))
    (each [_ value (pairs (or out.presentations {}))]
        (assert (= value :expanded) "GraphViewPersistence install-state! invalid presentation"))
    (R.require-array (or out.panels []))
    (R.require-array (or out.extra_panels []))
    (assert-valid-camera-state map-id out.camera "install-state!")
    (clone-view-modes map-id (R.field out :view_modes :table {}))
    out)

(fn compact-reference-panels [map-id panels extras?]
    (assert (= (type map-id) :string) "metadata panels require native map id")
    (R.require-array panels)
    (local kept [])
    (var compacted? false)
    (each [_ panel (ipairs panels)]
        (when (and (if extras? panel.kind (= panel.kind "graph-node-view")) (not panel.graph-map-id))
            (set panel.graph-map-id map-id)
            (set compacted? true))
        (if (or (not panel.graph-map-id) (= panel.graph-map-id map-id))
            (table.insert kept panel)
            (set compacted? true)))
    (values kept compacted?))

(fn loaded-reference-metadata [map-id decoded]
    (assert (= (type decoded) :table) "GraphViewPersistence load requires metadata object")
    (local out (reference-metadata map-id decoded))
    (local (panels panels-compacted?) (compact-reference-panels map-id (or out.panels []) false))
    (local (extra-panels extras-compacted?) (compact-reference-panels map-id (or out.extra_panels []) true))
    (local mode-states (clone-view-modes map-id out.view_modes))
    (when (and out.camera (not (and mode-states.spatial mode-states.spatial.camera)))
        (when (not mode-states.spatial) (set mode-states.spatial {}))
        (set mode-states.spatial.camera (clone-camera-state map-id out.camera)))
    (set out.positions (or out.positions {}))
    (set out.presentations (or out.presentations {}))
    (set out.sizes (or out.sizes {}))
    (set out.panels panels)
    (set out.extra_panels extra-panels)
    (set out.camera (clone-camera-state map-id (and mode-states.spatial mode-states.spatial.camera)))
    (set out.view_modes mode-states)
    (values out (or panels-compacted? extras-compacted?)))

(fn GraphViewPersistence [opts]
    (local options (or opts {}))
    (local data-dir options.data-dir)
    (assert data-dir "GraphViewPersistence requires data-dir")
    (local map-id (or options.map-id "main"))
    (assert (and (= (type map-id) :string)
                 (> (string.len map-id) 0)
                 (not (= (string.sub map-id 1 1) "."))
                 (not (string.find map-id "/" 1 true))
                 (not (string.find map-id "\\" 1 true))
                 (not (string.find map-id "." 1 true)))
            (.. "GraphViewPersistence: unsafe map-id: " (tostring map-id)))
    (local graph-data-dir (fs.join-path (fs.join-path data-dir "graph" "maps") map-id))
    (local metadata-path (fs.join-path graph-data-dir "metadata.json"))
    (var pending-save? false)
     (var persisted {:positions {}
                      :presentations {}
                      :sizes {}
                      :panels []
                      :extra_panels []
                      :camera nil
                      :view_modes {}})
    (var persisted-positions persisted.positions)
    (var persisted-presentations persisted.presentations)
    (var persisted-sizes persisted.sizes)
     (var persisted-panels persisted.panels)
     (var persisted-extra-panels [])
      (var persisted-camera nil)
      (var persisted-view-modes {})

     (fn ensure-graph-data-dir []
        (local (ok result) (pcall fs.create-dirs graph-data-dir))
        (when (not ok)
            (error (string.format "GraphView failed to create %s: %s"
                                  graph-data-dir
                                  result)))
        true)

    (local legacy-metadata-path (fs.join-path (fs.join-path data-dir "graph-view") "metadata.json"))

    (fn load []
        (var source-path metadata-path)
        (when (and (= map-id "main") (not (fs.exists metadata-path)) (fs.exists legacy-metadata-path))
            (set source-path legacy-metadata-path)
            (ensure-graph-data-dir))
        (when (and (not (= map-id "main"))
                   (= options.map-id nil)
                   (not (fs.exists metadata-path))
                   (fs.exists legacy-metadata-path))
            (set source-path legacy-metadata-path))
        (when (fs.exists source-path)
            (local (read-ok content) (pcall fs.read-file source-path))
            (when (not read-ok)
                (error (string.format "GraphView failed to read %s: %s"
                                      source-path
                                      content)))
            (local (parse-ok decoded) (pcall json.loads content))
            (when (not parse-ok)
                (error (string.format "GraphView failed to parse %s: %s"
                                      source-path
                                      decoded)))
            (local (candidate compacted?) (loaded-reference-metadata map-id decoded))
            (set persisted candidate)
            (set persisted-positions candidate.positions)
            (set persisted-presentations candidate.presentations)
            (set persisted-sizes candidate.sizes)
            (set persisted-panels candidate.panels)
            (set persisted-extra-panels candidate.extra_panels)
            (set persisted-camera candidate.camera)
            (set persisted-view-modes candidate.view_modes)
            (when compacted?
                (ensure-graph-data-dir)
                (JsonUtils.write-json! metadata-path persisted))))

    (fn saved-position [_self node]
        (when (and node node.key)
            (local stored (. persisted-positions node.key))
            (when stored
                (assert-valid-position node.key stored "GraphViewPersistence saved-position")
                (ensure-glm-vec3 stored))))

    (fn saved-presentation [_self node]
        (when (and node node.key)
            (local presentation (. persisted-presentations node.key))
            (when presentation
                (assert (= presentation :expanded)
                        (string.format "GraphViewPersistence saved-presentation for %s must be :expanded" node.key))
                presentation)))

    (fn saved-size [_self node]
        (when (and node node.key)
            (local stored (. persisted-sizes node.key))
            (when stored
                (assert-valid-size node.key stored "GraphViewPersistence saved-size")
                (glm.vec3 (rawget stored 1) (rawget stored 2) 0))))

    (fn saved-camera-state [_self]
        (clone-camera-state map-id persisted-camera))

    (fn saved-mode-camera-state [_self mode]
        (assert (= (type mode) :string) "GraphViewPersistence saved-mode-camera-state requires a string mode")
        (clone-camera-state map-id (and (. persisted-view-modes mode)
                                        (. persisted-view-modes mode :camera))))

    (fn capture-positions [_self points]
        (local positions {})
        (each [node point (pairs points)]
            (when (and node node.key point point.position)
                (local pos point.position)
                (assert (finite-number? pos.x)
                        (string.format "GraphViewPersistence capture has invalid x for %s" node.key))
                (assert (finite-number? pos.y)
                        (string.format "GraphViewPersistence capture has invalid y for %s" node.key))
                (assert (finite-number? pos.z)
                        (string.format "GraphViewPersistence capture has invalid z for %s" node.key))
                (local magnitude (glm.length pos))
                (assert (<= magnitude position-magnitude-threshold)
                        (string.format "GraphViewPersistence capture magnitude %.3f exceeds threshold %.0f for %s"
                                       magnitude
                                       position-magnitude-threshold
                                       node.key))
                (tset positions node.key [pos.x pos.y pos.z])))
        positions)

    (fn persist [self points force?]
        (when (or pending-save? force?)
            (ensure-graph-data-dir)
            (local positions (self:capture-positions points))
            (local merged {})
            (when persisted-positions
                (each [k v (pairs persisted-positions)]
                    (tset merged k v)))
            (each [k v (pairs positions)]
                (tset merged k v))
             (set persisted.positions merged)
              (set persisted.presentations persisted-presentations)
              (set persisted.sizes persisted-sizes)
              (set persisted.panels persisted-panels)
              (set persisted.extra_panels persisted-extra-panels)
              (set persisted.camera persisted-camera)
              (set persisted.view_modes persisted-view-modes)
              (local (write-ok err) (pcall (fn [] (JsonUtils.write-json! metadata-path persisted))))
            (when (not write-ok)
                (error (string.format "GraphView failed to write %s: %s"
                                      metadata-path
                                      err)))
            (set persisted-positions merged)
            (set pending-save? false)))

    (fn schedule-save [_self]
        (set pending-save? true))

    (fn set-presentation [_self node presentation]
        (assert (and node node.key) "GraphViewPersistence set-presentation requires a node with key")
        (if presentation
            (do
                (assert (= presentation :expanded)
                        "GraphViewPersistence only persists :expanded presentations")
                (tset persisted-presentations node.key presentation))
            (tset persisted-presentations node.key nil))
        (set persisted.presentations persisted-presentations)
        (set pending-save? true))

    (fn set-size [_self node size]
        (assert (and node node.key) "GraphViewPersistence set-size requires a node with key")
        (if size
            (do
              (assert (and (finite-number? size.x) (finite-number? size.y))
                      "GraphViewPersistence set-size requires finite size.x and size.y")
              (local sz [size.x size.y])
              (assert-valid-size node.key sz "GraphViewPersistence set-size")
              (tset persisted-sizes node.key sz))
            (tset persisted-sizes node.key nil))
        (set persisted.sizes persisted-sizes)
        (set pending-save? true))

    (fn set-camera-state [_self camera-state]
        (when (= (. persisted-view-modes :spatial) nil)
            (set (. persisted-view-modes :spatial) {}))
        (set (. persisted-view-modes :spatial :camera) (clone-camera-state map-id camera-state))
        (set persisted-camera (clone-camera-state map-id camera-state))
        (set persisted.camera persisted-camera)
        (set persisted.view_modes persisted-view-modes)
        (set pending-save? true)
        true)

    (fn set-mode-camera-state [_self mode camera-state]
        (assert (= (type mode) :string) "GraphViewPersistence set-mode-camera-state requires a string mode")
        (when (= (. persisted-view-modes mode) nil)
            (set (. persisted-view-modes mode) {}))
        (local cloned (clone-camera-state map-id camera-state))
        (set (. persisted-view-modes mode :camera) cloned)
        (when (= mode "spatial")
            (set persisted-camera (clone-camera-state map-id camera-state))
            (set persisted.camera persisted-camera))
        (set persisted.view_modes persisted-view-modes)
        (set pending-save? true)
        true)

    (fn prune-node-key [_self key]
        (assert (= (type key) :string) "GraphViewPersistence prune-node-key requires a string key")
        (tset persisted-positions key nil)
        (tset persisted-presentations key nil)
        (tset persisted-sizes key nil)
        (local kept-panels [])
        (local kept-extra-panels [])
        (each [_ panel (ipairs (or persisted-panels []))]
            (when (not (= panel.node-key key))
                (table.insert kept-panels panel)))
        (each [_ panel (ipairs (or persisted-extra-panels []))]
            (when (not (= panel.node-key key))
                (table.insert kept-extra-panels panel)))
        (set persisted-panels kept-panels)
        (set persisted-extra-panels kept-extra-panels)
        (set persisted.positions persisted-positions)
        (set persisted.presentations persisted-presentations)
        (set persisted.sizes persisted-sizes)
        (set persisted.panels persisted-panels)
        (set persisted.extra_panels persisted-extra-panels)
        (set pending-save? true)
        true)

    (fn saved-panels [_self]
        persisted-panels)

    (fn set-panels [_self panels]
        (assert (= (type panels) :table) "GraphViewPersistence set-panels requires a table")
        (set persisted-panels (ReferenceState.merge-view-panels persisted-panels panels))
        (set persisted.panels persisted-panels)
        (set pending-save? true))

    (fn saved-extra-panels [_self]
        persisted-extra-panels)

    (fn set-extra-panels [_self extra-panels]
        (assert (= (type extra-panels) :table) "GraphViewPersistence set-extra-panels requires a table")
        (set persisted-extra-panels extra-panels)
        (set persisted.extra_panels extra-panels)
        (set pending-save? true))

    (fn snapshot-state [_self]
        (R.clone persisted))

    (fn install-state! [_self metadata]
        (assert (= (type metadata) :table) "GraphViewPersistence install-state! requires metadata")
        (local candidate (reference-metadata map-id metadata))
        (set persisted candidate)
        (set persisted-positions (or candidate.positions {}))
        (set persisted-presentations (or candidate.presentations {}))
        (set persisted-sizes (or candidate.sizes {}))
        (set persisted-panels (or candidate.panels []))
        (set persisted-extra-panels (or candidate.extra_panels []))
        (set persisted-camera candidate.camera)
        (set persisted-view-modes (or candidate.view_modes {}))
        (set pending-save? false)
        true)

    (local self {:load load
                 :persist persist
                 :schedule-save schedule-save
                 :saved-position saved-position
                 :saved-presentation saved-presentation
                  :saved-size saved-size
                   :saved-camera-state saved-camera-state
                   :saved-mode-camera-state saved-mode-camera-state
                  :saved-panels saved-panels
                 :saved-extra-panels saved-extra-panels
                   :set-size set-size
                    :set-camera-state set-camera-state
                    :set-mode-camera-state set-mode-camera-state
                   :set-presentation set-presentation
                  :prune-node-key prune-node-key
                  :set-panels set-panels
                 :set-extra-panels set-extra-panels
                 :capture-positions capture-positions
                 :snapshot-state snapshot-state
                 :install-state! install-state!
                 :metadata-path metadata-path})

    (self:load)
    self)

(set finite-number?
     (fn [value]
         (and (= (type value) :number)
              (= value value)
              (not (= value math.huge))
              (not (= value (- math.huge))))))

(set assert-valid-position
     (fn [key value context]
         (local prefix (or context "GraphViewPersistence position"))
         (assert (= (type value) :table)
                 (string.format "%s for %s must be a table" prefix key))
         (assert (finite-number? (rawget value 1))
                 (string.format "%s for %s has invalid x value" prefix key))
         (assert (finite-number? (rawget value 2))
                 (string.format "%s for %s has invalid y value" prefix key))
         (assert (finite-number? (rawget value 3))
                 (string.format "%s for %s has invalid z value" prefix key))
         (local magnitude (glm.length (ensure-glm-vec3 value)))
         (assert (<= magnitude position-magnitude-threshold)
                 (string.format "%s for %s magnitude %.3f exceeds threshold %.0f"
                                prefix
                                key
                                magnitude
                                position-magnitude-threshold))))

(set assert-valid-size
     (fn [key value context]
         (local prefix (or context "GraphViewPersistence size"))
         (assert (= (type value) :table)
                 (string.format "%s for %s must be a table" prefix key))
         (assert (finite-number? (rawget value 1))
                 (string.format "%s for %s has invalid x value" prefix key))
         (assert (finite-number? (rawget value 2))
                 (string.format "%s for %s has invalid y value" prefix key))
         (assert (>= (rawget value 1) 0)
                 (string.format "%s for %s has negative x value" prefix key))
         (assert (>= (rawget value 2) 0)
                 (string.format "%s for %s has negative y value" prefix key))))

GraphViewPersistence
