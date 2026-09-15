(local fs (require :fs))
(local BuildContext (require :build-context))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "fs-file-viewer"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "viewer-" (os.time) "-" temp-counter)))

(fn create-temp-dir []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn write-sample-file [dir]
  (local file (fs.join-path dir "sample.txt"))
  (fs.write-file file "abcdefghi")
  (fs.absolute file))

(fn create-sample-file []
  (local dir (create-temp-dir))
  (values dir (write-sample-file dir)))

(fn vector-allocate [_self _count] 1)
(fn vector-delete [_self _handle] nil)
(fn vector-set-glm-vec3 [_self _handle _offset _value] nil)
(fn vector-set-glm-vec4 [_self _handle _offset _value] nil)
(fn vector-set-glm-vec2 [_self _handle _offset _value] nil)
(fn vector-set-float [_self _handle _offset _value] nil)

(fn make-vector-buffer []
  {:allocate vector-allocate
   :delete vector-delete
   :set-glm-vec3 vector-set-glm-vec3
   :set-glm-vec4 vector-set-glm-vec4
   :set-glm-vec2 vector-set-glm-vec2
   :set-float vector-set-float})

(fn clickable-register [_self _obj] nil)
(fn clickable-unregister [_self _obj] nil)
(fn clickable-register-right-click [_self _obj] nil)
(fn clickable-unregister-right-click [_self _obj] nil)
(fn clickable-register-double-click [_self _obj] nil)
(fn clickable-unregister-double-click [_self _obj] nil)

(fn make-clickables-stub []
  {:register clickable-register
   :unregister clickable-unregister
   :register-right-click clickable-register-right-click
   :unregister-right-click clickable-unregister-right-click
   :register-double-click clickable-register-double-click
   :unregister-double-click clickable-unregister-double-click})

(fn hoverable-register [_self _obj] nil)
(fn hoverable-unregister [_self _obj] nil)

(fn make-hoverables-stub []
  {:register hoverable-register
   :unregister hoverable-unregister})

(fn ssbo-upsert-text [_batcher _key _opts] nil)
(fn ssbo-update-text-transform [_batcher _key _opts] nil)
(fn ssbo-remove-text [_batcher _key] nil)

(fn quad-upsert [_batcher _key _opts] nil)
(fn quad-remove [_batcher _key] nil)

(fn make-ssbo-batcher []
  {:upsert-text ssbo-upsert-text
   :update-text-transform ssbo-update-text-transform
   :remove-text ssbo-remove-text})

(fn make-quad-batcher []
  {:upsert-quad quad-upsert
   :remove-quad quad-remove})

(fn ctx-get-text-ssbo-batcher [_self]
  (make-ssbo-batcher))

(fn ctx-get-rectangle-quad-batcher [_self]
  (make-quad-batcher))

(fn make-test-font []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1 :lineHeight 1}}
               :glyph-map {}})
  (set font.metadata.atlas {:width 1 :height 1})
  (for [codepoint 1 65533]
    (tset font.glyph-map codepoint glyph))
  font)

(fn make-test-ctx []
  (local text-buffer (make-vector-buffer))
  (local font (make-test-font))
  (local ctx (BuildContext {:clickables (make-clickables-stub)
                            :hoverables (make-hoverables-stub)}))
  (set ctx.triangle-vector (make-vector-buffer))
  (set ctx.theme {:font font
                  :text {:foreground [1 1 1 1] :scale 1}})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher ctx-get-text-ssbo-batcher)
  (set ctx.get-rectangle-quad-batcher ctx-get-rectangle-quad-batcher)
  ctx)

(fn text-widget-string [widget]
  (table.concat
    (icollect [_ codepoint (ipairs (widget:get-codepoints))]
              (utf8.char codepoint))
    ""))

(fn string-contains? [text needle]
  (not (= (string.find text needle 1 true) nil)))

(fn assert-view-handles [view]
  (assert view.virtual-input "view should expose virtual-input")
  (assert view.save-button "view should expose save-button")
  (assert view.edit-button "view should expose edit-button")
  (assert view.status-text "view should expose status-text"))

(fn status-string [view]
  (text-widget-string view.status-text))

(fn first-virtual-row-text [view]
  (local row (. view.virtual-input.rows 1))
  (text-widget-string row))

(fn fs-file-viewer-builds-virtual-input-for-file-contents []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (assert (= view.virtual-input.buffer node.buffer) "VirtualInput should edit the node's lazy buffer")
  (assert (= (first-virtual-row-text view) "abcdefghi") "VirtualInput should render file contents from visible rows")
  (assert (= node.buffer.dirty? false) "newly opened buffer should be clean")
  (view.virtual-input:insert-text "Z")
  (assert node.buffer.dirty? "editing through VirtualInput should dirty the lazy buffer")
  (assert (string-contains? (status-string view) "Unsaved") "status should report dirty edits")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-key-loader-loads-existing-file []
  (local Graph (require :graph/init))
  (local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))
  (local (dir file) (create-sample-file))
  (local key (.. "fs-file-viewer:" file))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {}))
  (local node (graph:load-by-key key))
  (assert node "fs-file-viewer loader should create a node for an existing file")
  (assert (= node.key key) "loaded viewer key should match")
  (assert (= node.path file) "loaded viewer path should match absolute path")
  (node:drop)
  (builtins:drop)
  (graph:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-saves-internal-edits-to-disk []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (view.virtual-input:insert-text "Z")
  (assert node.buffer.dirty? "edit should dirty the buffer before save")
  (view.save-button:on-click {})
  (assert (= (fs.read-file file) "Zabcdefghi") "Save should persist lazy buffer edits to disk")
  (assert (= node.buffer.dirty? false) "successful save should clean the buffer")
  (assert (string-contains? (status-string view) "Saved") "status should report save success")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-reports-external-modification-conflict []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (view.virtual-input:insert-text "Z")
  (fs.write-file file "external")
  (view.save-button:on-click {})
  (assert (= (fs.read-file file) "external") "conflicting save should not overwrite external edits")
  (assert node.buffer.dirty? "conflicting save should leave buffer dirty")
  (assert (string-contains? (status-string view) "Conflict") "status should report external modification conflict")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-ctrl-s-updates-status-after-save []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (view.virtual-input:insert-text "K")
  (assert (string-contains? (status-string view) "Unsaved") "edit should mark status dirty")
  (assert (view.virtual-input:on-key-down {:key (string.byte "s") :mod 64}) "Ctrl+S should be handled")
  (assert (= (fs.read-file file) "Kabcdefghi") "Ctrl+S should persist edits")
  (assert (string-contains? (status-string view) "Saved") "Ctrl+S should report save success")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-ctrl-s-reports-conflict-status []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (view.virtual-input:insert-text "K")
  (fs.write-file file "external")
  (local (ok handled) (pcall view.virtual-input.on-key-down view.virtual-input {:key (string.byte "s") :mod 64}))
  (assert ok "Ctrl+S conflict should be reported in status without throwing")
  (assert (= handled false) "conflicting Ctrl+S should return false")
  (assert (= (fs.read-file file) "external") "conflicting Ctrl+S should not overwrite external edits")
  (assert (string-contains? (status-string view) "Conflict") "Ctrl+S should report conflict status")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-ctrl-s-reports-error-status []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local view ((FsFileViewerNodeView node {}) (make-test-ctx)))
  (assert-view-handles view)
  (view.virtual-input:insert-text "K")
  (set node.buffer.save (fn [_self] (error "simulated save failure")))
  (local (ok handled) (pcall view.virtual-input.on-key-down view.virtual-input {:key (string.byte "s") :mod 64}))
  (assert ok "Ctrl+S save errors should be reported in status without throwing")
  (assert (= handled false) "erroring Ctrl+S should return false")
  (assert (string-contains? (status-string view) "Error") "Ctrl+S should report error status")
  (view:drop)
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-external-editor-explicit-button-remains-available []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local ExternalEditor (require :external-editor))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file}))
  (local original-open-file ExternalEditor.open-file)
  (local opened [])
  (var view nil)
  (set ExternalEditor.open-file
       (fn [path callback]
         (table.insert opened path)
         (callback)
         true))
  (local (ok result)
    (pcall
      (fn []
        (set view ((FsFileViewerNodeView node {}) (make-test-ctx)))
        (assert-view-handles view)
        (view.edit-button:on-click {})
        (assert (= (. opened 1) file) "edit button should open the absolute path")
        (assert (= view.content-button nil) "internal viewer should not claim wrapper double-click affordance"))))
  (set ExternalEditor.open-file original-open-file)
  (when view
    (view:drop))
  (node:drop)
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(table.insert tests {:name "fs-file-viewer builds VirtualInput for file contents"
                     :fn fs-file-viewer-builds-virtual-input-for-file-contents})
(table.insert tests {:name "fs-file-viewer key loader loads existing file"
                     :fn fs-file-viewer-key-loader-loads-existing-file})
(table.insert tests {:name "fs-file-viewer saves internal edits to disk"
                     :fn fs-file-viewer-saves-internal-edits-to-disk})
(table.insert tests {:name "fs-file-viewer reports external modification conflict"
                     :fn fs-file-viewer-reports-external-modification-conflict})
(table.insert tests {:name "fs-file-viewer Ctrl+S updates status after save"
                     :fn fs-file-viewer-ctrl-s-updates-status-after-save})
(table.insert tests {:name "fs-file-viewer Ctrl+S reports conflict status"
                     :fn fs-file-viewer-ctrl-s-reports-conflict-status})
(table.insert tests {:name "fs-file-viewer Ctrl+S reports error status"
                     :fn fs-file-viewer-ctrl-s-reports-error-status})
(table.insert tests {:name "fs-file-viewer external editor explicit button remains available"
                     :fn fs-file-viewer-external-editor-explicit-button-remains-available})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs-file-viewer"
                       :tests tests})))

{:name "fs-file-viewer"
 :tests tests
 :main main}
