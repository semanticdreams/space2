(fn context-prefix [context]
    (if context
        (.. context ": ")
        "GraphIslands: "))

(fn assert-non-empty-string [value label context]
    (assert (= (type value) "string")
            (.. (context-prefix context) label " must be a string"))
    (assert (> (string.len value) 0)
            (.. (context-prefix context) label " must be non-empty"))
    value)

(fn clone-value [value]
    (if (= (type value) "table")
        (do
            (local copy {})
            (each [k v (pairs value)]
                (set (. copy k) (clone-value v)))
            copy)
        value))

(fn position-array? [value]
    (and (= (type value) "table")
         (= (type (. value 1)) "number")
         (= (type (. value 2)) "number")
         (= (type (. value 3)) "number")))

(fn vec3-components [value]
    (pcall (fn [] (values value.x value.y value.z))))

(fn vec3-like? [value]
    (when value
        (local (ok x y z) (vec3-components value))
        (and ok
             (= (type x) "number")
             (= (type y) "number")
             (= (type z) "number"))))

(fn normalize-state-position [position context]
    (if (= position nil)
        nil
        (position-array? position)
        [(. position 1) (. position 2) (. position 3)]
        (vec3-like? position)
        [position.x position.y position.z]
        (error (.. (context-prefix context) "state.position must be a [x y z] array or vec3-like value"))))

(fn clone-state [state context]
    (local copy {})
    (each [k v (pairs state)]
        (if (= k :position)
            (set (. copy k) (normalize-state-position v context))
            (set (. copy k) (clone-value v))))
    copy)

(fn clone-members [members]
    (icollect [_ key (ipairs members)] key))

(fn clone-record [record]
    {:id record.id
     :kind record.kind
     :members (clone-members record.members)
     :state (clone-state (or record.state {}) "GraphIslands.clone-record")})

(fn normalize-record [record context]
    (assert (= (type record) "table")
            (.. (context-prefix context) "record must be a table"))
    (local id (assert-non-empty-string record.id "id" context))
    (local kind (assert-non-empty-string record.kind "kind" context))
    (local members record.members)
    (assert (= (type members) "table")
            (.. (context-prefix context) "members must be a table"))
    (assert (> (length members) 0)
            (.. (context-prefix context) "members must contain at least one key"))
    (local seen {})
    (local normalized-members [])
    (each [index key (ipairs members)]
        (assert-non-empty-string key (.. "members[" index "]") context)
        (assert (not (. seen key))
                (.. (context-prefix context) "members must not contain duplicate key: " key))
        (set (. seen key) true)
        (table.insert normalized-members key))
    (assert (= (length normalized-members) (length members))
            (.. (context-prefix context) "members must be an array"))
    (each [key _value (pairs members)]
        (assert (and (= (type key) "number")
                     (>= key 1)
                     (<= key (length members))
                     (= key (math.floor key)))
                (.. (context-prefix context) "members must be an array")))
    (local state (if (= record.state nil) {} record.state))
    (assert (= (type state) "table")
            (.. (context-prefix context) "state must be a table"))
    {:id id
     :kind kind
     :members normalized-members
     :state (clone-state state context)})

(fn values-equal? [left right]
    (if (not (= (type left) (type right)))
        false
        (if (not (= (type left) "table"))
            (= left right)
            (do
                (each [k v (pairs left)]
                    (when (not (values-equal? v (. right k)))
                        (lua "return false")))
                (each [k _ (pairs right)]
                    (when (= (. left k) nil)
                        (lua "return false")))
                true))))

{:clone-record clone-record
 :normalize-record normalize-record
 :records-equal? values-equal?}
