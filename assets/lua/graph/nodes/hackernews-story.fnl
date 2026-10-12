(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local HackerNewsStoryView (require :graph/view/views/hackernews-story))
(local HackerNewsUserNode (require :graph/nodes/hackernews-user))
(local {:ensure-client ensure-client} (require :graph/nodes/hackernews-common))
(local Signal (require :signal))

(fn human-time [timestamp]
    (if timestamp
        (os.date "%c" timestamp)
        "unknown time"))

(fn trim-author [by]
    (if by
        (let [trimmed (string.match (tostring by) "^%s*(.-)%s*$")]
            (if (> (# trimmed) 0) trimmed nil))
        nil))

(fn HackerNewsStoryNode [opts]
    (local options (or opts {}))
    (local id (or options.id (and options.item options.item.id)))
    (assert id "HackerNewsStoryNode requires an id")
    (local title (and options.item options.item.title))
    (local ensure (or options.ensure-client ensure-client))
    (local node
        (GraphNode
            {:key (.. "hackernews-story:" id)
             :label (or title (.. "story " id))
             :color (glm.vec4 0.9 0.5 0.2 1)
             :sub-color (glm.vec4 0.8 0.4 0.15 1)
             :size 8.0
             :view HackerNewsStoryView}))
    (set node.id id)
    (set node.item options.item)
    (set node.error nil)
    (set node.pending [])
    (set node.ensure-client ensure)
    (set node.rows-changed (Signal))
    (set node.actions-changed (Signal))

    (set node.build-rows
         (fn [self]
             (if self.error
                 [{:type :text :text (.. "Error: " self.error)}]
                 (if (not self.item)
                     [{:type :text :text "Loading story..."}]
                     (let [item self.item
                           rows []]
                         (table.insert rows {:type :text
                                             :text (or item.title "<untitled>")
                                             :style {:weight :bold}})
                         (table.insert rows {:type :text
                                             :text (string.format "By %s at %s"
                                                                  (or item.by "unknown")
                                                                  (human-time item.time))})
                         (local actions (self:make-actions item))
                         (when (and actions (> (length actions) 0))
                             (table.insert rows {:type :actions :actions actions}))
                         (when item.url
                             (table.insert rows {:type :text
                                                 :text (.. "URL: " item.url)}))
                         (table.insert rows {:type :body
                                             :text (or item.text "No text available")})
                         rows)))))

    (set node.add-user-node
         (fn [self username]
             (local author (trim-author username))
             (local graph self.graph)
             (when (and author graph)
                 (local user-node (HackerNewsUserNode {:id author
                                                       :ensure-client self.ensure-client}))
                 (graph:add-edge
                     (GraphEdge {:source self
                                     :target user-node})))))

    (set node.make-actions
         (fn [self item]
             (local author (trim-author (and item item.by)))
             (local enabled? (not (not author)))
             [{:label "by"
               :enabled? enabled?
               :on-click (fn [] (self:add-user-node author))}]))

    (set node.emit-rows
         (fn [self]
             (local rows (self:build-rows))
             (when self.rows-changed
                 (self.rows-changed:emit rows))
             rows))
    (set node.emit-actions
         (fn [self]
             (local actions (self:make-actions self.item))
             (when self.actions-changed
                 (self.actions-changed:emit actions))
             actions))
    (set node.emit-state
         (fn [self]
             (self:emit-rows)
             (self:emit-actions)))

    (set node.set-item
         (fn [self item]
             (set self.item item)
             (set self.error nil)
             (self:emit-state)))

    (set node.set-error
         (fn [self err]
             (set self.error err)
             (self:emit-state)))

    (fn track-future [self future cb]
        (if (and future future.on-complete)
            (do
                (table.insert self.pending future)
                (future.on-complete
                 (fn [ok value err source]
                     (for [i (length self.pending) 1 -1]
                         (when (= (. self.pending i) future)
                             (table.remove self.pending i)))
                     (when cb
                         (cb ok value err source)))))
            (when cb
                (cb false nil "invalid future" :hackernews))))

    (set node.fetch
         (fn [self]
             (local client (ensure))
             (if (and client self.id)
                 (track-future self
                               (client.fetch-item self.id)
                               (fn [ok value err _source]
                                   (if ok
                                       (self:set-item value)
                                       (self:set-error (or err "failed to fetch story")))))
                 (self:set-error "missing story id"))))

    (set node.cancel-pending
         (fn [self]
             (each [_ future (ipairs self.pending)]
                 (when (and future future.cancel)
                     (future:cancel)))
             (set self.pending [])))

    (local mount node.mount)
    (set node.mount
         (fn [self graph]
             (mount self graph)
             (when (not self.item)
                 (self:fetch))
             self))

    (set node.drop
         (fn [self]
             (self:cancel-pending)
             (when self.rows-changed
                 (self.rows-changed:clear))
             (when self.actions-changed
                 (self.actions-changed:clear))))

    (set node.actions
         [{:name "Refresh Story"
           :icon "refresh"
           :fn (fn [_button _event]
                   (node:fetch))}
          {:name "Open Author"
           :icon "person"
           :fn (fn [_button _event]
                   (local author (trim-author (and node.item node.item.by)))
                   (when author
                       (node:add-user-node author)))}])

    node)

HackerNewsStoryNode
