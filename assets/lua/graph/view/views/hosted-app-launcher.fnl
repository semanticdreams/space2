(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn text-color [ctx key fallback]
  (local theme (and ctx ctx.theme))
  (local text-theme (and theme theme.text))
  (if (and text-theme (. text-theme key))
      (. text-theme key)
      fallback))

(fn source-label [source]
  (assert source "HostedAppLauncherView source-label requires source")
  (if source.label
      source.label
      source.module-name
      source.module-name
      source.entry-path
      source.entry-path
      source.path
      source.path
      "hosted app"))

(fn status-message [status]
  (local current (assert status "HostedAppLauncherView requires launcher status"))
  (if current.message
      current.message
      (.. "status " (tostring current.status))))

(fn status-line [status]
  (local current (assert status "HostedAppLauncherView requires launcher status"))
  (.. "Status: " (tostring current.status) " — " (status-message current)))

(fn source-line [status]
  (local current (assert status "HostedAppLauncherView requires launcher status"))
  (if current.source
      (.. "Source: " (source-label current.source))
      "Source: select one filesystem app source"))

(fn launch-line [status]
  (local current (assert status "HostedAppLauncherView requires launcher status"))
  (if current.latest-launch
      (.. "Latest launch: " (status-message current.latest-launch))
      "Latest launch: none"))

(fn ready? [status]
  (= (and status status.status) :ready))

(fn constant-child [element]
  (fn [_child-ctx]
    element))

(fn mark-root-dirty [view]
  (when (and view view.layout)
    (view.layout:mark-measure-dirty)
    (view.layout:mark-layout-dirty)))

(fn update-view-status [view status]
  (local current (assert status "HostedAppLauncherView update requires status"))
  (set view.status-kind current.status)
  (set view.status-message (status-message current))
  (set view.source-message (source-line current))
  (set view.launch-message (launch-line current))
  (view.status-text:set-text (status-line current))
  (view.source-text:set-text view.source-message)
  (view.launch-text:set-text view.launch-message)
  (view.launch-button:set-enabled (ready? current))
  (mark-root-dirty view))

(fn make-launch-click-handler [target view]
  (fn [_button _event]
    (target:open-selected {})
    (update-view-status view (target:current-status))))

(fn make-status-handler [view]
  (fn [status]
    (update-view-status view status)))

(fn build-launcher-view [target build-ctx]
  (assert build-ctx.clickables "HostedAppLauncherView requires ctx.clickables")
  (assert build-ctx.hoverables "HostedAppLauncherView requires ctx.hoverables")
  (assert build-ctx.icons "HostedAppLauncherView launch button requires ctx.icons")
  (assert target.current-status "HostedAppLauncherView requires node:current-status")
  (assert target.refresh-selection "HostedAppLauncherView requires node:refresh-selection")
  (assert target.open-selected "HostedAppLauncherView requires node:open-selected")
  (local title-style
    (TextStyle {:color (text-color build-ctx :foreground (glm.vec4 1 1 1 1))
                :scale 1.2}))
  (local detail-style
    (TextStyle {:color (text-color build-ctx :dim-foreground (glm.vec4 0.7 0.7 0.7 1))}))
  (local view {})
  (local title-text ((Text {:text "Hosted App Launcher" :style title-style}) build-ctx))
  (local status-text ((Text {:text "" :style detail-style}) build-ctx))
  (local source-text ((Text {:text "" :style detail-style}) build-ctx))
  (local launch-text ((Text {:text "" :style detail-style}) build-ctx))

  (local launch-button
    ((Button {:icon "rocket_launch"
              :text "Host selected app"
              :variant :primary
              :enabled? false
              :on-click (make-launch-click-handler target view)})
     build-ctx))

  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.35
            :children [(FlexChild (constant-child title-text) 0)
                       (FlexChild (constant-child status-text) 0)
                       (FlexChild (constant-child source-text) 0)
                       (FlexChild (constant-child launch-text) 0)
                       (FlexChild (constant-child launch-button) 0)]})
     build-ctx))

  (set view.title-text title-text)
  (set view.status-text status-text)
  (set view.source-text source-text)
  (set view.launch-text launch-text)
  (set view.launch-button launch-button)
  (set view.layout flex.layout)
  (set view.refresh-status
       (fn [self]
         (when target.refresh-selection
           (target:refresh-selection))
         (update-view-status self (target:current-status))))

  (local status-signal (assert target.status-changed
                               "HostedAppLauncherView requires node.status-changed"))
  (local status-handler (make-status-handler view))
  (status-signal:connect status-handler)

  (set view.drop
       (fn [_self]
         (status-signal:disconnect status-handler true)
         (flex:drop)))

  (view:refresh-status)
  view)

(fn HostedAppLauncherView [node opts]
  (local options (if opts opts {}))
  (local target (if node node options.node))
  (assert target "HostedAppLauncherView requires a launcher node")

  (fn build [ctx]
    (local build-ctx (assert ctx "HostedAppLauncherView requires a build context"))
    (build-launcher-view target build-ctx)))

HostedAppLauncherView
