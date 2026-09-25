(local AppConfig (require :app-config))
(local StandaloneRuntime (require :standalone-app-runtime))
(local SnakeApp (require :snake/app))

(fn main []
  (StandaloneRuntime.run {:module SnakeApp
                          :engine-options {:width 800 :height 600
                                           :title "Snake"}}))

(when AppConfig.run-main
  (main))

{:metadata SnakeApp.metadata
 :create SnakeApp.create
 :main main}
