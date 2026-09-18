(local AppConfig (require :app-config))
(local SnakeApp (require :snake/app))

(fn main []
  (SnakeApp.run))

(when AppConfig.run-main
  (main))

{:main main}
