(local InputState (require :input-state-router))

(fn current-active-input []
  (and InputState
       InputState.active-input
       (InputState.active-input)))

(fn set-focused [input focused?]
  (set input.focused? (not (not focused?)))
  (when input.update-focus-visual
    (input:update-focus-visual {:mark-layout-dirty? true})))

(fn normalize-blurred [input]
  (when input.enter-normal-mode
    (input:enter-normal-mode))
  (set input.connected? false)
  (set-focused input false))

(fn handle-focus [input]
  (assert input "FocusPolicy.handle-focus requires input")
  (when (not input.focused?)
    (set input.focused? true)
    (when input.enter-normal-mode
      (input:enter-normal-mode))
    (when (and InputState (not input.connected?))
      (InputState.connect-input input)
      (set input.connected? true))
    (when (and InputState (not (= (InputState.current-state-name) :text)))
      (InputState.set-state :text))
    (when input.update-focus-visual
      (input:update-focus-visual {:mark-layout-dirty? true})))
  true)

(fn handle-blur [input]
  (assert input "FocusPolicy.handle-blur requires input")
  (if input.__focus-policy-blurring?
      (do
        (normalize-blurred input)
        true)
      (do
        (set input.__focus-policy-blurring? true)
        (when (and InputState (= (current-active-input) input))
          (InputState.disconnect-input input))
        (normalize-blurred input)
        (set input.__focus-policy-blurring? false)
        true)))

(fn handle-state-disconnected [input]
  (assert input "FocusPolicy.handle-state-disconnected requires input")
  (normalize-blurred input)
  true)

(fn request-focus [input]
  (assert input "FocusPolicy.request-focus requires input")
  (if input.focus-node
      (input.focus-node:request-focus)
      (handle-focus input))
  true)

(fn make-focus-listener [input]
  (fn [event]
    (local node input.focus-node)
    (when (and node event (= event.current node))
      (handle-focus input))))

(fn make-blur-listener [input]
  (fn [event]
    (local node input.focus-node)
    (when (and node event (= event.previous node))
      (handle-blur input))))

(fn connect-focus-listeners [input]
  (assert input "FocusPolicy.connect-focus-listeners requires input")
  (local focus-manager input.focus-manager)
  (when (and focus-manager (not input.__focus-listener))
    (set input.__focus-listener
         (focus-manager.focus-focus.connect (make-focus-listener input))))
  (when (and focus-manager (not input.__blur-listener))
    (set input.__blur-listener
         (focus-manager.focus-blur.connect (make-blur-listener input))))
  (when (and focus-manager input.focus-node (= (focus-manager:get-focused-node) input.focus-node))
    (handle-focus input))
  nil)

(fn disconnect-focus-listeners [input]
  (assert input "FocusPolicy.disconnect-focus-listeners requires input")
  (when input.__focus-listener
    (local manager input.focus-manager)
    (when (and manager manager.focus-focus)
      (manager.focus-focus.disconnect input.__focus-listener true))
    (set input.__focus-listener nil))
  (when input.__blur-listener
    (local manager input.focus-manager)
    (when (and manager manager.focus-blur)
      (manager.focus-blur.disconnect input.__blur-listener true))
    (set input.__blur-listener nil))
  nil)

{:request-focus request-focus
 :handle-focus handle-focus
 :handle-blur handle-blur
 :handle-state-disconnected handle-state-disconnected
 :connect-focus-listeners connect-focus-listeners
 :disconnect-focus-listeners disconnect-focus-listeners}
