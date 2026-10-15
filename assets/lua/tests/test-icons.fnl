(local fennel (require :fennel))
(local original-require require)

;; Snapshot _G.app existence before the global form creates/uses it.
;; If _G.app was nil, restore it to nil after setup so the module
;; does not permanently create a global that didn't exist before.
(local app-existed-before (not (= nil _G.app)))

;; Setup may temporarily need app; preserve its original absence below.
(global app (or _G.app {}))

;; Wrapper that snapshots/restores dotted global paths.
;; Keys not starting with 'package.' or 'app.' are prefixed with 'app.'.
;; Nil-safe: if any segment of the path does not exist in _G, snapshot is nil
;; and restore is a no-op.
;; Recognized by the test-isolation constraint rule as a safe mutation wrapper.
(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    ;; Resolve dotted key path from global scope to snapshot
    (local full-key (if (or (key:find "^package%.") (key:find "^app%."))
                       key
                       (.. "app." key)))
    (local parts [])
    (each [seg (full-key:gmatch "[^%.]+")] (table.insert parts seg))
    (var src _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set src (. src (. parts i)))
      (when (= nil src)
        (set all-exist false)
        (lua :break)))
    (set (. snapshot key) (if all-exist
                              (. src (. parts (length parts)))
                              nil)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    ;; Restore dotted key path from snapshot
    (local full-key (if (or (key:find "^package%.") (key:find "^app%."))
                       key
                       (.. "app." key)))
    (local parts [])
    (each [seg (full-key:gmatch "[^%.]+")] (table.insert parts seg))
    (var dst _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set dst (. dst (. parts i)))
      (when (= nil dst)
        (set all-exist false)
        (lua :break)))
    (when all-exist
      (tset dst (. parts (length parts)) (. snapshot key))))
  (if ok
      result
      (error result)))

(fn setup-icons []
  ;; Wrapper snapshots/restores package.loaded.textures AND app.engine.
  ;; :package.loaded.textures — restore leaf texture module value
  ;; :engine — restore app.engine container (includes get-asset-path)
  ;; If a require throws, the wrapper's pcall restores both keys immediately.
  (with-restored-app-fields [:package.loaded.textures :engine]
    (fn []
      ;; Create a FRESH engine table — never mutate a pre-existing one.
      ;; The wrapper replaces the engine container entirely, so the old
      ;; engine reference (or nil) is saved and properly restored on exit.
      (tset _G.app :engine
            {:get-asset-path
             (fn [path] (.. (os.getenv "SPACE_ASSETS_PATH") "/" path))})

      ;; Mock textures while loading icon widgets
      (tset package.loaded :textures
            {:load-texture (fn [_name _path] {:width 512 :height 512 :id 1})
             :load-texture-async (fn [_name _path] {:width 512 :height 512 :id 1})})
      (local icons (require :icons))
      (local icon (require :icon-widget))
      (local button (require :button))

      ;; Return loaded modules as a sequential table
      [icons icon button])))

(local (ok modules) (pcall setup-icons))
;; Wrap setup-icons in pcall so _G.app cleanup always runs,
;; even when setup throws during module loading.
;; The wrapper inside setup-icons already restores package.loaded.textures
;; and app.engine on error; this outer pcall ensures _G.app itself is
;; also cleaned up.
(when (not app-existed-before)
  (tset _G :app nil))
(if (not ok)
    (error modules))

(local Icons (. modules 1))
(local Icon (. modules 2))
(local Button (. modules 3))

(fn test-icons-resolve []
  (local icons (Icons {:theme "Adwaita"}))
  
  ;; Test Material Icon (legacy)
  (local material-res (icons:resolve "arrow_drop_down"))
  (assert (= material-res.type :font) "Material icon should identify as font")
  (assert material-res.codepoint "Material icon should have a codepoint")

  ;; Test Image Path
  (local image-res (icons:resolve "/tmp/some-icon.png"))
  (assert (= image-res.type :image) "Absolute path should identify as image")
  (assert (= image-res.path "/tmp/some-icon.png") "Path should be preserved"))

(fn test-icon-widget-render []
  ;; Mock Context with Icons service
  (local icons (Icons))
  
  (local mock-vector
    {:allocate (fn [])
     :delete (fn [])
     :set-float (fn [])
     :set-glm-vec3 (fn [])
     :set-glm-vec2 (fn [])
     :set-glm-vec4 (fn [])})

  (local ctx {:icons icons
              :get-text-vector (fn [] mock-vector)
              :get-text-ssbo-batcher (fn []
                                       {:upsert-text (fn [_batcher _key _opts] nil)
                                        :update-text-transform (fn [_batcher _key _opts] nil)
                                        :remove-text (fn [_batcher _key] nil)})
              :track-text-handle (fn [])
              :untrack-text-handle (fn [])})
  
  ;; Render Material Icon
  (local icon-builder (Icon {:icon "home"}))
  (local widget (icon-builder ctx))
  (assert widget "Icon widget should build")
  (assert widget.layout "Icon widget should have layout")
  ;; We know it's a Text widget underneath for material icons, checking children
  ;; would rely on implementation details but we can verify it doesn't crash.
  
  (widget:drop))

(fn check-reimport-preserves-theme []
  (local module-name "tests.test-icons")
  (local previous-app _G.app)
  (local previous-themes (and previous-app previous-app.themes))
  (local previous-cache package.loaded)
  (local previous-module (. previous-cache module-name))
  (local (import-ok result)
    (pcall (fn []
             (tset previous-cache module-name nil)
             (original-require module-name))))
  (local imported-app _G.app)
  (local imported-themes (and imported-app imported-app.themes))
  ;; Restore every observed field/cache entry BEFORE any assertion or rethrow.
  (when previous-app (tset previous-app :themes previous-themes))
  (tset _G :app previous-app)
  (tset previous-cache module-name previous-module)
  (set package.loaded previous-cache)
  (assert import-ok (tostring result))
  (assert (= imported-app previous-app) "icon reimport must preserve app existence/identity")
  (assert (= imported-themes previous-themes) "icon reimport must preserve actual theme provider identity/absence")
  (assert (= (. package.loaded module-name) previous-module) "reimport fixture must restore module cache"))

(fn test-reimport-preserves-theme []
  (check-reimport-preserves-theme)
  (fn without-theme []
    (tset app :themes nil)
    (check-reimport-preserves-theme))
  (with-restored-app-fields [:themes] without-theme))

(local tests [{:name "icons resolves material and image references" :fn test-icons-resolve}
              {:name "icons renders native material font" :fn test-icon-widget-render}
              {:name "icons reimport preserves theme provider and module cache" :fn test-reimport-preserves-theme}])

(fn main []
  ;; Snapshot _G.app existence and engine state before mocking.
  (local app-existed-main (not (= nil _G.app)))
  (local prev-engine (and _G.app _G.app.engine))

  ;; Ensure _G.app exists for test execution.
  (when (not app-existed-main)
    (tset _G :app {}))

  ;; Create a FRESH engine table — never mutate a pre-existing one.
  ;; The restore below replaces the entire container, so the old
  ;; engine (or nil) is preserved without leaking mock mutations.
  (tset _G.app :engine
        {:get-asset-path
         (fn [path] (.. (os.getenv "SPACE_ASSETS_PATH") "/" path))})

  (local (ok err) (pcall (fn []
    (test-icons-resolve)
    (print "test-icons-resolve passed")
    (test-icon-widget-render)
    (print "test-icon-widget-render passed")
    (print "All icon tests passed."))))

  ;; Always restore state, even if tests failed.
  ;; Restore engine to its pre-main value (nil or original table ref).
  (if _G.app
      (tset _G.app :engine prev-engine))
  ;; If _G.app was created solely for this test run, remove it.
  (when (not app-existed-main)
    (tset _G :app nil))

  ;; Re-raise any test error after cleanup
  (if (not ok) (error err)))

{:name "icons" :tests tests :main main}
