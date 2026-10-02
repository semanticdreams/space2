(global app (or app {}))

(local glm (require :glm))
(local Hud (require :hud))
(local {: Layout} (require :layout))
(local HudLayout (require :hud-layout))
(local PanelUtils (require :target-panel-utils))

(local tests [])

(fn approx [a b eps]
  (<= (math.abs (- a b)) (or eps 1e-6)))

(fn adaptive-hud-keeps-reference-scale-at-1080p []
  (local hud (Hud {}))
  (hud:update-projection {:width 1920 :height 1080})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "1920x1080 should keep the baseline HUD scale factor")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "1920x1080 should keep the baseline HUD world-units-per-pixel")
  (hud:drop))

(fn adaptive-hud-grows-at-1200p []
  (local hud (Hud {}))
  (hud:update-projection {:width 1920 :height 1200})
  (assert (approx hud.effective-scale-factor 1.5)
          "1920x1200 should reduce effective scale factor so HUD renders larger")
  (assert (approx hud.world-units-per-pixel 0.075)
          "1920x1200 should reduce world-units-per-pixel so HUD renders larger")
  (hud:drop))

(fn adaptive-hud-keeps-baseline-at-smaller-heights []
  (local hud (Hud {}))
  (hud:update-projection {:width 1600 :height 900})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "viewports shorter than 1080p should keep baseline readability")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "viewports shorter than 1080p should keep baseline world-units-per-pixel")
  (hud:drop))

(fn adaptive-hud-ignores-placeholder-viewport []
  (local hud (Hud {}))
  (hud:update-projection {:width 1 :height 1})
  (assert (approx hud.effective-scale-factor (/ 5 3))
          "placeholder viewport should keep the requested scale factor")
  (assert (approx hud.world-units-per-pixel (/ 1 12))
          "placeholder viewport should keep baseline world-units-per-pixel")
  (hud:drop))

(fn vec-approx [left right eps]
  (and (approx left.x right.x eps)
       (approx left.y right.y eps)
       (approx left.z right.z eps)))

(fn array->vec3 [items]
  (glm.vec3 (. items 1)
            (. items 2)
            (. items 3)))

(fn fixed-widget [name measure]
  (fn [_ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure measure))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))}))

(fn build-test-hud [width height]
  (local hud (Hud {}))
  (hud:build
    (HudLayout.make-hud-builder
      {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
       :status-builder (fixed-widget "status" (glm.vec3 8 2 0))}))
  (hud:update-projection {:width width :height height})
  (hud:update)
  hud)

(fn hud-float-persistence-stays-resolution-independent []
  (local kind "hud-test-panel")
  (local dialog-builder (fixed-widget "dialog" (glm.vec3 4 3 0)))
  (local original-hud (build-test-hud 1920 1080))
  (original-hud:register-panel-restorer
    kind
    (fn [panel]
      (local placement (PanelUtils.panel-placement-options original-hud panel))
      (original-hud:add-panel-child {:builder dialog-builder
                                     :location placement.location
                                     :position placement.position
                                     :rotation placement.rotation
                                     :size placement.size
                                     :align-x placement.align-x
                                     :align-y placement.align-y
                                     :persistence {:kind kind}})))
  (original-hud:add-panel-child {:builder dialog-builder
                                 :location :float
                                 :position (glm.vec3 3 4 0)
                                 :rotation (glm.quat 1 0 0 0)
                                 :size (glm.vec3 10 6 0)
                                 :persistence {:kind kind}})
  (original-hud:update)
  (local captured (original-hud:capture-state))
  (local original-panel (. captured.panels 1))
  (assert (= (type original-panel.relative-position) :table)
          "HUD float persistence should store relative position")
  (assert (= (type original-panel.relative-size) :table)
          "HUD float persistence should store relative size")
  (original-hud:drop)

  (local restored-hud (build-test-hud 1920 1200))
  (restored-hud:register-panel-restorer
    kind
    (fn [panel]
      (local placement (PanelUtils.panel-placement-options restored-hud panel))
      (restored-hud:add-panel-child {:builder dialog-builder
                                     :location placement.location
                                     :position placement.position
                                     :rotation placement.rotation
                                     :size placement.size
                                     :align-x placement.align-x
                                     :align-y placement.align-y
                                     :persistence {:kind kind}})))
  (restored-hud:restore-state captured)
  (restored-hud:update)
  (local restored (restored-hud:capture-state))
  (local restored-panel (. restored.panels 1))
  (assert (vec-approx (array->vec3 restored-panel.relative-position)
                      (array->vec3 original-panel.relative-position)
                      1e-6)
          "HUD float persistence should preserve relative position across resolutions")
  (assert (vec-approx (array->vec3 restored-panel.relative-size)
                      (array->vec3 original-panel.relative-size)
                      1e-6)
          "HUD float persistence should preserve relative size across resolutions")
  (restored-hud:drop))

(fn hud-screen-pos-ray-converts-logical-input-to-viewport-space []
  (local original-engine app.engine)
  (local original-viewport app.viewport)
  (var hud nil)
  (set app.engine {:width 100 :height 50})
  (set app.viewport {:x 0 :y 0 :width 200 :height 100})
  (set hud (Hud {}))
  (hud:update-projection app.viewport)
  (local logical-ray (hud:screen-pos-ray {:x 50 :y 25}))
  (assert (approx logical-ray.origin.x 0 1e-6)
          "HUD logical input conversion should keep the viewport center on the HUD origin")
  (assert (approx logical-ray.origin.y 0 1e-6)
          "HUD logical input conversion should keep the viewport center on the HUD origin")
  (assert (approx logical-ray.direction.x 0 1e-6)
          "HUD logical input conversion should keep the center ray aligned on the Z axis")
  (assert (approx logical-ray.direction.y 0 1e-6)
          "HUD logical input conversion should keep the center ray aligned on the Z axis")
  (hud:drop)
  (set app.viewport original-viewport)
  (set app.engine original-engine))

(fn hud-overlay-layers-are-explicit []
  (local hud (build-test-hud 1920 1080))
  (local full-overlay
    (hud:add-overlay-child {:builder (fixed-widget "full-overlay" (glm.vec3 2 1 0))}))
  (local middle-overlay
    (hud:add-overlay-child {:builder (fixed-widget "middle-overlay" (glm.vec3 2 1 0))
                            :layer :middle}))
  (hud:update)
  (assert (= (length hud.overlay-root.children) 1)
          "default overlay children should attach to the full HUD overlay")
  (assert (= (length hud.middle-overlay-root.children) 1)
          "middle overlay children should require an explicit layer")
  (assert (= (. (. hud.overlay-root.children 1) :element) full-overlay)
          "full overlay root should own the default overlay element")
  (assert (= (. (. hud.middle-overlay-root.children 1) :element) middle-overlay)
          "middle overlay root should own the explicitly layered overlay element")
  (hud:drop))

(fn hud-overlay-layer-fails-loudly []
  (local hud (build-test-hud 1920 1080))
  (local (ok err)
    (pcall (fn []
             (hud:add-overlay-child {:builder (fixed-widget "bad-overlay" (glm.vec3 2 1 0))
                                     :layer :side}))))
  (assert (not ok)
          "unsupported overlay layers should fail")
  (assert (and err (string.find (tostring err) "Unsupported HUD overlay layer" 1 true))
          "unsupported overlay layers should report the bad layer")
  (hud:drop))

(fn hud-overlay-requires-builder []
  (local hud (build-test-hud 1920 1080))
  (local (ok err)
    (pcall (fn []
             (hud:add-overlay-child {:layer :middle}))))
  (assert (not ok)
          "overlay children should require a builder")
  (assert (and err (string.find (tostring err) "Hud.add-overlay-child requires :builder" 1 true))
          "missing overlay builders should fail loudly")
  (hud:drop))

(fn hud-default-snackbar-scope-and-lifecycle []
  (local hud (Hud {}))
  (assert hud.snackbar-manager
          "Hud should create a default snackbar manager")
  (local original-manager hud.snackbar-manager)
  (hud:build-default {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
                      :status-builder (fixed-widget "status" (glm.vec3 8 2 0))})
  (assert hud.entity.snackbar-host-root
          "Hud.build-default should mount the default snackbar host root")
  (local handle (hud:show-snackbar {:text "Saved" :persistent? true}))
  (assert handle
          "Hud.show-snackbar should return a handle")
  (assert (= (length (hud.snackbar-manager:visible-entries)) 1)
          "Hud.show-snackbar should add a visible manager entry")
  (assert (hud:dismiss-snackbar handle)
          "Hud.dismiss-snackbar should dismiss by handle")
  (assert (= (length (hud.snackbar-manager:visible-entries)) 0)
          "Hud.dismiss-snackbar should remove the visible entry")
  (local preserved-handle (hud:show-snackbar {:text "Still here" :persistent? true}))
  (hud:build-default {:control-builder (fixed-widget "control" (glm.vec3 8 3 0))
                      :status-builder (fixed-widget "status" (glm.vec3 8 2 0))})
  (assert (= hud.snackbar-manager original-manager)
          "Hud rebuilds should preserve the snackbar manager object")
  (assert (= (length (hud.snackbar-manager:visible-entries)) 1)
          "Hud rebuilds should preserve existing visible snackbar entries")
  (local visible-after-rebuild (hud.snackbar-manager:visible-entries))
  (assert (= (. (. visible-after-rebuild 1) :id) preserved-handle.id)
          "Hud rebuilds should keep the existing snackbar entry")
  (local original-scope hud.snackbar-scope)
  (var drop-count 0)
  (local original-drop original-scope.drop)
  (set original-scope.drop
       (fn [self]
         (set drop-count (+ drop-count 1))
         (original-drop self)))
  (hud:drop)
  (hud:drop)
  (assert (= drop-count 1)
          "Hud.drop should drop the snackbar scope exactly once")
  (local (ok err)
    (pcall (fn []
             (original-manager:show {:text "After drop"}))))
  (assert (not ok)
          "Snackbar manager should reject show after Hud.drop")
  (assert (and err (string.find (tostring err) "SnackbarManager is dropped" 1 true))
          "Dropped snackbar manager should report its dropped state"))

(fn hud-default-snackbar-manager-uses-active-theme-policy []
  (local original-engine app.engine)
  (local original-themes app.themes)
  (set app.engine (or app.engine {}))
  (set app.themes {:get-active-theme (fn []
                                       {:snackbar {:max-visible 1
                                                   :duration-ms 123456}})})
  (local hud (Hud {}))
  (local first (hud:show-snackbar {:text "First" :persistent? true}))
  (local second (hud:show-snackbar {:text "Second" :persistent? true}))
  (local timed (hud:show-snackbar {:text "Timed"}))
  (local visible (hud.snackbar-manager:visible-entries))
  (local queued (hud.snackbar-manager:queued-entries))
  (assert (= (length visible) 1)
          "Active snackbar theme max-visible should limit HUD manager visibility")
  (assert (= (. (. visible 1) :id) first.id)
          "The first HUD snackbar should remain visible under max-visible 1")
  (assert (= (length queued) 2)
          "Additional HUD snackbars should queue under active snackbar max-visible policy")
  (assert (= (. (. queued 1) :id) second.id)
          "The second HUD snackbar should be queued by max-visible 1")
  (assert (= (. (. queued 2) :id) timed.id)
          "The timed HUD snackbar should be queued behind the second entry")
  (assert (= (. (. queued 2) :duration-ms) 123456)
          "Active snackbar theme duration-ms should become the HUD manager default duration")
  (hud:drop)
  (set app.themes original-themes)
  (set app.engine original-engine))

(table.insert tests {:name "Hud adaptive scaling keeps reference scale at 1080p"
                     :fn adaptive-hud-keeps-reference-scale-at-1080p})
(table.insert tests {:name "Hud adaptive scaling grows at 1200p"
                     :fn adaptive-hud-grows-at-1200p})
(table.insert tests {:name "Hud adaptive scaling keeps baseline at smaller heights"
                     :fn adaptive-hud-keeps-baseline-at-smaller-heights})
(table.insert tests {:name "Hud adaptive scaling ignores placeholder viewport"
                     :fn adaptive-hud-ignores-placeholder-viewport})
(table.insert tests {:name "Hud float persistence stays resolution independent"
                     :fn hud-float-persistence-stays-resolution-independent})
(table.insert tests {:name "Hud screen-pos-ray converts logical input to viewport space"
                     :fn hud-screen-pos-ray-converts-logical-input-to-viewport-space})
(table.insert tests {:name "Hud overlay layers are explicit"
                     :fn hud-overlay-layers-are-explicit})
(table.insert tests {:name "Hud overlay layer fails loudly"
                     :fn hud-overlay-layer-fails-loudly})
(table.insert tests {:name "Hud overlay requires builder"
                     :fn hud-overlay-requires-builder})
(table.insert tests {:name "Hud default snackbar scope and lifecycle"
                      :fn hud-default-snackbar-scope-and-lifecycle})
(table.insert tests {:name "Hud default snackbar manager uses active theme policy"
                     :fn hud-default-snackbar-manager-uses-active-theme-policy})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud"
                       :tests tests})))

{:name "hud"
 :tests tests
 :main main}
