(local fields [:id :label :action-name :icon :browser-key])

(fn copy-descriptor [descriptor]
  {:id descriptor.id
   :label descriptor.label
   :action-name descriptor.action-name
   :icon descriptor.icon
   :browser-key descriptor.browser-key})

(fn validate-sequence [types]
  (assert (= (type types) "table") "EntityTypeCatalog :types must be a dense sequence")
  (var count 0)
  (var maximum 0)
  (each [index _ (pairs types)]
    (assert (and (= (type index) "number") (> index 0) (= (% index 1) 0))
            "EntityTypeCatalog :types must be a dense sequence")
    (set count (+ count 1))
    (set maximum (math.max maximum index)))
  (assert (= count maximum) "EntityTypeCatalog :types must be a dense sequence"))

(fn validate-descriptor [descriptor]
  (assert (= (type descriptor) "table") "EntityTypeCatalog descriptor must be a table")
  (each [_ field (ipairs fields)]
    (local value (. descriptor field))
    (assert (and (= (type value) "string") (> (length value) 0))
            (.. "EntityTypeCatalog descriptor :" field " must be a nonempty string"))))

(fn EntityTypeCatalog [opts]
  (local types opts.types)
  (validate-sequence types)
  (local ordered [])
  (local by-id {})
  (each [_ descriptor (ipairs types)]
    (validate-descriptor descriptor)
    (assert (not (. by-id descriptor.id))
            (.. "EntityTypeCatalog duplicate type: " descriptor.id))
    (local copied (copy-descriptor descriptor))
    (table.insert ordered copied)
    (tset by-id copied.id copied))
  {:list-types (fn [_self]
                 (icollect [_ descriptor (ipairs ordered)]
                   (copy-descriptor descriptor)))
   :get-type (fn [_self id]
               (copy-descriptor
                 (assert (. by-id id)
                         (.. "EntityTypeCatalog unknown type: " (tostring id)))))})

{:EntityTypeCatalog EntityTypeCatalog}
