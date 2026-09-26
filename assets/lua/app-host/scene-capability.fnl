(fn scene-error [message]
  (error (.. "[app-host.scene] " message)))

(local supported-kinds {:custom true
                        :panel true
                        :cube true})

(fn table? [value]
  (= (type value) :table))

(fn copy-array [items]
  (local out [])
  (when items
    (each [_ item (ipairs items)]
      (table.insert out item)))
  out)

(fn component [value index label]
  (local item (. value index))
  (when (= item nil)
    (scene-error (.. label " requires three components")))
  item)

(fn vector3 [value fallback]
  (if value
      [(component value 1 "vector3")
       (component value 2 "vector3")
       (component value 3 "vector3")]
      (copy-array fallback)))

(fn make-transform [source]
  (local value (if source source {}))
  {:position (vector3 value.position [0 0 0])
   :rotation (if value.rotation (copy-array value.rotation) nil)
   :size (vector3 value.size [1 1 1])})

(fn copy-transform [transform]
  {:position (copy-array transform.position)
   :rotation (if transform.rotation (copy-array transform.rotation) nil)
   :size (copy-array transform.size)})

(fn bounds-from-center-size [center size]
  (local center3 (vector3 center nil))
  (local size3 (vector3 size nil))
  (local half [(/ (. size3 1) 2)
               (/ (. size3 2) 2)
               (/ (. size3 3) 2)])
  {:min [(- (. center3 1) (. half 1))
         (- (. center3 2) (. half 2))
         (- (. center3 3) (. half 3))]
   :max [(+ (. center3 1) (. half 1))
         (+ (. center3 2) (. half 2))
         (+ (. center3 3) (. half 3))]})

(fn normalize-bounds [bounds]
  (when (not (table? bounds))
    (scene-error "query-volume requires bounds table"))
  (if (and bounds.min bounds.max)
      {:min (vector3 bounds.min [0 0 0])
       :max (vector3 bounds.max [0 0 0])}
      (if (and bounds.center bounds.size)
          (bounds-from-center-size bounds.center bounds.size)
          (scene-error "query-volume requires bounds min/max or center/size"))))

(fn transform-bounds [transform]
  (bounds-from-center-size transform.position transform.size))

(fn overlaps? [a b]
  (and (<= (. a.min 1) (. b.max 1))
       (>= (. a.max 1) (. b.min 1))
       (<= (. a.min 2) (. b.max 2))
       (>= (. a.max 2) (. b.min 2))
       (<= (. a.min 3) (. b.max 3))
       (>= (. a.max 3) (. b.min 3))))

(fn tag-set [tags]
  (local out {})
  (when tags
    (each [_ tag (ipairs tags)]
      (set (. out tag) true)))
  out)

(fn tag-matches? [record requested-tags]
  (if (= requested-tags nil)
      true
      (= (# requested-tags) 0)
      true
      (do
       (local owned-tags (tag-set record.tags))
       (var matched? false)
       (each [_ tag (ipairs requested-tags)]
         (when (. owned-tags tag)
           (set matched? true)))
       matched?)))

(fn create [opts]
  (when (and (not (= opts nil)) (not (table? opts)))
    (scene-error "create requires opts table"))
  (local options (if opts opts {}))
  (local backend options.backend)
  (local records [])
  (local records-by-token {})
  (var next-token 0)
  (var dropped? false)

  (fn remove-record [record]
    (var removed? false)
    (for [i (# records) 1 -1]
      (when (= (. records i) record)
        (table.remove records i)
        (set removed? true)))
    (set (. records-by-token record.token) nil)
    removed?)

  (fn record-for-handle [handle]
    (when (not (table? handle))
      (scene-error "invalid scene handle"))
    (local token handle._scene-token)
    (local record (and token (. records-by-token token)))
    (when (not record)
      (scene-error "invalid scene handle"))
    (when (not (= record.handle handle))
      (scene-error "invalid scene handle"))
    record)

  (fn spawn [_self spec]
    (when (not (table? spec))
      (scene-error "spawn requires spec table"))
    (local kind spec.kind)
    (when (not (. supported-kinds kind))
      (scene-error (.. "unsupported spawn kind: " (tostring kind))))
    (set next-token (+ next-token 1))
    (local handle {:id (if (= spec.id nil) next-token spec.id)
                   :kind kind
                   :tags (copy-array spec.tags)
                   :_scene-token next-token})
    (local record {:token next-token
                   :handle handle
                   :id handle.id
                   :kind kind
                   :tags handle.tags
                   :solid? spec.solid?
                   :transform (make-transform spec)})
    (table.insert records record)
    (set (. records-by-token next-token) record)
    handle)

  (fn despawn [_self handle]
    (local record (record-for-handle handle))
    (when (and backend (= (type backend.despawn) :function))
      (backend:despawn handle))
    (remove-record record))

  (fn set-transform [_self handle transform]
    (when (not (table? transform))
      (scene-error "set-transform requires transform table"))
    (local record (record-for-handle handle))
    (set record.transform (make-transform transform))
    (copy-transform record.transform))

  (fn get-transform [_self handle]
    (local record (record-for-handle handle))
    (copy-transform record.transform))

  (fn list-owned [_self]
    (local out [])
    (each [_ record (ipairs records)]
      (table.insert out record.handle))
    out)

  (fn query-volume [_self bounds opts]
    (local query-bounds (normalize-bounds bounds))
    (local query-opts (if opts opts {}))
    (local hits [])
    (each [_ record (ipairs records)]
      (when (and (tag-matches? record query-opts.tags)
                 (overlaps? query-bounds (transform-bounds record.transform)))
        (table.insert hits {:handle record.handle
                            :id record.id
                            :kind record.kind
                            :tags (copy-array record.tags)
                            :solid? record.solid?
                            :position (copy-array record.transform.position)
                            :source :owned})))
    hits)

  (fn raycast-terrain [_self ray opts]
    (if (and backend (= (type backend.raycast-terrain) :function))
        (backend:raycast-terrain ray opts)
        nil))

  (fn height-at [_self point opts]
    (if (and backend (= (type backend.height-at) :function))
        (backend:height-at point opts)
        nil))

  (fn drop [self]
    (when (not dropped?)
      (set dropped? true)
      (local owned (self:list-owned))
      (each [_ handle (ipairs owned)]
        (self:despawn handle)))
    nil)

  {:spawn spawn
   :despawn despawn
   :set-transform set-transform
   :get-transform get-transform
   :list-owned list-owned
   :query-volume query-volume
   :raycast-terrain raycast-terrain
   :height-at height-at
   :drop drop})

{:create create}
