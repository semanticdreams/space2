(local Common (require :graph/extensions/builtins/common))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local HackerNewsStoryListNode (require :graph/nodes/hackernews-story-list))
(local HackerNewsStoryNode (require :graph/nodes/hackernews-story))
(local HackerNewsUserNode (require :graph/nodes/hackernews-user))

(local schemes ["hackernews-root" "hackernews-story-list" "hackernews-story" "hackernews-user"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn install-loaders [options graph ctx]
  (local ensure-client options.hackernews-ensure-client)
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-root [] (HackerNewsRootNode {:ensure-client ensure-client}))
  (fn make-story-list [kind key]
    (HackerNewsStoryListNode {:kind kind :key key :ensure-client ensure-client}))
  (fn make-story [id _key]
    (HackerNewsStoryNode {:id id :ensure-client ensure-client}))
  (fn make-user [id _key]
    (HackerNewsUserNode {:id id :ensure-client ensure-client}))
  (add! (graph:register-key-loader "hackernews-root"
      (Common.exact-key-loader "hackernews-root" make-root)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "hackernews-story-list"
      (Common.prefix-loader "hackernews-story-list:" make-story-list)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "hackernews-story"
      (Common.prefix-loader "hackernews-story:" make-story)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "hackernews-user"
      (Common.prefix-loader "hackernews-user:" make-user)
      (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-hackernews"
      :unit-id "builtin-graph-hackernews"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
