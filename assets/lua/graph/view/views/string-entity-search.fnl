(local Input (require :input))
(local Button (require :button))
(local Text (require :text))
(local ListView (require :list-view))
(local {: Flex : FlexChild} (require :flex))
(local Utils (require :graph/view/utils))

(fn table-or-empty [value]
  (if value value []))

(fn display-entity-text [result]
  (if (and result.entity result.entity.value)
      result.entity.value
      result.entity-id
      result.entity-id
      "result"))

(fn result-label [result]
  (local entity-text (display-entity-text result))
  (local matched-line (string.match entity-text "([^\r\n]+)"))
  (local first-line (if matched-line matched-line entity-text))
  (local count (if result.match-count result.match-count 0))
  (string.format "%s (%d)" (Utils.truncate-with-ellipsis first-line 80) count))

(fn result-items [results]
  (icollect [_ result (ipairs (table-or-empty results))]
    [result (result-label result)]))

(fn child-widget [widget]
  (fn [_ctx] widget))

(fn make-input [target build-ctx]
  (local query (if target.query target.query ""))
  ((Input {:text query
           :placeholder "Search string entity text"})
   build-ctx))

(fn make-search-button [target input build-ctx]
  (fn search-clicked [_button _event]
    (target:search-text (input:get-text)))
  ((Button {:text "Search"
            :icon "search"
            :variant :ghost
            :on-click search-clicked})
   build-ctx))

(fn make-status-text [target build-ctx]
  (local status (if target.status target.status "Ready"))
  ((Text {:text status}) build-ctx))

(fn make-result-row [target item child-ctx]
  (local result (. item 1))
  (local label (tostring (. item 2)))
  (fn result-clicked [_button _event]
    (target:open-result result))
  ((Button {:text label
            :variant :ghost
            :on-click result-clicked})
   child-ctx))

(fn make-results-list [target build-ctx]
  (fn build-result-row [item child-ctx]
    (make-result-row target item child-ctx))
  ((ListView {:items (result-items target.results)
              :name "string-entity-text-search-results"
              :show-head false
              :paginate false
              :fill-width true
              :scroll true
              :builder build-result-row})
   build-ctx))

(fn make-query-row [input search-button build-ctx]
  ((Flex {:axis 1
          :xspacing 0.3
          :xalign :stretch
          :children [(FlexChild (child-widget input) 1)
                     (FlexChild (child-widget search-button) 0)]})
   build-ctx))

(fn make-root [query-row status-text results-list build-ctx]
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.3
          :children [(FlexChild (child-widget query-row) 0)
                     (FlexChild (child-widget status-text) 0)
                     (FlexChild (child-widget results-list) 1)]})
   build-ctx))

(fn resolve-target [node options]
  (if node
      node
      options.node
      options.node
      (error "StringEntitySearchNodeView requires target node")))

(fn resolve-build-ctx [ctx options target]
  (if ctx
      ctx
      options.ctx
      options.ctx
      (and target.graph target.graph.ctx)
      target.graph.ctx
      (error "StringEntitySearchNodeView requires a build context")))

(fn connect-result-updates [target results-list]
  (fn results-handler [results]
    (results-list:set-items (result-items results)))
  (target.results-changed:connect results-handler)
  results-handler)

(fn connect-status-updates [target status-text]
  (fn status-handler [status]
    (status-text:set-text status))
  (target.status-changed:connect status-handler)
  status-handler)

(fn StringEntitySearchNodeView [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (local build-ctx (resolve-build-ctx ctx options target))
    (local view {})
    (local input (make-input target build-ctx))
    (local search-button (make-search-button target input build-ctx))
    (local status-text (make-status-text target build-ctx))
    (local results-list (make-results-list target build-ctx))
    (local query-row (make-query-row input search-button build-ctx))
    (local root (make-root query-row status-text results-list build-ctx))
    (local results-handler (connect-result-updates target results-list))
    (local status-handler (connect-status-updates target status-text))
    (set view.input input)
    (set view.search-button search-button)
    (set view.status-text status-text)
    (set view.results-list results-list)
    (set view.layout root.layout)
    (set view.drop
         (fn [_self]
           (target.results-changed:disconnect results-handler true)
           (target.status-changed:disconnect status-handler true)
           (root:drop)))
    view))

StringEntitySearchNodeView
