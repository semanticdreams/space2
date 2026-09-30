(fn split-interval-text [text]
  (assert (= (type text) :string) "temporal interval text must be a string")
  (when (text:match "^R")
    (error "temporal repeating interval syntax is not supported here"))
  (var bracket-depth 0)
  (var separator-index nil)
  (for [index 1 (length text)]
    (local char (text:sub index index))
    (if (= char "[")
        (set bracket-depth (+ bracket-depth 1))
        (= char "]")
        (do
          (set bracket-depth (- bracket-depth 1))
          (when (< bracket-depth 0)
            (error "temporal interval text has unbalanced zone brackets")))
        (and (= char "/") (= bracket-depth 0))
        (if separator-index
            (error "temporal interval text must contain one separator")
            (set separator-index index))))
  (when (not (= bracket-depth 0))
    (error "temporal interval text has unbalanced zone brackets"))
  (when (= separator-index nil)
    (error "temporal interval text must contain one separator"))
  (local start-text (text:sub 1 (- separator-index 1)))
  (local end-text (text:sub (+ separator-index 1)))
  (when (or (= start-text "") (= end-text ""))
    (error "temporal interval text requires start and end"))
  (values start-text end-text))

(fn endpoint-kind [text]
  (assert (= (type text) :string) "temporal interval endpoint text must be a string")
  (if (or (text:match "^PT") (text:match "^%-PT"))
      :exact-duration
      (and (or (text:match "^P") (text:match "^%-P"))
           (not (text:match "T")))
      :calendar-period
      :concrete))

(fn parse-digits [text label]
  (if (and text (text:match "^%d+$"))
      (tonumber text)
      (error (.. "invalid temporal exact duration " label))))

(fn fractional-second-nanoseconds [fraction]
  (when (< 9 (length fraction))
    (error "invalid temporal exact duration: fractional seconds exceed nanosecond precision"))
  (tonumber (.. fraction (string.rep "0" (- 9 (length fraction))))))

(fn parse-second-field [remaining]
  (local (seconds fraction) (remaining:match "^(%d+)%.?(%d*)S$"))
  (if seconds
      (do
        (local fraction-text (if (= fraction "") "" (.. "." fraction)))
        (local whole-nanoseconds (* (parse-digits seconds "seconds") 1000000000))
        (local fractional-nanoseconds
          (if (= fraction "")
              0
              (fractional-second-nanoseconds fraction)))
        (values (.. seconds fraction-text "S")
                (+ whole-nanoseconds fractional-nanoseconds)))
      (values nil nil)))

(fn parse-exact-duration [duration-api text]
  (assert (= (type text) :string) "temporal exact duration text must be a string")
  (local negative? (not (= (text:match "^%-") nil)))
  (local body (if negative? (text:sub 2) text))
  (when (not (= (body:sub 1 2) "PT"))
    (error "invalid temporal exact duration"))
  (local fields (body:sub 3))
  (when (= fields "")
    (error "invalid temporal exact duration: missing fields"))
  (var consumed "")
  (var total 0)
  (var saw-field? false)
  (local h (fields:match "^(%d+)H"))
  (when h
    (set consumed (.. consumed h "H"))
    (set total (+ total (* (parse-digits h "hours") 3600000000000)))
    (set saw-field? true))
  (local remaining-after-hours (fields:sub (+ (length consumed) 1)))
  (local m (remaining-after-hours:match "^(%d+)M"))
  (when m
    (set consumed (.. consumed m "M"))
    (set total (+ total (* (parse-digits m "minutes") 60000000000)))
    (set saw-field? true))
  (local remaining-after-minutes (fields:sub (+ (length consumed) 1)))
  (local (seconds-consumed seconds-nanoseconds) (parse-second-field remaining-after-minutes))
  (when seconds-consumed
    (set consumed (.. consumed seconds-consumed))
    (set total (+ total seconds-nanoseconds))
    (set saw-field? true))
  (when (or (not saw-field?) (not (= consumed fields)))
    (error "invalid temporal exact duration"))
  (duration-api.from-nanoseconds (if negative? (- total) total)))

{:split-interval-text split-interval-text
 :endpoint-kind endpoint-kind
 :parse-exact-duration parse-exact-duration}
