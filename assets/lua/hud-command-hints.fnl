(local glm (require :glm))
(local Text (require :text))

(local Padding (require :padding))
(local Card (require :card))
(local CommandHint (require :command-hints))
(local Runtime (require :state-runtime))
(local {: codepoints-from-text : measure-single-line} (require :text-utils))

(local entry CommandHint.entry)
(local key-label CommandHint.key-label)
(local SDLK_F1 CommandHint.KEY_F1)

(local collapsed-section-order [:focus :context :mode])
(local overlay-section-order [:mode :focus :context])

(fn push-section! [target id title entries]
  (when (> (length entries) 0)
    (table.insert target {:id id :title title :entries entries})))

(fn current-state [hud]
  (local states (and hud hud.states))
  (and states states.active-state
       (states:active-state)))

(fn current-state-name [hud]
  (local states (and hud hud.states))
  (and states states.active-name
       (states:active-name)))

(fn current-focus-manager [hud]
  (assert hud "CommandHints requires a HUD")
  (assert hud.get-focus-manager "CommandHints HUD must expose :get-focus-manager")
  (hud:get-focus-manager))

(fn active-focused-node [hud]
  (local focus-manager (current-focus-manager hud))
  (and focus-manager focus-manager.get-focused-node
       (focus-manager:get-focused-node)))

(fn resolve-provider [owner]
  (local provider (and owner owner.command_hints_provider))
  (and provider
       (fn [payload]
         (provider owner payload))))

(fn collect-provider-sections [provider payload default-id default-title]
  (local sections [])
  (when provider
    (local result (provider payload))
    (if (and result result.entries)
        (push-section! sections
                       (or result.id default-id)
                       (or result.title default-title)
                       result.entries)
        (if (= (type result) :table)
            (each [_ section (ipairs result)]
              (when (and section section.entries)
                (push-section! sections
                               (or section.id default-id)
                               (or section.title default-title)
                               section.entries))))))
  sections)

(fn focus-sections [hud expanded?]
  (local node (active-focused-node hud))
  (collect-provider-sections (resolve-provider node)
                             {:expanded? expanded?
                              :state-name (current-state-name hud)
                              :state (current-state hud)}
                             :focus
                             "FOCUS"))

(fn state-sections [hud expanded?]
  (local state (current-state hud))
  (local focus-manager (current-focus-manager hud))
  (collect-provider-sections (resolve-provider state)
                             {:expanded? expanded?
                              :state-name (current-state-name hud)
                              :focus-node (active-focused-node hud)
                              :focus-manager focus-manager
                              :active-input (Runtime.active-input)}
                             :mode
                             "MODE"))

(fn world-context-sections [hud expanded?]
  (local contrib (and hud hud.world-hud-contrib))
  (local focus-manager (current-focus-manager hud))
  (collect-provider-sections (resolve-provider contrib)
                             {:expanded? expanded?
                              :state-name (current-state-name hud)
                              :state (current-state hud)
                              :focus-node (active-focused-node hud)
                              :focus-manager focus-manager
                              :active-input (Runtime.active-input)}
                             :context
                             "CONTEXT"))

(fn context-sections [hud expanded?]
  (world-context-sections hud expanded?))

(fn overlay-toggle-command [expanded?]
  (entry "f1" (if expanded? "less" "more") {:priority 999 :id :toggle}))

(fn format-command [hint]
  (.. "[" (or hint.key "") "] " (or hint.label "")))

(fn compare-entries [left right]
  (if (< left.priority right.priority)
      true
      (if (> left.priority right.priority)
          false
          (< (or left._seq 0) (or right._seq 0)))))

(fn sort-entries! [entries]
  (table.sort entries compare-entries)
  entries)

(fn copy-entry [hint seq]
  (local copied {})
  (each [k v (pairs hint)]
    (set (. copied k) v))
  (set copied._seq seq)
  copied)

(fn dedup-entries [entries]
  (local seen {})
  (local result [])
  (each [_ hint (ipairs entries)]
    (local key (.. (or hint.key "") "\31" (or hint.label "")))
    (when (not (. seen key))
      (set (. seen key) true)
      (table.insert result hint)))
  result)

(fn gather-sections [hud expanded?]
  (var seq 0)
  (local sections [])

  (fn push-sections [items]
    (each [_ section (ipairs items)]
      (local entries [])
      (each [_ hint (ipairs (or section.entries []))]
        (set seq (+ seq 1))
        (table.insert entries (copy-entry hint seq)))
      (when (> (length entries) 0)
        (push-section! sections
                       (or section.id :mode)
                       (or section.title "MODE")
                       (sort-entries! entries)))))

  (push-sections (focus-sections hud expanded?))
  (push-sections (context-sections hud expanded?))
  (push-sections (state-sections hud expanded?))

  (local toggle-entry (overlay-toggle-command expanded?))
  (set seq (+ seq 1))
  (set toggle-entry._seq seq)
  (var mode-section nil)
  (each [_ section (ipairs sections)]
    (when (= section.id :mode)
      (set mode-section section)))
  (if mode-section
      (table.insert mode-section.entries toggle-entry)
      (push-section! sections :mode "MODE" [toggle-entry]))
  sections)

(fn collapsed-entries [sections]
  (local merged [])
  (each [_ section-id (ipairs collapsed-section-order)]
    (each [_ section (ipairs sections)]
      (when (= section.id section-id)
        (each [_ hint (ipairs section.entries)]
          (when hint.show-collapsed?
            (table.insert merged hint))))))
  (dedup-entries (sort-entries! merged)))

(fn measure-line-width [text style]
  (local layout {:measure (glm.vec3 0)})
  (measure-single-line layout (codepoints-from-text text) style)
  (. layout.measure 1))

(fn collapsed-char-text [entries max-chars]
  (var toggle nil)
  (local regular [])
  (each [_ hint (ipairs entries)]
    (if (= hint.id :toggle)
        (set toggle hint)
        (table.insert regular hint)))
  (local toggle-chunk (and toggle (format-command toggle)))
  (local toggle-size (and toggle-chunk (string.len toggle-chunk)))
  (local items [])
  (var used 0)
  (each [_ hint (ipairs regular)]
    (local chunk (format-command hint))
    (local prefix-cost (if (> (length items) 0) 3 0))
    (local candidate-used (+ used prefix-cost (string.len chunk)))
    (local required-used
      (if toggle-chunk
          (+ candidate-used
             (if (> (+ (length items) 1) 0) 3 0)
             toggle-size)
          candidate-used))
    (when (<= required-used max-chars)
      (table.insert items chunk)
      (set used candidate-used)))
  (when toggle-chunk
    (local toggle-prefix (if (> (length items) 0) 3 0))
    (when (<= (+ used toggle-prefix toggle-size) max-chars)
      (table.insert items toggle-chunk)))
  (table.concat items "   "))

(fn collapsed-width-text [entries max-width style]
  (var toggle nil)
  (local regular [])
  (each [_ hint (ipairs entries)]
    (if (= hint.id :toggle)
        (set toggle hint)
        (table.insert regular hint)))
  (local toggle-chunk (and toggle (format-command toggle)))
  (local items [])
  (each [_ hint (ipairs regular)]
    (local chunk (format-command hint))
    (local candidate-text
      (if (> (length items) 0)
          (.. (table.concat items "   ") "   " chunk)
          chunk))
    (local required-text
      (if toggle-chunk
          (table.concat [candidate-text toggle-chunk] "   ")
          candidate-text))
    (when (<= (measure-line-width required-text style) max-width)
      (table.insert items chunk)))
  (when toggle-chunk
    (local final-text
      (if (> (length items) 0)
          (.. (table.concat items "   ") "   " toggle-chunk)
          toggle-chunk))
    (when (<= (measure-line-width final-text style) max-width)
      (table.insert items toggle-chunk)))
  (if (and (= (length items) 0) toggle-chunk)
      toggle-chunk
      (table.concat items "   ")))

(fn collapsed-text [sections opts]
  (local options (or opts {}))
  (local entries (collapsed-entries sections))
  (if (and options.max-width
           options.style
           (> options.max-width 0))
      (collapsed-width-text entries options.max-width options.style)
      (collapsed-char-text entries (or options.max-chars 96))))

(fn overlay-text [sections]
  (local lines ["COMMANDS"])
  (each [_ section-id (ipairs overlay-section-order)]
    (each [_ section (ipairs sections)]
      (when (= section.id section-id)
        (table.insert lines "")
        (table.insert lines section.title)
        (each [_ hint (ipairs section.entries)]
          (table.insert lines (format-command hint))))))
  (table.concat lines "\n"))

(fn toggle-key-payload? [payload]
  (= (and payload payload.key) SDLK_F1))

(fn command-hints-card-builder [content]
  (fn build-content [_ctx]
    content)
  (fn build-card [inner-ctx]
    ((Card
       {:child
        (Padding {:edge-insets [0.6 0.45]
                  :child build-content})})
     inner-ctx)))

(fn overlay-builder [manager]
  (local ScrollArea (require :scroll-area))
  (fn build [ctx]
    (var text-entity nil)
    (local content
      ((Text {:text (overlay-text manager.sections)}) ctx))
    (set text-entity content)
    (local clipped ((ScrollArea {:name "command-hints-clip"
                                 :child (command-hints-card-builder content)}) ctx))
    (set clipped.set-text
         (fn [_self text]
           (text-entity:set-text text)))
    clipped))

(fn passive-event? [event-name]
  (or (= event-name :updated)
      (= event-name :key-up)
      (= event-name :text-input)
      (= event-name :text-editing)
      (= event-name :mouse-motion)
      (= event-name :mouse-wheel)
      (= event-name :touch-motion)
      (= event-name :pen-motion)
      (= event-name :pen-axis)
      (= event-name :gamepad-axis-motion)))

(fn CommandHints [hud]
  (local self {:hud hud
               :sections []
               :expanded? false
               :overlay-element nil
               :collapsed ""})

  (fn refresh-model [self opts]
    (set self.sections (gather-sections self.hud self.expanded?))
    (set self.collapsed (collapsed-text self.sections opts)))

  (fn sync-overlay [self]
    (if self.expanded?
        (do
          (if (not self.overlay-element)
              (set self.overlay-element
                   (self.hud:add-overlay-child {:builder (overlay-builder self)
                                                 :layer :middle :fill-parent? true
                                                 :depth-offset-index 200})))
          (when self.overlay-element.set-text
            (self.overlay-element:set-text (overlay-text self.sections))))
        (when self.overlay-element
          (self.hud:remove-overlay-child self.overlay-element)
          (set self.overlay-element nil))))

  (fn update [self opts]
    (refresh-model self opts)
    (sync-overlay self)
    self.collapsed)

  (fn close-overlay [self]
    (set self.expanded? false)
    (refresh-model self nil)
    (sync-overlay self)
    false)

  (fn toggle-overlay [self]
    (set self.expanded? (not self.expanded?))
    (refresh-model self nil)
    (sync-overlay self)
    true)

  (fn reset-overlay [self]
    (when self.overlay-element
      (self.hud:remove-overlay-child self.overlay-element)
      (set self.overlay-element nil))
    (set self.expanded? false)
    (refresh-model self nil)
    false)

  (fn handle-toggle-key [self payload]
    (if (toggle-key-payload? payload)
        (toggle-overlay self)
        false))

  (fn close-on-handled-event [self event-name payload]
    (if (or (not self.expanded?)
            (passive-event? event-name))
        false
        (if (and (= event-name :key-down)
                 (toggle-key-payload? payload))
            false
            (close-overlay self))))

  (set self.update update)
  (set self.close-overlay close-overlay)
  (set self.toggle-overlay toggle-overlay)
  (set self.reset-overlay reset-overlay)
  (set self.handle-toggle-key handle-toggle-key)
  (set self.close-on-handled-event close-on-handled-event)
  (set self.toggle-key-payload? toggle-key-payload?)
  (set self.get-collapsed-text (fn [manager]
                                 (manager:update)))
  (set self.get-overlay-text (fn [manager]
                               (manager:update)
                               (overlay-text manager.sections)))
  (set self.overlay-open? (fn [_self]
                            self.expanded?))
  (refresh-model self nil)
  self)

{:CommandHints CommandHints
 :toggle-key-payload? toggle-key-payload?
 :overlay-text overlay-text
 :collapsed-text collapsed-text
 :toggle-key-label (key-label SDLK_F1)}
