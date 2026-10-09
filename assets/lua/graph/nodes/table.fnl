(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local TableNodeView (require :graph/view/views/table))
(local Signal (require :signal))
(local logging (require :logging))

(local default-key-limit 36)
(local default-value-limit 64)
(var TableNode nil)

(fn safe-tostring [value]
    (local (ok result) (pcall (fn [] (tostring value))))
    (if ok result "<error>"))

(fn userdata-label [value]
    (local (mt-ok mt) (pcall (fn [] (debug.getmetatable value))))
    (local name (and mt-ok (= (type mt) :table) (= (type mt.__name) :string) mt.__name))
    (if name
        (.. "<userdata:" name ">")
        "<userdata>"))

(fn metatable-table-label [value]
    (local (mt-ok mt) (pcall (fn [] (debug.getmetatable value))))
    (local name (and mt-ok (= (type mt) :table) (= (type mt.__name) :string) mt.__name))
    (if name
        (.. "<table:" name ">")
        "<table>"))

(fn metatable-backed-table? [value]
    (local (mt-ok mt) (pcall (fn [] (debug.getmetatable value))))
    (and mt-ok mt))

(fn trim-text [_self text limit]
    (local str (safe-tostring text))
    (local resolved (math.max 3 (or limit 3)))
    (if (<= (string.len str) resolved)
        str
        (.. (string.sub str 1 (- resolved 1)) "…")))

(fn safe-read [_self tbl key]
    (if (not (= (type tbl) :table))
        nil
        (do
            (local (ok value) (pcall (fn [] (. tbl key))))
            (if ok value nil))))

(fn resolve-table-label [self tbl]
    (if (not (= (type tbl) :table))
        nil
        (do
            (local name (self:safe-read tbl "name"))
            (local title (self:safe-read tbl "title"))
            (local id (self:safe-read tbl "id"))
            (local label (or (and (= (type name) :string) name)
                             (and (= (type title) :string) title)
                             (and (= (type id) :string) id)))
            (if label
                (self:trim-text label self.value-limit)
                nil))))

(fn describe-key [self key]
    (local key-type (type key))
    (local base
        (if (= key-type :string)
            key
            (if (= key-type :userdata)
                (.. "[" key-type "] " (userdata-label key))
                (if (and (= key-type :table) (metatable-backed-table? key))
                    (.. "[" key-type "] " (metatable-table-label key))
                    (.. "[" key-type "] " (safe-tostring key))))))
    (self:trim-text base self.key-limit))

(fn describe-table-value [self value]
    (local (mt-ok mt) (pcall (fn [] (debug.getmetatable value))))
    (if (and mt-ok mt)
        (do
            (local resolved (self:resolve-table-label value))
            (self:trim-text (if resolved resolved (metatable-table-label value)) self.value-limit))
        (do
            (local resolved (self:resolve-table-label value))
            (or resolved (self:trim-text (safe-tostring value) self.value-limit)))))

(fn describe-non-table [self value value-type]
    (if (= value-type :nil)
        "nil"
        (if (= value-type :userdata)
            (self:trim-text (userdata-label value) self.value-limit)
            (self:trim-text (safe-tostring value) self.value-limit))))

(fn describe-value [self value]
    (local value-type (type value))
    (if (= value-type :string)
        (do
            (local inner-limit (math.max 1 (- self.value-limit 2)))
            (local inner (self:trim-text value inner-limit))
            (.. "\"" inner "\""))
        (if (or (= value-type :number) (= value-type :boolean))
            (self:trim-text (safe-tostring value) self.value-limit)
            (if (= value-type :table)
                (describe-table-value self value)
                (describe-non-table self value value-type)))))

(fn entry-label [self entry]
    (local key-text (self:describe-key entry.key))
    (local value-text (self:describe-value entry.value))
    (if (= entry.value-type :table)
        (.. key-text " (table)")
        (.. key-text " = " value-text)))

(fn key-fragment [self key]
    (local fragment (self:describe-key key))
    (select 1 (string.gsub fragment "[/%s]+" "-")))

(fn child-key [self entry]
    (local base (tostring (or self.key "table")))
    (local fragment (self:key-fragment entry.key))
    (.. base "/" fragment))

(fn child-label [self entry]
    (self:entry-label entry))

(fn create-value-node [self entry]
    (GraphNode {:key (self:child-key entry)
                    :label (self:child-label entry)
                    :color (glm.vec4 0.7 0.75 0.9 1)
                    :sub-color (glm.vec4 0.55 0.6 0.75 1)
                    :size 7.0}))

(fn create-child-node [self entry]
    (if (= entry.value-type :table)
        (TableNode {:table entry.value
                    :label (self:child-label entry)
                    :key (self:child-key entry)
                    :key-limit self.key-limit
                    :value-limit self.value-limit})
        (create-value-node self entry)))

(fn sanitize-label [label]
    (select 1 (string.gsub (tostring label) "%s+" "-")))

(fn table-key [options tbl label]
    (if options.key
        (tostring options.key)
        (.. "table:" (sanitize-label label) ":"
            (if (metatable-backed-table? tbl)
                (sanitize-label (metatable-table-label tbl))
                (select 1 (string.gsub (safe-tostring tbl) "%s+" ""))))))

(fn table-label [options tbl]
    (or options.label
        (if (metatable-backed-table? tbl)
            (metatable-table-label tbl)
            (select 1 (string.gsub (safe-tostring tbl) "%s+" " ")))))

(set TableNode (fn [opts]
    (local options (or opts {}))
    (local tbl (or options.table options.target))
    (assert (= (type tbl) :table) "TableNode requires a table target")
    (local label (table-label options tbl))
    (local node (GraphNode {:key (table-key options tbl label)
                                :label label
                                :color (glm.vec4 0.8 0.45 0.95 1)
                                :sub-color (glm.vec4 0.65 0.35 0.85 1)
                                :size 9.0
                                :view TableNodeView}))
    (set node.table tbl)
    (set node.key-limit (math.max 8 (or options.key-limit default-key-limit)))
    (set node.value-limit (math.max 8 (or options.value-limit default-value-limit)))
    (set node.safe-tostring safe-tostring)
    (set node.trim-text trim-text)
    (set node.safe-read safe-read)
    (set node.resolve-table-label resolve-table-label)
    (set node.describe-key describe-key)
    (set node.describe-value describe-value)
    (set node.entry-label entry-label)
    (set node.key-fragment key-fragment)
    (set node.child-key child-key)
    (set node.child-label child-label)
    (set node.create-child-node create-child-node)
    (set node.items-changed (Signal))
    (set node.build-entry
         (fn [self key value]
             (local entry {:key key
                           :value value
                           :value-type (type value)})
             (set entry.key-text (self:describe-key key))
             (set entry.value-text (self:describe-value value))
             (set entry.label (self:entry-label entry))
             entry))
    (set node.collect-entries
         (fn [self]
             (local entries [])
             (var count 0)

             (fn collect-one [entry-key entry-value]
                 (set count (+ count 1))
                 (local (entry-ok entry)
                        (pcall (fn [] (self:build-entry entry-key entry-value))))
                 (when entry-ok
                     (table.insert entries entry)))

             (local (ok err)
                    (pcall
                        (fn []
                            (each [entry-key entry-value (pairs self.table)]
                                (collect-one entry-key entry-value)))))
             (when (not ok)
                 (logging.warn (.. "[TableNode] failed to inspect table: " err)))
             (table.sort entries
                 (fn [a b]
                     (< (string.lower a.key-text) (string.lower b.key-text))))
             entries))
    (set node.build-items
         (fn [self]
             (local entries (self:collect-entries))
             (set self.entries entries)
             (icollect [_ entry (ipairs entries)]
                 [entry (or entry.label entry.key-text)])))
    (set node.emit-items
         (fn [self]
             (local items (self:build-items))
             (when self.items-changed
                 (self.items-changed:emit items))
             items))
    (set node.open-entry
         (fn [self entry]
             (when (and entry self.create-child-node)
                 (local graph self.graph)
                 (assert graph "Table node requires a mounted graph")
                 (local child (self:create-child-node entry))
                 (graph:add-edge (GraphEdge {:source self
                                                 :target child})))))
    (set node.actions
         [{:name "Refresh"
           :icon "refresh"
           :fn (fn [_button _event]
                   (node:emit-items))}])
    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))
    node))

{:TableNode TableNode}
