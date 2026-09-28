(local allowed-keys
  {:id true :version true :capabilities true :priority true
   :parse true :format true :calendar true :business-calendar true})

(fn sequential-length [items]
  (var count 0)
  (var max-index 0)
  (each [key _value (pairs items)]
    (assert (and (= (type key) :number)
                 (> key 0)
                 (= key (math.floor key)))
            "temporal provider capabilities must be a sequential array")
    (set count (+ count 1))
    (when (> key max-index)
      (set max-index key)))
  (assert (= count max-index) "temporal provider capabilities must be a sequential array")
  count)

(fn copy-array [items]
  (local out [])
  (each [_ value (ipairs items)]
    (table.insert out value))
  out)

(fn has-operational-field? [provider]
  (if (= (type provider.parse) :function)
      true
      (= (type provider.format) :function)
      true
      (= (type provider.calendar) :function)
      true
      (= (type provider.calendar) :table)
      true
      (= (type provider.business-calendar) :function)
      true
      (= (type provider.business-calendar) :table)
      true
      false))

(fn validate-capabilities [provider]
  (assert (= (type provider.capabilities) :table) "temporal provider capabilities must be an array")
  (assert (> (sequential-length provider.capabilities) 0) "temporal provider capabilities must not be empty")
  (local seen {})
  (each [_ capability (ipairs provider.capabilities)]
    (assert (= (type capability) :string) "temporal provider capability must be a keyword")
    (assert (not (. seen capability)) "duplicate temporal provider capability")
    (tset seen capability true)))

(fn validate-provider [provider]
  (assert (= (type provider) :table) "temporal provider must be a table")
  (each [key _value (pairs provider)]
    (assert (. allowed-keys key) (.. "invalid temporal provider key: " (tostring key))))
  (assert (and (= (type provider.id) :string) (> (length provider.id) 0)) "temporal provider id must be a non-empty string")
  (assert (and (= (type provider.version) :string) (> (length provider.version) 0)) "temporal provider version must be a non-empty string")
  (validate-capabilities provider)
  (when (not (= provider.priority nil))
    (assert (= (type provider.priority) :number) "temporal provider priority must be a number"))
  (assert (has-operational-field? provider) "temporal provider requires an operational field"))

(fn capability-present? [provider capability]
  (var present false)
  (each [_ current (ipairs provider.capabilities)]
    (when (= current capability)
      (set present true)))
  present)

(fn provider-priority [provider]
  (if (= provider.priority nil) 100 provider.priority))

(fn provider-summary [provider]
  {:id provider.id
   :version provider.version
   :priority (provider-priority provider)
   :capabilities (copy-array provider.capabilities)})

(fn sort-providers! [providers]
  (table.sort providers
    (fn [a b]
      (if (not (= (provider-priority a) (provider-priority b)))
          (< (provider-priority a) (provider-priority b))
          (< a.id b.id)))))

(fn create-registry []
  (local state {:providers [] :by-id {} :handles {}})

  (fn ordered-providers []
    (local providers [])
    (each [_ provider (ipairs state.providers)]
      (table.insert providers provider))
    (sort-providers! providers)
    providers)

  (fn register [provider]
    (validate-provider provider)
    (assert (= (. state.by-id provider.id) nil) (.. "duplicate temporal provider id: " provider.id))
    (local stored {:id provider.id
                   :version provider.version
                   :priority (provider-priority provider)
                   :capabilities (copy-array provider.capabilities)
                   :parse provider.parse
                   :format provider.format
                   :calendar provider.calendar
                   :business-calendar provider.business-calendar})
    (table.insert state.providers stored)
    (tset state.by-id stored.id stored)
    (local handle {})
    (tset state.handles handle {:id stored.id :active? true})
    handle)

  (fn unregister [handle]
    (local metadata (and (= (type handle) :table) (. state.handles handle)))
    (assert metadata "invalid temporal provider handle")
    (if (not metadata.active?)
        false
        (do
          (set metadata.active? false)
          (tset state.by-id metadata.id nil)
          (local kept [])
          (each [_ provider (ipairs state.providers)]
            (when (not (= provider.id metadata.id))
              (table.insert kept provider)))
          (set state.providers kept)
          true)))

  (fn list [capability]
    (assert (= (type capability) :string) "temporal provider capability must be a keyword")
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (when (capability-present? provider capability)
        (table.insert out (provider-summary provider))))
    out)

  (fn all []
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (table.insert out (provider-summary provider)))
    out)

  (fn append-candidates [out provider candidates]
    (when (not (= candidates nil))
      (assert (= (type candidates) :table) "temporal provider parse result must be an array")
      (each [_ candidate (ipairs candidates)]
        (assert (= (type candidate) :table) "temporal provider candidate must be a table")
        (local copied {})
        (each [key value (pairs candidate)]
          (tset copied key value))
        (when (= copied.provider-id nil)
          (tset copied :provider-id provider.id))
        (table.insert out copied))))

  (fn parse [text context]
    (assert (= (type text) :string) "temporal provider parse text must be a string")
    (local ctx (if (= context nil) {} context))
    (assert (= (type ctx) :table) "temporal provider parse context must be a table")
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (when (and (= (type provider.parse) :function) (capability-present? provider :natural))
        (local (ok result) (pcall provider.parse text ctx))
        (if ok
            (append-candidates out provider result)
            (error (.. "temporal provider " provider.id " parse failed: " (tostring result))))))
    out)

  {:register register
   :unregister unregister
   :list list
   :all all
   :parse parse})

(fn create [_deps]
  (local registry (create-registry))
  {:register registry.register
   :unregister registry.unregister
   :list registry.list
   :all registry.all
   :parse registry.parse})

create
