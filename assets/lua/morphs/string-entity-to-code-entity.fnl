(fn run-morph [ctx]
  (local source (assert ctx.source-node "string->code morph requires source-node"))
  (local mounted (and source.graph source.graph.reference-lifecycle))
  (local explicit (and ctx.options ctx.options.lifecycle))
  (local service (source:resolve-reference-lifecycle!))
  (assert (or (not explicit) (= explicit service)) "string->code reference lifecycle conflict")
  (assert (or (not mounted) (= mounted service)) "string->code reference lifecycle graph conflict")
  (service:replace! source.key
    (fn []
      (local entity (assert (service.stores.string-store:get-entity source.entity-id)
                            "string->code morph missing source entity"))
      {:name "" :language "fnl" :source entity.value :kernel 0})))

(fn register [morphs]
  (assert morphs "register string->code morph requires morphs registry")
  (morphs:register "string-entity" "code-entity" run-morph {:label "code-entity"}))

register
