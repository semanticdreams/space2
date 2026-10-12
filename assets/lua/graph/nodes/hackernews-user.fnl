(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:ensure-client ensure-client} (require :graph/nodes/hackernews-common))
(local HackerNewsUserView (require :graph/view/views/hackernews-user))
(local Signal (require :signal))

(fn human-time [timestamp]
    (if timestamp
        (os.date "%c" timestamp)
        "unknown time"))

(fn HackerNewsUserNode [opts]
    (local options (or opts {}))
    (local id options.id)
    (assert id "HackerNewsUserNode requires an id")
    (local label (or options.label (.. "user " id)))
    (local ensure (or options.ensure-client ensure-client))
    (local node
        (GraphNode
            {:key (.. "hackernews-user:" id)
             :label label
             :color (glm.vec4 0.2 0.6 0.95 1)
             :sub-color (glm.vec4 0.15 0.5 0.85 1)
             :size 8.0
             :view HackerNewsUserView}))
    (set node.id id)
    (set node.user options.user)
    (set node.error nil)
    (set node.pending [])
    (set node.ensure-client ensure)
    (set node.rows-changed (Signal))

    (set node.build-rows
         (fn [self]
             (if self.error
                 [{:type :text :text (.. "Error: " self.error)}]
                 (if (not self.user)
                     [{:type :text :text "Loading user..."}]
                     (let [user self.user
                           rows []]
                         (table.insert rows {:type :text
                                             :text (.. "User " (or user.id "<unknown>"))
                                             :style {:weight :bold}})
                         (table.insert rows {:type :text
                                             :text (.. "Created: " (human-time user.created))})
                         (table.insert rows {:type :text
                                             :text (.. "Karma: " (or user.karma "unknown"))})
                         (table.insert rows {:type :body
                                             :text (or user.about "No about text provided")})
                         rows)))))

    (set node.emit-rows
         (fn [self]
             (local rows (self:build-rows))
             (when self.rows-changed
                 (self.rows-changed:emit rows))
             rows))

    (set node.set-user
         (fn [self user]
             (set self.user user)
             (set self.error nil)
             (self:emit-rows)))

    (set node.set-error
         (fn [self err]
             (set self.error err)
             (self:emit-rows)))

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
                               (client.fetch-user self.id)
                               (fn [ok value err _source]
                                   (if ok
                                       (self:set-user value)
                                       (self:set-error (or err "failed to fetch user")))))
                 (self:set-error "missing user id"))))

    (set node.cancel-pending
         (fn [self]
             (each [_ future (ipairs self.pending)]
                 (when (and future future.cancel)
                     (future:cancel)))
             (set self.pending [])))

    (set node.actions
         [{:name "Refresh User"
           :icon "refresh"
           :fn (fn [_button _event]
                   (node:fetch))}])

    (local mount node.mount)
    (set node.mount
         (fn [self graph]
             (mount self graph)
             (when (not self.user)
                 (self:fetch))
             self))

    (set node.drop
         (fn [self]
             (self:cancel-pending)
             (when self.rows-changed
                 (self.rows-changed:clear))))

    node)

HackerNewsUserNode
