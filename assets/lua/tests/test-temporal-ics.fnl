(local tests [])
(local grammar (require :temporal/ics/grammar))

(fn assert= [actual expected message]
  (assert (= actual expected) (or message (.. "expected " (tostring expected) ", got " (tostring actual)))))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn assert-error-contains [f fragment message]
  (local err (assert-error f message))
  (assert (tostring err):find fragment 1 true)
  err)

(fn grammar-unfolds-crlf-and-lf-lines []
  (local crlf-lines (grammar.unfold-lines "SUMMARY:Alpha\r\n beta\r\nDTSTART:20261001T090000\r\n"))
  (assert= (# crlf-lines) 2 "CRLF input should produce two unfolded lines")
  (assert= (. crlf-lines 1) "SUMMARY:Alphabeta")
  (assert= (. crlf-lines 2) "DTSTART:20261001T090000")
  (local lf-lines (grammar.unfold-lines "SUMMARY:Alpha\n beta\nDTSTART:20261001T090000\n"))
  (assert= (# lf-lines) 2 "LF input should produce two unfolded lines")
  (assert= (. lf-lines 1) "SUMMARY:Alphabeta")
  (assert= (. lf-lines 2) "DTSTART:20261001T090000"))

(fn grammar-parses-names-params-and-values []
  (local dtstart (grammar.parse-content-line "DTSTART;TZID=America/New_York:20261001T090000" 7))
  (assert= dtstart.kind :temporal-ics-content-line)
  (assert= dtstart.name "DTSTART")
  (assert= dtstart.params.TZID "America/New_York")
  (assert= dtstart.value "20261001T090000")
  (assert= dtstart.source-order 7)
  (local summary (grammar.parse-content-line "SUMMARY:Review\\, plan\\; ship\\\\done\\nNext" 8))
  (assert= summary.name "SUMMARY")
  (assert= summary.value "Review, plan; ship\\done\nNext"))

(fn grammar-rejects-malformed-lines-and-escapes []
  (assert-error-contains #(grammar.parse-content-line "SUMMARY no colon" 1)
                         "content line"
                         "missing colon should mention content line")
  (assert-error-contains #(grammar.parse-content-line "BAD NAME:value" 1)
                         "property"
                         "invalid property name should mention property")
  (assert-error-contains #(grammar.unescape-text "bad\\q")
                         "escape"
                         "unknown escape should mention escape")
  (assert-error-contains #(grammar.unescape-text "bad\\")
                         "escape"
                         "trailing backslash should mention escape"))

(fn grammar-emits-folded-content-lines []
  (local escaped (grammar.emit-content-line "SUMMARY" {} "Review, plan; ship\\done\nNext" {:line-ending :lf}))
  (assert= escaped "SUMMARY:Review\\, plan\\; ship\\\\done\\nNext")
  (local long-description (string.rep "a" 90))
  (local folded (grammar.emit-content-line "DESCRIPTION" {} long-description))
  (assert (folded:find "\r\n " 1 true))
  (assert (= (folded:sub 1 12) "DESCRIPTION:")))

(table.insert tests {:name "grammar unfolds CRLF and LF lines"
                     :fn grammar-unfolds-crlf-and-lf-lines})
(table.insert tests {:name "grammar parses names params and values"
                     :fn grammar-parses-names-params-and-values})
(table.insert tests {:name "grammar rejects malformed lines and escapes"
                     :fn grammar-rejects-malformed-lines-and-escapes})
(table.insert tests {:name "grammar emits folded content lines"
                     :fn grammar-emits-folded-content-lines})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-ics" :tests tests})))

{:name "temporal-ics" :tests tests :main main}
