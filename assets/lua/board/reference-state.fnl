(local R (require :reference-lifecycle/record-utils))

(fn contains? [items key]
  (assert (= (type items) :table) "retiring keys must be an array")
  (accumulate [found false _ item (ipairs items)] (or found (= item key))))

(fn stable-key [key operation]
  (var result key)
  (each [_ rewrite (ipairs operation.reference-plan.rewrites)]
    (when (= rewrite.from-key key) (set result rewrite.to-key)))
  result)

;; Preparation cannot ensure identities or assume reserved identities already
;; exist. Resolve through the read-only reservation overlay, then apply the
;; concrete morph overlay (including existing explicit identity chains).
(fn planned-target [key operation identity-store]
  (var current key)
  (var depth 0)
  (local seen {})
  (local reserved (collect [_ record (ipairs operation.reference-plan.identities)]
                    (.. "identity:" record.id) record.target-key))
  (while (and (= (type current) :string) (= (string.sub current 1 9) "identity:"))
    (assert (not (. seen current)) (.. "board subject identity cycle: " current))
    (tset seen current true)
    (local entity (and (not (. reserved current)) (identity-store:get-entity (string.sub current 10))))
    (local target (or (. reserved current) (and entity entity.target-key)))
    (when (or (not target) (= target "")) (lua "break"))
    (assert (< depth 32) (.. "board subject identity depth exhausted: " current))
    (set current target)
    (set depth (+ depth 1)))
  (if (and (= operation.kind "morph") (= current operation.source-key))
      operation.target-key current))

(fn rewrite-item [item operation identity-store]
  (assert (= (type item.type) :string) "board item requires native type")
  (when (not (and (= operation.kind "delete")
                  (contains? operation.retiring item.subject-key)))
    (local out (R.clone item))
    (when item.subject-key
      (set out.subject-key (stable-key item.subject-key operation))
      (local target (planned-target out.subject-key operation identity-store))
      (local scheme (and (= (type target) :string) (string.match target "^([^:]+):")))
      (when (or (= scheme "string-entity") (= scheme "code-entity"))
        (set out.type scheme)))
    out))

(fn keep-connector? [connector present operation]
  (and (. present connector.source-item-id) (. present connector.target-item-id)
       (not (and (= operation.kind "delete") (= connector.kind "semantic-link")
                 connector.semantic-link-id
                 (contains? operation.retiring (.. "link-entity:" connector.semantic-link-id))))))

(fn rewrite [state operation identity-store]
  (assert identity-store "board rewrite requires canonical identity-store")
  (local out (R.clone state))
  (R.require-array (R.field state :items :table []))
  (R.require-array (R.field state :connectors :table []))
  (local items [])
  (local present {})
  (each [_ item (ipairs (or state.items []))]
    (local candidate (rewrite-item item operation identity-store))
    (when candidate
      (table.insert items candidate)
      (tset present candidate.id true)))
  (set out.items items)
  (set out.connectors (icollect [_ connector (ipairs (or state.connectors []))]
                       (when (keep-connector? connector present operation) (R.clone connector))))
  out)

(fn merge-members [existing current fields]
  (assert (and existing current fields) "board merge requires owning and current members and native fields")
  (R.require-array existing) (R.require-array current)
  (local by-id {})
  (each [_ entry (ipairs existing)] (tset by-id entry.id entry))
  (icollect [_ entry (ipairs current)]
    (do
      (local out (R.clone (or (. by-id entry.id) {})))
      ;; Only the native schema is authoritative. Missing live members stay missing;
      ;; opaque owning fields are retained by ID, not searched for reference strings.
      (each [_ field (ipairs fields)] (tset out field (R.clone (. entry field))))
      out)))

(fn merge-model [existing current]
  (assert current "board merge requires live model")
  (local out (R.clone (or existing {})))
  (set out.items (merge-members (or out.items []) current.items
                  [:id :type :subject-key :position :rotation :size :state]))
  (set out.connectors (merge-members (or out.connectors []) current.connectors
                       [:id :source-item-id :target-item-id :kind :semantic-link-id :state]))
  out)

(fn snapshot-roles [record runtime]
  (local sessions (and record.activity record.activity.sessions))
  {:state (R.clone record.board)
   :activity (R.clone (and sessions sessions.board sessions.board.board-state))
   :model (and runtime runtime.board (merge-model record.board (runtime.board:capture-state)))
   :retained (R.clone (and runtime runtime.board-state))
   :runtime-session (R.clone (and runtime runtime.activity-session-state
                                 runtime.activity-session-state.board runtime.activity-session-state.board.board-state))})

(fn install-model! [board state]
  (local items {}) (local connectors {})
  (each [_ item (ipairs state.items)] (tset items item.id item))
  (each [_ connector (ipairs state.connectors)] (tset connectors connector.id connector))
  (for [index (# board.connectors-in-order) 1 -1]
    (local connector (. board.connectors-in-order index))
    (when (not (. connectors connector.id)) (board:remove-connector connector.id)))
  (for [index (# board.items-in-order) 1 -1]
    (local item (. board.items-in-order index))
    (when (not (. items item.id)) (board:remove-item item.id)))
  (each [_ candidate (ipairs state.items)]
    (local item (. board.items candidate.id))
    (if item (board:update-item-subject item.id candidate.subject-key candidate.type)
        (board:add-item candidate)))
  (each [_ candidate (ipairs state.connectors)]
    (when (not (. board.connectors candidate.id)) (board:add-connector candidate)))
  true)

{:rewrite rewrite :snapshot-roles snapshot-roles :install-model! install-model! :merge-model merge-model}
