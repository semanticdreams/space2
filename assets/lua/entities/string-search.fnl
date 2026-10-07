(fn trim [text]
  (assert (= (type text) :string) "search query must be a string")
  (string.match text "^%s*(.-)%s*$"))

(fn trim-trailing-slash [path]
  (if (and path (> (# path) 1) (= (string.sub path -1) "/"))
      (trim-trailing-slash (string.sub path 1 -2))
      path))

(fn normalize-path-separators [path]
  (when path
    (string.gsub path "\\" "/")))

(fn has-prefix? [text prefix]
  (= (string.sub text 1 (string.len prefix)) prefix))

(fn path-under-dir? [dir path]
  (local normalized-dir (trim-trailing-slash (normalize-path-separators dir)))
  (local normalized-path (normalize-path-separators path))
  (and normalized-dir
       normalized-path
       (has-prefix? normalized-path (.. normalized-dir "/"))))

(fn strip-md-extension [name]
  (string.match name "^(.*)%.md$"))

(fn basename [path]
  (assert (= (type path) :string) "path must be a string")
  (string.match (normalize-path-separators path) "([^/]+)$"))

(fn entity-id-for-path [entities-dir path]
  (when (path-under-dir? entities-dir path)
    (strip-md-extension (basename path))))

(fn add-match! [groups order store entities-dir item]
  (local entity-id (entity-id-for-path entities-dir item.path))
  (when entity-id
    (local entity (store:get-entity entity-id))
    (when entity
      (var group (. groups entity-id))
      (when (not group)
        (set group {:entity-id entity-id
                    :entity entity
                    :matches []
                    :match-count 0})
        (set (. groups entity-id) group)
        (table.insert order entity-id))
      (table.insert group.matches item)
      (set group.match-count (+ group.match-count 1)))))

(fn matches-to-results [store entities-dir matches]
  (assert (= (type matches) :table) "ripgrep result requires :matches table")
  (local groups {})
  (local order [])
  (each [_ item (ipairs matches)]
    (add-match! groups order store entities-dir item))
  (icollect [_ entity-id (ipairs order)]
    (. groups entity-id)))

(fn callback-payload [query store entities-dir result]
  {:ok result.ok
   :query query
   :stderr result.stderr
   :error (and (not result.ok) (or result.error result.stderr))
   :results (matches-to-results store entities-dir result.matches)})

(fn search-nonblank [rg store query callback]
  (local entities-dir store.entities-dir)
  (fn handle-ripgrep-result [result]
    (callback (callback-payload query store entities-dir result)))
  (rg.search-async
    {:query query
     :paths [entities-dir]
     :globs ["*.md"]
     :literal true
     :case :ignore}
    handle-ripgrep-result))

(fn RipgrepStringEntitySearchBackend [opts]
  (local options (or opts {}))
  (local store (assert options.store "RipgrepStringEntitySearchBackend requires :store"))
  (local rg (or options.ripgrep (require :ripgrep)))
  (assert store.entities-dir "RipgrepStringEntitySearchBackend requires store.entities-dir")
  (assert store.get-entity "RipgrepStringEntitySearchBackend requires store:get-entity")
  (assert rg.search-async "RipgrepStringEntitySearchBackend requires ripgrep.search-async")
  (fn search-text [_self query callback]
    (assert (= (type callback) :function) "search-text requires callback")
    (local trimmed (trim query))
    (if (= (# trimmed) 0)
        (do
          (callback {:ok true :query trimmed :results []})
          nil)
        (search-nonblank rg store trimmed callback)))
  {:search-text search-text})

{:RipgrepStringEntitySearchBackend RipgrepStringEntitySearchBackend}
