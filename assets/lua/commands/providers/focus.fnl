(local M {})

(fn focus-manager [ctx]
  (and ctx ctx.focus-manager (ctx.focus-manager)))

(fn active-input [ctx]
  (and ctx ctx.active-input (ctx.active-input)))

(fn presentation-camera []
  (and app app.presentation-camera (app.presentation-camera)))

(fn focus-manager-available? [ctx method-name]
  (local manager (focus-manager ctx))
  (if (and manager (. manager method-name)) true false))

(fn can-focus-into? [ctx]
  (local manager (focus-manager ctx))
  (if (and manager manager.can-focus-into?)
      (not (not (manager:can-focus-into?)))
      false))

(fn can-focus-out? [ctx]
  (local manager (focus-manager ctx))
  (if (and manager manager.can-focus-out?)
      (not (not (manager:can-focus-out?)))
      false))

(fn can-focus-next? [ctx]
  (focus-manager-available? ctx :focus-next))

(fn can-focus-direction? [ctx]
  (if (active-input ctx)
      false
      (focus-manager-available? ctx :focus-direction)))

(fn run-focus-into [ctx]
  (local manager (focus-manager ctx))
  (if (and manager manager.focus-into)
      (not (not (manager:focus-into {})))
      false))

(fn run-focus-out [ctx]
  (local manager (focus-manager ctx))
  (if (and manager manager.focus-out)
      (not (not (manager:focus-out {})))
      false))

(fn run-focus-next [ctx opts]
  (local manager (focus-manager ctx))
  (if (and manager manager.focus-next)
      (not (not (manager:focus-next opts)))
      false))

(fn run-focus-direction [ctx direction]
  (local manager (focus-manager ctx))
  (if (and manager manager.focus-direction (not (active-input ctx)))
      (not (not (manager:focus-direction {:direction direction
                                           :camera (presentation-camera)})))
      false))

(fn make-direction-command [id label direction]
  {:id id
   :label label
   :available? can-focus-direction?
   :run (fn [ctx] (run-focus-direction ctx direction))})

(fn M.provider [_opts]
  {:commands {"focus.into" {:id "focus.into"
                             :label "into"
                             :available? can-focus-into?
                             :run run-focus-into}
              "focus.out" {:id "focus.out"
                            :label "out"
                            :available? can-focus-out?
                            :run run-focus-out}
              "focus.next" {:id "focus.next"
                             :label "next"
                             :available? can-focus-next?
                             :run (fn [ctx] (run-focus-next ctx {}))}
              "focus.previous" {:id "focus.previous"
                                 :label "prev"
                                 :available? can-focus-next?
                                 :run (fn [ctx] (run-focus-next ctx {:backwards? true}))}
              "focus.left" (make-direction-command "focus.left" "left" :left)
              "focus.down" (make-direction-command "focus.down" "down" :down)
              "focus.up" (make-direction-command "focus.up" "up" :up)
              "focus.right" (make-direction-command "focus.right" "right" :right)}
   :prefixes [{:keys ["f"] :label "focus" :priority 50}]
   :bindings [{:keys ["f" "i"] :command "focus.into" :label "into" :priority 10}
              {:keys ["f" "o"] :command "focus.out" :label "out" :priority 20}
              {:keys ["f" "n"] :command "focus.next" :label "next" :priority 30}
              {:keys ["f" "p"] :command "focus.previous" :label "prev" :priority 40}
              {:keys ["f" "h"] :command "focus.left" :label "left" :priority 50}
              {:keys ["f" "j"] :command "focus.down" :label "down" :priority 60}
              {:keys ["f" "k"] :command "focus.up" :label "up" :priority 70}
              {:keys ["f" "l"] :command "focus.right" :label "right" :priority 80}]})

{:provider M.provider}
