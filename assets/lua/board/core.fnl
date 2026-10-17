(local glm (require :glm))
(local Signal (require :signal))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(local transform-magnitude-threshold 1e6)

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn assert-valid-vec3 [value context]
  (assert value (.. context " requires vec3 value"))
  (assert (finite-number? value.x) (.. context " has invalid x"))
  (assert (finite-number? value.y) (.. context " has invalid y"))
  (assert (finite-number? value.z) (.. context " has invalid z"))
  (local magnitude (glm.length value))
  (assert (<= magnitude transform-magnitude-threshold)
          (string.format "%s magnitude %.3f exceeds threshold %.0f"
                         context
                         magnitude
                         transform-magnitude-threshold))
  value)

(fn assert-valid-quat [value context]
  (assert value (.. context " requires quat value"))
  (assert (finite-number? value.w) (.. context " has invalid w"))
  (assert (finite-number? value.x) (.. context " has invalid x"))
  (assert (finite-number? value.y) (.. context " has invalid y"))
  (assert (finite-number? value.z) (.. context " has invalid z"))
  value)

(fn vec3->array [value]
  (if value
      [value.x value.y value.z]
      nil))

(fn quat->array [value]
  (if value
      [value.w value.x value.y value.z]
      nil))

(fn array->vec3 [value fallback]
  (if (and (or (= (type value) :table)
               (= (type value) :userdata))
           value.x)
      value
      (= (type value) :table)
      (do
        (assert (and (>= (length value) 3)
                     (not (= (. value 1) nil))
                     (not (= (. value 2) nil))
                     (not (= (. value 3) nil)))
                "Board persisted vec3 requires 3 non-nil elements")
        (glm.vec3 (. value 1)
                  (. value 2)
                  (. value 3)))
      fallback))

(fn array->quat [value fallback]
  (if (and (or (= (type value) :table)
               (= (type value) :userdata))
           value.w)
      value
      (= (type value) :table)
      (do
        (assert (and (>= (length value) 4)
                     (not (= (. value 1) nil))
                     (not (= (. value 2) nil))
                     (not (= (. value 3) nil))
                     (not (= (. value 4) nil)))
                "Board persisted quat requires 4 non-nil elements")
        (glm.quat (. value 1)
                  (. value 2)
                  (. value 3)
                  (. value 4)))
      fallback))

(fn next-id [prefix seq]
  (.. prefix "-" seq))

(fn id-seq [prefix id]
  (when (= (type id) :string)
    (local suffix (string.match id (.. "^" prefix "%-(%d+)$")))
    (and suffix (tonumber suffix))))

(fn remove-record! [map ordered id record]
  (set (. map id) nil)
  (for [idx (length ordered) 1 -1]
    (when (= (. ordered idx) record)
      (table.remove ordered idx))))

(fn Board [opts]
  (local options (or opts {}))
  (local items {})
  (local items-in-order [])
  (local connectors {})
  (local connectors-in-order [])
  (var item-seq 0)
  (var connector-seq 0)
  (local item-added (Signal))
  (local item-removed (Signal))
  (local item-updated (Signal))
  (local connector-added (Signal))
  (local connector-removed (Signal))

  (fn add-item [self spec]
    (local previous-item-seq item-seq)
    (local (ok result)
      (pcall
        (fn []
          (local item-spec (or spec {}))
          (local item-type (assert item-spec.type "Board.add-item requires :type"))
          (local explicit-id item-spec.id)
          (set item-seq (+ item-seq 1))
          (local id (tostring (or explicit-id (next-id "item" item-seq))))
          (local restored-seq (id-seq "item" id))
          (when (and explicit-id restored-seq (> restored-seq item-seq))
            (set item-seq restored-seq))
          (assert (not (. items id)) (.. "Duplicate board item id: " id))
          (local position (assert-valid-vec3
                            (array->vec3 item-spec.position (or item-spec.position-vec (glm.vec3 0 0 0)))
                            (.. "Board item " id " position")))
          (local rotation (assert-valid-quat
                            (array->quat item-spec.rotation (or item-spec.rotation-quat (glm.quat 1 0 0 0)))
                            (.. "Board item " id " rotation")))
          (local size (assert-valid-vec3
                        (array->vec3 item-spec.size (or item-spec.size-vec (glm.vec3 32 16 0)))
                        (.. "Board item " id " size")))
          (local item {:id id
                       :type item-type
                       :subject-key item-spec.subject-key
                       :position position
                       :rotation rotation
                       :size size
                       :state (clone-table (or item-spec.state {}))})
          (set (. items id) item)
          (table.insert items-in-order item)
          (local (emit-ok emit-err)
            (pcall (fn [] (item-added:emit item))))
          (when (not emit-ok)
            (remove-record! items items-in-order id item)
            (item-removed:emit item)
            (error emit-err))
          item)))
    (when (not ok)
      (set item-seq previous-item-seq)
      (error result))
    result)

  (fn remove-item [self item-or-id]
    (local id (if (= (type item-or-id) :table) item-or-id.id item-or-id))
    (local item (and id (. items id)))
    (when item
      (local affected-connectors [])
      (for [idx (length connectors-in-order) 1 -1]
        (local connector (. connectors-in-order idx))
        (when (or (= connector.source-item-id id)
                  (= connector.target-item-id id))
          (table.insert affected-connectors {:connector connector
                                             :index idx})))
      (var removed-connectors [])
      (local (remove-connectors-ok remove-connectors-err)
        (pcall
          (fn []
            (each [_ entry (ipairs affected-connectors)]
              (self:remove-connector entry.connector.id)
              (table.insert removed-connectors entry)))))
      (when (not remove-connectors-ok)
        (for [i (length removed-connectors) 1 -1]
          (local entry (. removed-connectors i))
          (local c entry.connector)
          (set (. connectors c.id) c)
          (table.insert connectors-in-order entry.index c)
          (pcall (fn [] (connector-added:emit c))))
        (error remove-connectors-err))
      (set (. items id) nil)
      (var ordered-index nil)
      (for [idx (length items-in-order) 1 -1]
        (when (= (. items-in-order idx) item)
          (set ordered-index idx)))
      (when ordered-index
        (table.remove items-in-order ordered-index))
      (local (emit-ok emit-err)
        (pcall (fn [] (item-removed:emit item))))
      (when (not emit-ok)
        (set (. items id) item)
        (when ordered-index
          (table.insert items-in-order ordered-index item))
        (for [i (length affected-connectors) 1 -1]
          (local entry (. affected-connectors i))
          (local c entry.connector)
          (set (. connectors c.id) c)
          (table.insert connectors-in-order entry.index c)
          (pcall (fn [] (connector-added:emit c))))
        (pcall (fn [] (item-added:emit item)))
        (error emit-err))
      item))

  (fn update-item-transform [self item-or-id transform]
    (local id (if (= (type item-or-id) :table) item-or-id.id item-or-id))
    (local item (assert (. items id) (.. "Board.update-item-transform missing item: " (tostring id))))
    (local tx (or transform {}))
    (local previous-position item.position)
    (local previous-rotation item.rotation)
    (local previous-size item.size)
    (local next-position (if tx.position
                             (assert-valid-vec3 tx.position
                                                (.. "Board item " id " position"))
                             previous-position))
    (local next-rotation (if tx.rotation
                             (assert-valid-quat tx.rotation
                                                (.. "Board item " id " rotation"))
                             previous-rotation))
    (local next-size (if tx.size
                         (assert-valid-vec3 tx.size
                                            (.. "Board item " id " size"))
                         previous-size))
    (set item.position next-position)
    (set item.rotation next-rotation)
    (set item.size next-size)
    (local (ok err)
      (pcall (fn [] (item-updated:emit item))))
    (when (not ok)
      (set item.position previous-position)
      (set item.rotation previous-rotation)
      (set item.size previous-size)
      (pcall (fn [] (item-updated:emit item)))
      (error err))
    item)

  (fn add-connector [self spec]
    (local previous-connector-seq connector-seq)
    (local (ok result)
      (pcall
        (fn []
          (local connector-spec (or spec {}))
          (local source-id (assert connector-spec.source-item-id
                                   "Board.add-connector requires :source-item-id"))
          (local target-id (assert connector-spec.target-item-id
                                   "Board.add-connector requires :target-item-id"))
          (assert (. items source-id) (.. "Board.add-connector missing source item: " source-id))
          (assert (. items target-id) (.. "Board.add-connector missing target item: " target-id))
          (local explicit-id connector-spec.id)
          (set connector-seq (+ connector-seq 1))
          (local id (tostring (or explicit-id (next-id "connector" connector-seq))))
          (local restored-seq (id-seq "connector" id))
          (when (and explicit-id restored-seq (> restored-seq connector-seq))
            (set connector-seq restored-seq))
          (assert (not (. connectors id)) (.. "Duplicate board connector id: " id))
          (local kind (or connector-spec.kind "visual"))
          (local link-id connector-spec.semantic-link-id)
          (when (= kind "semantic-link")
            (assert (and link-id (not (= (tostring link-id) "")))
                    "Board.add-connector semantic-link kind requires non-empty :semantic-link-id"))
          (when (and link-id (not (= (tostring link-id) "")))
            (assert (= kind "semantic-link")
                    "Board.add-connector semantic-link-id requires kind \"semantic-link\""))
          (local connector {:id id
                            :source-item-id source-id
                            :target-item-id target-id
                            :kind kind
                            :semantic-link-id link-id
                            :state (clone-table (or connector-spec.state {}))})
          (set (. connectors id) connector)
          (table.insert connectors-in-order connector)
          (local (emit-ok emit-err)
            (pcall (fn [] (connector-added:emit connector))))
          (when (not emit-ok)
            (remove-record! connectors connectors-in-order id connector)
            (connector-removed:emit connector)
            (error emit-err))
          connector)))
    (when (not ok)
      (set connector-seq previous-connector-seq)
      (error result))
    result)

  (fn remove-connector [_self connector-or-id]
    (local id (if (= (type connector-or-id) :table) connector-or-id.id connector-or-id))
    (local connector (and id (. connectors id)))
    (when connector
      (set (. connectors id) nil)
      (var ordered-index nil)
      (for [idx (length connectors-in-order) 1 -1]
        (when (= (. connectors-in-order idx) connector)
          (set ordered-index idx)))
      (when ordered-index
        (table.remove connectors-in-order ordered-index))
      (local (emit-ok emit-err)
        (pcall (fn [] (connector-removed:emit connector))))
      (when (not emit-ok)
        (set (. connectors id) connector)
        (when ordered-index
          (table.insert connectors-in-order ordered-index connector))
        (pcall (fn [] (connector-added:emit connector)))
        (error emit-err))
      connector))

  (fn capture-state [_self]
    {:items (icollect [_ item (ipairs items-in-order)]
              {:id item.id
               :type item.type
               :subject-key item.subject-key
               :position (vec3->array item.position)
               :rotation (quat->array item.rotation)
               :size (vec3->array item.size)
               :state (clone-table item.state)})
     :connectors (icollect [_ connector (ipairs connectors-in-order)]
                   {:id connector.id
                    :source-item-id connector.source-item-id
                    :target-item-id connector.target-item-id
                    :kind connector.kind
                    :semantic-link-id connector.semantic-link-id
                    :state (clone-table connector.state)})})

  (fn restore-state [self state]
    (local previous-state (self:capture-state))
    (local previous-item-seq item-seq)
    (local previous-connector-seq connector-seq)
    (local payload (or state {}))
    (local validation-board (Board {}))
    (each [_ item (ipairs (or payload.items []))]
      (validation-board:add-item item))
    (each [_ connector (ipairs (or payload.connectors []))]
      (validation-board:add-connector connector))
    (local (ok result)
      (pcall
        (fn []
          (each [_ item (ipairs (icollect [_ current (ipairs items-in-order)] current))]
            (self:remove-item item.id))
          (set item-seq 0)
          (set connector-seq 0)
          (each [_ item (ipairs (or payload.items []))]
            (self:add-item item))
          (each [_ connector (ipairs (or payload.connectors []))]
            (self:add-connector connector))
          true)))
    (when (not ok)
      (local (rollback-ok rollback-err)
        (pcall
          (fn []
            (each [_ item (ipairs (icollect [_ current (ipairs items-in-order)] current))]
              (self:remove-item item.id))
            (set item-seq 0)
            (set connector-seq 0)
            (each [_ item (ipairs previous-state.items)]
              (self:add-item item))
            (each [_ connector (ipairs previous-state.connectors)]
              (self:add-connector connector)))))
      (when (not rollback-ok)
        (set item-seq previous-item-seq)
        (set connector-seq previous-connector-seq)
        (error (.. (tostring result)
                   " (board restore rollback failed: "
                   (tostring rollback-err)
                   ")")))
      (set item-seq previous-item-seq)
      (set connector-seq previous-connector-seq)
      (error result))
    result)

  (fn update-item-subject [_self item-id subject-key item-type]
    (local item (assert (. items item-id) (.. "Board.update-item-subject missing item: " (tostring item-id))))
    (assert (= (type subject-key) :string) "Board.update-item-subject requires subject-key")
    (assert (= (type item-type) :string) "Board.update-item-subject requires item-type")
    (when (not (and (= item.subject-key subject-key) (= item.type item-type)))
      (local previous-key item.subject-key)
      (local previous-type item.type)
      (set item.subject-key subject-key)
      (set item.type item-type)
      (local (ok err) (pcall item-updated.emit item-updated item))
      (when (not ok)
        (set item.subject-key previous-key)
        (set item.type previous-type)
        (pcall item-updated.emit item-updated item)
        (error err)))
    item)

  (local self {:items items
               :items-in-order items-in-order
               :connectors connectors
               :connectors-in-order connectors-in-order
               :item-added item-added
               :item-removed item-removed
               :item-updated item-updated
               :connector-added connector-added
               :connector-removed connector-removed
               :add-item add-item
               :remove-item remove-item
               :update-item-transform update-item-transform
               :update-item-subject update-item-subject
               :add-connector add-connector
               :remove-connector remove-connector
               :capture-state capture-state
               :restore-state restore-state})
  (when options.state
    (self:restore-state options.state))
  self)

{:Board Board}
