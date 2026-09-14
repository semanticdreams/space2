(local tests [])
(local fs (require :fs))
(local process (require :process))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "lazy-text-buffer"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "case-" (os.time) "-" temp-counter)))

(fn make-clean-temp-dir []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn source-for-file [path opts]
  (LazyTextSource.file path opts))

(fn buffer-for-file [path opts]
  (LazyTextBuffer {:source (source-for-file path opts)
                   :chunk-bytes (and opts opts.chunk-bytes)}))

(fn string-contains? [haystack needle]
  (not= nil (string.find (tostring haystack) needle 1 true)))

(fn assert-error-contains [needle f arg]
  (local (ok err) (pcall f arg))
  (assert (not ok) "expected operation to fail")
  (assert (string-contains? err needle)
          (.. "expected error to contain " needle ", got " (tostring err))))

(fn call-with-read-file-disabled [f arg]
  (local original-read-file fs.read-file)
  (set fs.read-file (fn [_path] (error "fs.read-file must not be called")))
  (local (ok result) (pcall f arg))
  (set fs.read-file original-read-file)
  (if ok
      result
      (error result)))

(fn call-with-large-concat-disabled [limit f arg]
  (local original-concat table.concat)
  (set table.concat
       (fn [items sep i j]
         (var total 0)
         (local start (or i 1))
         (local finish (or j (length items)))
         (for [index start finish]
           (local item (. items index))
           (when (= (type item) :string)
             (set total (+ total (# item)))))
         (when (> total limit)
           (error (.. "table.concat materialized " total " bytes; limit=" limit)))
         (original-concat items sep i j)))
  (local (ok result) (pcall f arg))
  (set table.concat original-concat)
  (if ok
      result
      (error result)))

(fn instrument-source-reads [source]
  (local original-read-range source.read-range)
  (set source.read-count 0)
  (set source.bytes-requested 0)
  (set source.max-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.read-count (+ self.read-count 1))
         (set self.bytes-requested (+ self.bytes-requested max-bytes))
         (set self.max-requested (math.max self.max-requested max-bytes))
         (original-read-range self offset max-bytes)))
  source)

(fn reset-source-read-stats [source]
  (set source.read-count 0)
  (set source.bytes-requested 0)
  (set source.max-requested 0))

(fn assert-source-range [file]
  (local source (source-for-file file {:chunk-bytes 4}))
  (assert (= source.path (fs.absolute file)))
  (local range (source:read-range 2 3))
  (assert (= range.bytes "cde"))
  (assert (= range.offset 2))
  (assert (= range.bytes-read 3)))

(fn save-buffer [buffer]
  (buffer:save))

(fn insert-invalid-byte [buffer]
  (buffer:insert-text (string.char 255)))

(fn space-bin []
  (if (fs.exists "./build/space")
      "./build/space"
      "./space"))

(fn lazy-text-source-reads-bounded-byte-ranges []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "source.txt"))
  (fs.write-file file "abcdef")
  (call-with-read-file-disabled assert-source-range file))

(fn lazy-text-source-records-baseline-token []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "token.txt"))
  (fs.write-file file "abcdef")
  (local source (source-for-file file))
  (assert source.baseline-token "baseline token should be populated")
  (assert (= source.baseline-token.path (fs.absolute file)))
  (assert (= source.size 6)))

(fn lazy-text-buffer-viewport-reads-only-requested-rows []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "viewport.txt"))
  (fs.write-file file "line-0\nline-1\nline-2\nline-3\n")
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local snapshot (buffer:get-viewport {:line 1 :column 0 :lines 2 :columns 20}))
  (assert (= (length snapshot.rows) 2))
  (assert (= (. snapshot.rows 1 :text) "line-1"))
  (assert (= (. snapshot.rows 2 :text) "line-2"))
  (assert (= snapshot.start-line 1))
  (assert (= snapshot.requested-lines 2))
  (assert (= snapshot.requested-columns 20)))

(fn lazy-text-buffer-indexes-lf-and-crlf-across-chunks []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "newlines.txt"))
  (fs.write-file file "aa\r\nbb\ncc\r\ndd")
  (local buffer (buffer-for-file file {:chunk-bytes 3}))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 4 :columns 10}))
  (assert (= (length snapshot.rows) 4))
  (assert (= (. snapshot.rows 1 :text) "aa"))
  (assert (= (. snapshot.rows 1 :newline-bytes) 2))
  (assert (= (. snapshot.rows 2 :text) "bb"))
  (assert (= (. snapshot.rows 2 :newline-bytes) 1))
  (assert (= (. snapshot.rows 3 :text) "cc"))
  (assert (= (. snapshot.rows 3 :newline-bytes) 2))
  (assert (= (. snapshot.rows 4 :text) "dd")))

(fn lazy-text-buffer-direct-line-request-handles-crlf-split-across-chunks []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "direct-crlf.txt"))
  (fs.write-file file "aa\r\nbb\ncc")
  (local buffer (buffer-for-file file {:chunk-bytes 3}))
  (local snapshot (buffer:get-viewport {:line 2 :column 0 :lines 1 :columns 10}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "cc") "direct request after split CRLF should start at later requested line")
  (assert (= row.start-byte 7) "line 2 should start after aa CRLF and bb LF")
  (buffer:move-caret-to-line-column 2 0)
  (assert (= buffer.cursor-byte 7) "caret line 2 column 0 should land at cc start"))

(fn lazy-text-buffer-adjacent-codepoint-from-anchor-stays-within-line []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "anchor-adjacent.txt"))
  (fs.write-file file "abc\nxyz")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (local left (buffer:adjacent-codepoint-from-anchor {:byte 2 :line 0 :column 2} -1))
  (assert left.bounded? "left anchor movement should be bounded")
  (assert left.moved? "left anchor movement should move")
  (assert (= left.byte 1))
  (assert (= left.line 0))
  (assert (= left.column 1))
  (local right (buffer:adjacent-codepoint-from-anchor {:byte 2 :line 0 :column 2} 1))
  (assert right.bounded? "right anchor movement should be bounded")
  (assert right.moved? "right anchor movement should move")
  (assert (= right.byte 3))
  (assert (= right.line 0))
  (assert (= right.column 3))
  (local line-end (buffer:adjacent-codepoint-from-anchor {:byte 3 :line 0 :column 3} 1))
  (assert line-end.bounded? "line-end anchor movement should be bounded")
  (assert (not line-end.moved?) "movement from line end should not cross newline")
  (assert line-end.line-end? "line-end movement should report line-end")
  (assert (= line-end.byte 3))
  (assert (= line-end.line 0))
  (assert (= line-end.column 3)))

(fn lazy-text-buffer-line-column-from-near-anchor-is-bounded []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "anchor-near-line-column.txt"))
  (fs.write-file file (string.rep "a" 100000))
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 16})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16}))
  (local anchor {:byte 99990 :line 0 :column 99990})
  (local read-budget (* 4 (math.max 16 buffer.chunk-bytes)))
  (reset-source-read-stats source)
  (local result (buffer:move-to-line-column-from-anchor anchor 0 99995 {:max-codepoints 16}))
  (assert result.bounded? "near anchor line-column move should be bounded")
  (assert (= result.byte 99995))
  (assert (= result.line 0))
  (assert (= result.column 99995))
  (assert (not result.clamped?) "near anchor line-column move should not clamp")
  (assert (<= source.max-requested (math.max 16 buffer.chunk-bytes))
          (.. "near anchor move should keep source read requests bounded; max=" source.max-requested))
  (assert (<= source.read-count 4)
          (.. "near anchor move should use a bounded number of source reads; reads=" source.read-count))
  (assert (<= source.bytes-requested read-budget)
           (.. "near anchor move should keep total requested bytes bounded; bytes=" source.bytes-requested)))

(fn lazy-text-buffer-next-word-start-streams_long_line []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "next-word-long-line.txt"))
  (fs.write-file file (.. (string.rep "a" 100000) " next"))
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 16})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16}))
  (local result
    (call-with-large-concat-disabled
      4096
      (fn [target-buffer]
        (target-buffer:next-word-start-from-anchor {:byte 0 :line 0 :column 0}))
      buffer))
  (assert result "next word start should return a result")
  (assert result.moved? "next word start should report moved")
  (assert (= result.column 100001) (.. "next word should land after long run and space; column=" result.column))
  (assert (<= source.max-requested 16)
          (.. "word motion should keep source read requests bounded; max=" source.max-requested)))

(fn lazy-text-buffer-next-word-start-counts_utf8_punctuation_as_codepoint []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "next-word-utf8-punctuation.txt"))
  (fs.write-file file "λ next")
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 4})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 4}))
  (local result (buffer:next-word-start-from-anchor {:byte 0 :line 0 :column 0}))
  (assert result "UTF-8 punctuation word motion should return a result")
  (assert result.moved? "UTF-8 punctuation word motion should move")
  (assert (= result.byte 3) (.. "UTF-8 punctuation w should land at byte 3; byte=" result.byte))
  (assert (= result.column 2) (.. "UTF-8 punctuation w should land at column 2; column=" result.column)))

(fn lazy-text-buffer-next-word-start-completes_utf8_across_chunk_boundary []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "next-word-utf8-chunk-boundary.txt"))
  (fs.write-file file "λ next")
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 1})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 1}))
  (local result (buffer:next-word-start-from-anchor {:byte 0 :line 0 :column 0}))
  (assert result "UTF-8 boundary word motion should return a result")
  (assert result.moved? "UTF-8 boundary word motion should move")
  (assert (= result.byte 3) (.. "UTF-8 boundary w should land at byte 3; byte=" result.byte))
  (assert (= result.column 2) (.. "UTF-8 boundary w should land at column 2; column=" result.column))
  (assert (<= source.max-requested 4)
          (.. "UTF-8 boundary retry should request at most one UTF-8 codepoint; max=" source.max-requested)))

(fn lazy-text-buffer-next-word-start-handles_adjacent_multibyte_punctuation_boundaries []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "next-word-adjacent-utf8-punctuation.txt"))
  (fs.write-file file "λ🙂 next")
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 1})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 1}))
  (local result (buffer:next-word-start-from-anchor {:byte 0 :line 0 :column 0}))
  (assert result "adjacent UTF-8 punctuation word motion should return a result")
  (assert result.moved? "adjacent UTF-8 punctuation word motion should move")
  (assert (= result.byte 7) (.. "adjacent UTF-8 punctuation w should land at byte 7; byte=" result.byte))
  (assert (= result.column 3) (.. "adjacent UTF-8 punctuation w should land at column 3; column=" result.column))
  (assert (<= source.max-requested 4)
          (.. "adjacent UTF-8 retry should request at most one UTF-8 codepoint; max=" source.max-requested)))

(fn lazy-text-buffer-line-column-from-far-line-start-reports-unbounded []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "anchor-far-line-column.txt"))
  (fs.write-file file (string.rep "a" 100000))
  (local source (instrument-source-reads (source-for-file file {:chunk-bytes 16})))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16}))
  (local anchor {:byte 0 :line 0 :column 0})
  (buffer:move-caret-to-byte 42)
  (local original-cursor-byte buffer.cursor-byte)
  (local read-budget (* 4 (math.max 16 buffer.chunk-bytes)))
  (reset-source-read-stats source)
  (local result (buffer:move-to-line-column-from-anchor anchor 0 99995 {:max-codepoints 16}))
  (assert (not result.bounded?) "far anchor line-column move should report unbounded")
  (assert (= result.reason :anchor-too-far))
  (assert (= buffer.cursor-byte original-cursor-byte) "unbounded anchor move must not move the buffer cursor")
  (assert (<= source.max-requested (math.max 16 buffer.chunk-bytes))
          (.. "far anchor move should keep source read requests bounded; max=" source.max-requested))
  (assert (<= source.read-count 4)
          (.. "far anchor move should use a bounded number of source reads; reads=" source.read-count))
  (assert (<= source.bytes-requested read-budget)
          (.. "far anchor move should keep total requested bytes bounded; bytes=" source.bytes-requested)))

(fn lazy-text-buffer-builds-viewport-row-from-anchor-without-prefix-materialization []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "anchor-viewport-row.txt"))
  (fs.write-file file (string.rep "a" 100000))
  (local buffer (buffer-for-file file {:chunk-bytes 16}))
  (local anchor {:byte 99990 :line 0 :column 99990})
  (call-with-large-concat-disabled
    4096
    (fn [target-buffer]
      (local row (target-buffer:build-viewport-row-from-anchor anchor 5))
      (assert (= row.line 0))
      (assert (= row.start-byte 99990))
      (assert (= row.start-column 99990))
      (assert (= row.text "aaaaa"))
      (assert (= (. row.column-byte-offsets 1) 0))
      (assert (= (. row.column-byte-offsets 2) 1))
      (assert (= (. row.column-byte-offsets 3) 2))
      (assert (= (. row.column-byte-offsets 4) 3))
      (assert (= (. row.column-byte-offsets 5) 4))
      (assert (= (. row.column-byte-offsets 6) 5))
      (assert (not row.partial?) "viewport row from anchor should preserve fully-known row partial flag"))
    buffer))

(fn lazy-text-buffer-maps-utf8-columns-to-byte-offsets []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "utf8.txt"))
  (fs.write-file file "aλ🙂z")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "aλ🙂z"))
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (assert (= (. row.column-byte-offsets 3) 3))
  (assert (= (. row.column-byte-offsets 4) 7))
  (assert (= (. row.column-byte-offsets 5) 8)))

(fn lazy-text-buffer-clips-nonzero-utf8-columns-with-relative-offsets []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "utf8-column.txt"))
  (fs.write-file file "aλ🙂z")
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local snapshot (buffer:get-viewport {:line 0 :column 1 :lines 1 :columns 2}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "λ🙂"))
  (assert (= row.start-byte 1) "clipped row start-byte should be visible slice start")
  (assert (= row.end-byte 7) "clipped row end-byte should be visible slice end")
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 2))
  (assert (= (. row.column-byte-offsets 3) 6)))

(fn lazy-text-buffer-clips-before-multibyte-boundary []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "utf8-boundary.txt"))
  (fs.write-file file "a🙂z")
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 1}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "a"))
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (buffer:move-caret-to-line-column 0 1)
  (assert (= buffer.cursor-byte 1) "caret column 1 should resolve before emoji bytes"))

(fn lazy-text-buffer-bounds-newline-free-viewport-source-reads []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "long-line.txt"))
  (local parts [])
  (for [_ 1 4096]
    (table.insert parts "abcdefghij"))
  (fs.write-file file (table.concat parts ""))
  (local source (source-for-file file {:chunk-bytes 16}))
  (local original-read-range source.read-range)
  (set source.read-count 0)
  (set source.bytes-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.read-count (+ self.read-count 1))
         (set self.bytes-requested (+ self.bytes-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16}))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 5}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "abcde"))
  (assert row.partial? "long newline-free row should report partial metadata")
  (assert (not row.line-end-known?) "line ending should be unknown after bounded scan")
  (assert (<= source.read-count 2) (.. "viewport should not scan to EOF; reads=" source.read-count)))

(fn lazy-text-buffer-line-column-move-does-not-materialize-long-line []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "long-line-move.txt"))
  (local text (string.rep "abcdefghij" 4096))
  (fs.write-file file text)
  (local source (source-for-file file {:chunk-bytes 16}))
  (local original-read-range source.read-range)
  (set source.max-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.max-requested (math.max self.max-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16}))
  (call-with-large-concat-disabled
    4096
    (fn [target-buffer]
      (target-buffer:move-caret-to-line-column 0 (# text)))
    buffer)
  (assert (= buffer.cursor-byte buffer.size) "wide line-column move should land at EOF")
  (assert (<= source.max-requested 16) (.. "line-column move should keep source read requests bounded; max=" source.max-requested))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 5}))
  (assert (= (. snapshot.rows 1 :text) "abcde") "viewport after long-line move should remain clipped"))

(fn lazy-text-buffer-horizontal-viewport-does-not-materialize-prefix []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "long-line-horizontal.txt"))
  (local text (string.rep "abcdefghij" 4096))
  (fs.write-file file text)
  (local buffer (buffer-for-file file {:chunk-bytes 16}))
  (call-with-large-concat-disabled
    4096
    (fn [target-buffer]
      (local snapshot (target-buffer:get-viewport {:line 0 :column (- (# text) 5) :lines 1 :columns 5}))
      (local row (. snapshot.rows 1))
      (assert (= row.text "fghij") "horizontally scrolled viewport should render only visible suffix")
      (assert (= row.start-byte (- (# text) 5)) "row start-byte should move to visible suffix")
      (assert (= (. row.column-byte-offsets 1) 0))
      (assert (= (. row.column-byte-offsets 6) 5)))
    buffer))

(fn lazy-text-buffer-line-column-move-resolves-lines-beyond-index-budget []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "far-logical-move.txt"))
  (fs.write-file file (string.rep "x\n" 1000))
  (local source (source-for-file file {:chunk-bytes 16}))
  (local original-read-range source.read-range)
  (set source.max-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.max-requested (math.max self.max-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16 :line-index-scan-budget 64}))
  (local final-line (- (buffer:get-line-count) 1))
  (buffer:move-caret-to-line-column final-line 0)
  (assert (= buffer.cursor-byte buffer.size)
          (.. "far logical line move should land at final line start; cursor=" buffer.cursor-byte " size=" buffer.size))
  (assert (<= source.max-requested 4096)
          (.. "far logical line move should keep individual reads bounded; max=" source.max-requested)))

(fn lazy-text-buffer-bounds-missing-line-discovery-in-newline-free-file []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "missing-line.txt"))
  (local parts [])
  (for [_ 1 4096]
    (table.insert parts "abcdefghij"))
  (fs.write-file file (table.concat parts ""))
  (local source (source-for-file file {:chunk-bytes 16}))
  (local original-read-range source.read-range)
  (set source.read-count 0)
  (set source.bytes-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.read-count (+ self.read-count 1))
         (set self.bytes-requested (+ self.bytes-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16 :line-index-scan-budget 64}))
  (local snapshot (buffer:get-viewport {:line 24 :column 0 :lines 1 :columns 5}))
  (local row (. snapshot.rows 1))
  (assert row.partial? "unknown later line in newline-free file should be marked partial")
  (assert (not row.line-end-known?) "unknown later line must not be represented as fully discovered")
  (assert (<= source.read-count 6) (.. "missing line discovery should not scan to EOF; reads=" source.read-count))
  (assert (<= source.bytes-requested 128) (.. "missing line discovery should keep requested bytes bounded; bytes=" source.bytes-requested)))

(fn lazy-text-buffer-bounds-far-line-discovery-with-many-newlines []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "many-newlines.txt"))
  (local parts [])
  (for [_ 1 10000]
    (table.insert parts "x\n"))
  (fs.write-file file (table.concat parts ""))
  (local source (source-for-file file {:chunk-bytes 16}))
  (local original-read-range source.read-range)
  (set source.read-count 0)
  (set source.bytes-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.read-count (+ self.read-count 1))
         (set self.bytes-requested (+ self.bytes-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 16 :line-index-scan-budget 64}))
  (local snapshot (buffer:get-viewport {:line 1000 :column 0 :lines 1 :columns 5}))
  (local row (. snapshot.rows 1))
  (assert row.partial? "far line discovery should become partial when line-index budget is exhausted")
  (assert (not row.line-end-known?) "far line discovery should not pretend target line is known after budget exhaustion")
  (assert (<= source.read-count 6) (.. "far newline discovery should keep reads bounded; reads=" source.read-count))
  (assert (<= source.bytes-requested 128) (.. "far newline discovery should keep requested bytes bounded; bytes=" source.bytes-requested)))

(fn lazy-text-buffer-inserts-and-deletes-across-piece-boundaries []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "edit.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-to-byte 3)
  (buffer:insert-text "XY")
  (assert buffer.dirty?)
  (buffer:delete-before-cursor)
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 20}))
  (assert (= (. snapshot.rows 1 :text) "abcXdef")))

(fn lazy-text-buffer-selection-copies-across-original-and-added-pieces []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "selection.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-to-byte 3)
  (buffer:insert-text "XY")
  (buffer:set-selection 2 7)
  (assert (= (buffer:get-selected-text) "cXYde")))

(fn lazy-text-buffer-selection-copies-large-original-span-completely []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "large-selection.txt"))
  (local parts [])
  (for [_ 1 300000]
    (table.insert parts "a"))
  (fs.write-file file (table.concat parts ""))
  (local buffer (buffer-for-file file {:chunk-bytes 65536}))
  (buffer:set-selection 0 300000)
  (local selected (buffer:get-selected-text))
  (assert (= (# selected) 300000) (.. "large original selection should not be truncated; bytes=" (# selected)))
  (assert (= (string.sub selected 1 1) "a"))
  (assert (= (string.sub selected 300000 300000) "a")))

(fn lazy-text-buffer-preserves-invalid-original-bytes-when-untouched []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid.bin"))
  (fs.write-file file (.. "ab" (string.char 255) "cd"))
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-to-byte 0)
  (buffer:insert-text "Z")
  (local result (buffer:save))
  (assert result.saved)
  (local raw (fs.read-byte-range file 0 16))
  (assert (= raw.bytes (.. "Zab" (string.char 255) "cd"))))

(fn lazy-text-buffer-renders-invalid-original-bytes-as-replacement []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid-visible.bin"))
  (fs.write-file file (.. "ab" (string.char 255) "cd"))
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}))
  (local row (. snapshot.rows 1))
  (assert (= row.text "ab�cd") "invalid visible byte should render as replacement and keep trailing text")
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (assert (= (. row.column-byte-offsets 3) 2))
  (assert (= (. row.column-byte-offsets 4) 3) "column after replacement should advance by the invalid source byte")
  (assert (= (. row.column-byte-offsets 5) 4))
  (assert (= (. row.column-byte-offsets 6) 5))
  (buffer:move-caret-to-line-column 0 3)
  (assert (= buffer.cursor-byte 3) "caret after replacement should land after invalid source byte")
  (buffer:move-caret-to-byte 0)
  (buffer:insert-text "Z")
  (local result (buffer:save))
  (assert result.saved)
  (local raw (fs.read-byte-range file 0 16))
  (assert (= raw.bytes (.. "Zab" (string.char 255) "cd")) "save must preserve untouched invalid original byte"))

(fn lazy-text-buffer-vertical-move-clamps-invalid-row-column-to-source-end []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid-vertical.bin"))
  (fs.write-file file (.. "abcdef\n" "a" (string.char 255) "b"))
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (buffer:move-caret-to-line-column 1 10)
  (assert (= buffer.cursor-byte buffer.size)
          (.. "wide target column should clamp to source/document end, cursor=" buffer.cursor-byte " size=" buffer.size)))

(fn lazy-text-buffer-renders-invalid-lead-before-ascii-as-replacement []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid-lead-ascii.bin"))
  (fs.write-file file (.. "a" (string.char 0xE2) "("))
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local row (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}) :rows 1))
  (assert (= row.text "a�(") "invalid lead byte should not swallow trailing ASCII")
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (assert (= (. row.column-byte-offsets 3) 2) "replacement should advance only over invalid lead byte")
  (assert (= (. row.column-byte-offsets 4) 3))
  (buffer:move-caret-to-line-column 0 2)
  (assert (= buffer.cursor-byte 2) "caret after replacement should be before trailing ASCII")
  (buffer:move-caret-to-line-column 0 3)
  (assert (= buffer.cursor-byte 3) "caret after trailing ASCII should reach source EOF"))

(fn lazy-text-buffer-renders-malformed-semantic-utf8-as-replacement []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid-semantic.bin"))
  (fs.write-file file (.. "a" (string.char 0xE0 0x80 0x80) "b" (string.char 0xED 0xA0 0x80) "c"))
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local row (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}) :rows 1))
  (assert (= row.text "a�b�c") "overlong and surrogate-shaped bytes should render as replacements and continue")
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (assert (= (. row.column-byte-offsets 3) 4) "replacement should advance over malformed source sequence")
  (assert (= (. row.column-byte-offsets 4) 5))
  (assert (= (. row.column-byte-offsets 5) 8) "surrogate replacement should advance over malformed source sequence")
  (assert (= (. row.column-byte-offsets 6) 9))
  (buffer:move-caret-to-line-column 0 2)
  (assert (= buffer.cursor-byte 4) "caret after malformed sequence should land after all offending source bytes"))

(fn lazy-text-buffer-renders-truncated-eof-utf8-as-replacement []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "invalid-truncated.bin"))
  (fs.write-file file (.. "a" (string.char 0xE2 0x82)))
  (local buffer (buffer-for-file file {:chunk-bytes 8}))
  (local row (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}) :rows 1))
  (assert (= row.text "a�") "truncated EOF sequence should render as replacement")
  (assert (= (. row.column-byte-offsets 1) 0))
  (assert (= (. row.column-byte-offsets 2) 1))
  (assert (= (. row.column-byte-offsets 3) 3) "truncated replacement should advance over remaining source bytes")
  (buffer:move-caret-to-line-column 0 2)
  (assert (= buffer.cursor-byte 3) "caret after truncated sequence should land at EOF"))

(fn lazy-text-buffer-save-streams-pieces-through-atomic-replace []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "save.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-to-byte 3)
  (buffer:insert-text "XY")
  (local result (buffer:save))
  (assert result.saved)
  (assert (not buffer.dirty?))
  (assert buffer.source.baseline-token)
  (assert (= buffer.source.baseline-token.size 8))
  (assert (= (fs.read-file file) "abcXYdef")))

(fn lazy-text-buffer-save-reports-external-modification-conflict []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-lazy-text-buffer:conflict-main"]
                              :env {:SPACE_DISABLE_AUDIO "1"
                                    :SPACE_ASSETS_PATH (os.getenv "SPACE_ASSETS_PATH")
                                    :FENNEL_PATH (os.getenv "FENNEL_PATH")
                                    :FENNEL_MACRO_PATH (os.getenv "FENNEL_MACRO_PATH")}
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "conflict child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn conflict-main []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "conflict.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:insert-text "Z")
  (fs.write-file file "external")
  (local (ok result) (pcall save-buffer buffer))
  (assert (not ok) "save should fail on external modification")
  (assert buffer.dirty? "conflict should leave dirty state set")
  (assert (string-contains? result "file changed since token")
          (.. "expected conflict error text, got " (tostring result))))

(fn lazy-text-buffer-save-detects-same-size-external-modification []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-lazy-text-buffer:same-size-conflict-main"]
                              :env {:SPACE_DISABLE_AUDIO "1"
                                    :SPACE_ASSETS_PATH (os.getenv "SPACE_ASSETS_PATH")
                                    :FENNEL_PATH (os.getenv "FENNEL_PATH")
                                    :FENNEL_MACRO_PATH (os.getenv "FENNEL_MACRO_PATH")}
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "same-size conflict child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn same-size-conflict-main []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "same-size-conflict.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:insert-text "Z")
  (fs.write-file file "uvwxyz")
  (local (ok result) (pcall save-buffer buffer))
  (assert (not ok) "save should fail on same-size external modification")
  (assert buffer.dirty? "same-size conflict should leave dirty state set")
  (assert (= (fs.read-file file) "uvwxyz") "same-size external edit must not be overwritten")
  (assert (string-contains? result "file changed since token")
          (.. "expected same-size conflict error text, got " (tostring result))))

(fn lazy-text-buffer-rejects-invalid-utf8-inserted-text []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "insert-invalid.txt"))
  (fs.write-file file "abcdef")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (assert-error-contains
    "LazyTextBuffer insert-text requires valid UTF-8"
    insert-invalid-byte
    buffer))

(fn lazy-text-buffer-moves_caret_by_utf8_boundaries []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "utf8-move.txt"))
  (fs.write-file file "éx")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-horizontal 1)
  (assert (= buffer.cursor-byte 2) "right movement should skip the full multibyte character")
  (buffer:move-caret-horizontal -1)
  (assert (= buffer.cursor-byte 0) "left movement should return to previous boundary"))

(fn lazy-text-buffer-deletes_utf8_codepoints []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "utf8-delete.txt"))
  (fs.write-file file "éx")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (buffer:move-caret-to-byte 2)
  (buffer:delete-before-cursor)
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 10}))
  (assert (= (. snapshot.rows 1 :text) "x") "backspace should delete the full multibyte character"))

(fn lazy-text-buffer-exposes-logical-query-helpers []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "logical-queries.txt"))
  (fs.write-file file " \tα\r\nbb\n")
  (local source (source-for-file file {:chunk-bytes 3}))
  (local original-read-range source.read-range)
  (set source.max-requested 0)
  (set source.read-range
       (fn [self offset max-bytes]
         (set self.max-requested (math.max self.max-requested max-bytes))
         (original-read-range self offset max-bytes)))
  (local buffer (LazyTextBuffer {:source source :chunk-bytes 3}))
  (local summary (buffer:get-line-summary 0))
  (assert (= summary.line 0))
  (assert summary.known?)
  (assert (= summary.start-byte 0))
  (assert (= summary.line-end-byte 4))
  (assert summary.line-end-known?)
  (assert (= summary.newline-bytes 2))
  (assert (= summary.codepoint-count 3))
  (assert (= summary.first-nonblank-column 2))
  (assert (= (buffer:get-line-count) 3))
  (local (line column known?) (buffer:line-column-for-byte 7))
  (assert known?)
  (assert (= line 1))
  (assert (= column 1))
  (assert (= (buffer:byte-for-codepoint-position -4) 0))
  (assert (= (buffer:byte-for-codepoint-position 2) 2))
  (assert (= (buffer:byte-for-codepoint-position 3) 4))
  (assert (= (buffer:byte-for-codepoint-position 99) buffer.size))
  (assert (<= source.max-requested 4096) (.. "logical queries should read bounded chunks; max=" source.max-requested)))

(fn lazy-text-buffer-logical-queries-consume-split-crlf-once []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "split-crlf-logical.txt"))
  (local prefix (string.rep "a" 4095))
  (fs.write-file file (.. prefix "\r\nb"))
  (local buffer (buffer-for-file file {:chunk-bytes 4096}))
  (assert (= (buffer:get-line-count) 2) "split CRLF at logical scan chunk boundary should count as one separator")
  (local summary (buffer:get-line-summary 1))
  (assert (= summary.line 1))
  (assert (= summary.start-byte 4097) "line summary scan should resume after both CR and LF")
  (assert (= summary.line-end-byte 4098))
  (assert (= summary.codepoint-count 1)))

(fn lazy-text-buffer-logical-query-required-args-error []
  (local root (make-clean-temp-dir))
  (local file (fs.join-path root "logical-query-required-args.txt"))
  (fs.write-file file "abc")
  (local buffer (buffer-for-file file {:chunk-bytes 4}))
  (assert-error-contains
    "LazyTextBuffer line-column-for-byte requires numeric byte"
    (fn [target-buffer] (target-buffer:line-column-for-byte nil))
    buffer)
  (assert-error-contains
    "LazyTextBuffer byte-for-codepoint-position requires numeric position"
    (fn [target-buffer] (target-buffer:byte-for-codepoint-position nil))
    buffer))

(table.insert tests {:name "lazy text source reads bounded byte ranges" :fn lazy-text-source-reads-bounded-byte-ranges})
(table.insert tests {:name "lazy text source records baseline token" :fn lazy-text-source-records-baseline-token})
(table.insert tests {:name "lazy text buffer viewport reads only requested rows" :fn lazy-text-buffer-viewport-reads-only-requested-rows})
(table.insert tests {:name "lazy text buffer indexes LF and CRLF across chunks" :fn lazy-text-buffer-indexes-lf-and-crlf-across-chunks})
(table.insert tests {:name "lazy text buffer direct line request handles CRLF split across chunks" :fn lazy-text-buffer-direct-line-request-handles-crlf-split-across-chunks})
(table.insert tests {:name "lazy text buffer adjacent codepoint from anchor stays within line" :fn lazy-text-buffer-adjacent-codepoint-from-anchor-stays-within-line})
(table.insert tests {:name "lazy text buffer line-column from near anchor is bounded" :fn lazy-text-buffer-line-column-from-near-anchor-is-bounded})
(table.insert tests {:name "lazy text buffer next word start streams long line" :fn lazy-text-buffer-next-word-start-streams_long_line})
(table.insert tests {:name "lazy text buffer next word start counts UTF-8 punctuation as one codepoint" :fn lazy-text-buffer-next-word-start-counts_utf8_punctuation_as_codepoint})
(table.insert tests {:name "lazy text buffer next word start completes UTF-8 across chunk boundary" :fn lazy-text-buffer-next-word-start-completes_utf8_across_chunk_boundary})
(table.insert tests {:name "lazy text buffer next word start handles adjacent multibyte punctuation boundaries" :fn lazy-text-buffer-next-word-start-handles_adjacent_multibyte_punctuation_boundaries})
(table.insert tests {:name "lazy text buffer line-column from far line start reports unbounded" :fn lazy-text-buffer-line-column-from-far-line-start-reports-unbounded})
(table.insert tests {:name "lazy text buffer builds viewport row from anchor without prefix materialization" :fn lazy-text-buffer-builds-viewport-row-from-anchor-without-prefix-materialization})
(table.insert tests {:name "lazy text buffer maps UTF-8 columns to byte offsets" :fn lazy-text-buffer-maps-utf8-columns-to-byte-offsets})
(table.insert tests {:name "lazy text buffer clips nonzero UTF-8 columns with relative offsets" :fn lazy-text-buffer-clips-nonzero-utf8-columns-with-relative-offsets})
(table.insert tests {:name "lazy text buffer clips before multibyte boundary" :fn lazy-text-buffer-clips-before-multibyte-boundary})
(table.insert tests {:name "lazy text buffer bounds newline-free viewport source reads" :fn lazy-text-buffer-bounds-newline-free-viewport-source-reads})
(table.insert tests {:name "lazy text buffer line-column move does not materialize long line" :fn lazy-text-buffer-line-column-move-does-not-materialize-long-line})
(table.insert tests {:name "lazy text buffer horizontal viewport does not materialize prefix" :fn lazy-text-buffer-horizontal-viewport-does-not-materialize-prefix})
(table.insert tests {:name "lazy text buffer line-column move resolves lines beyond index budget" :fn lazy-text-buffer-line-column-move-resolves-lines-beyond-index-budget})
(table.insert tests {:name "lazy text buffer bounds missing line discovery in newline-free file" :fn lazy-text-buffer-bounds-missing-line-discovery-in-newline-free-file})
(table.insert tests {:name "lazy text buffer bounds far line discovery with many newlines" :fn lazy-text-buffer-bounds-far-line-discovery-with-many-newlines})
(table.insert tests {:name "lazy text buffer inserts and deletes across piece boundaries" :fn lazy-text-buffer-inserts-and-deletes-across-piece-boundaries})
(table.insert tests {:name "lazy text buffer selection copies across original and added pieces" :fn lazy-text-buffer-selection-copies-across-original-and-added-pieces})
(table.insert tests {:name "lazy text buffer selection copies large original span completely" :fn lazy-text-buffer-selection-copies-large-original-span-completely})
(table.insert tests {:name "lazy text buffer preserves invalid original bytes when untouched" :fn lazy-text-buffer-preserves-invalid-original-bytes-when-untouched})
(table.insert tests {:name "lazy text buffer renders invalid original bytes as replacement" :fn lazy-text-buffer-renders-invalid-original-bytes-as-replacement})
(table.insert tests {:name "lazy text buffer vertical move clamps invalid row column to source end" :fn lazy-text-buffer-vertical-move-clamps-invalid-row-column-to-source-end})
(table.insert tests {:name "lazy text buffer renders invalid lead before ASCII as replacement" :fn lazy-text-buffer-renders-invalid-lead-before-ascii-as-replacement})
(table.insert tests {:name "lazy text buffer renders malformed semantic UTF-8 as replacement" :fn lazy-text-buffer-renders-malformed-semantic-utf8-as-replacement})
(table.insert tests {:name "lazy text buffer renders truncated EOF UTF-8 as replacement" :fn lazy-text-buffer-renders-truncated-eof-utf8-as-replacement})
(table.insert tests {:name "lazy text buffer save streams pieces through atomic replace" :fn lazy-text-buffer-save-streams-pieces-through-atomic-replace})
(table.insert tests {:name "lazy text buffer save reports external modification conflict" :fn lazy-text-buffer-save-reports-external-modification-conflict})
(table.insert tests {:name "lazy text buffer save detects same-size external modification" :fn lazy-text-buffer-save-detects-same-size-external-modification})
(table.insert tests {:name "lazy text buffer rejects invalid UTF-8 inserted text" :fn lazy-text-buffer-rejects-invalid-utf8-inserted-text})
(table.insert tests {:name "lazy text buffer moves caret by UTF-8 boundaries" :fn lazy-text-buffer-moves_caret_by_utf8_boundaries})
(table.insert tests {:name "lazy text buffer deletes UTF-8 codepoints" :fn lazy-text-buffer-deletes_utf8_codepoints})
(table.insert tests {:name "lazy text buffer exposes logical query helpers" :fn lazy-text-buffer-exposes-logical-query-helpers})
(table.insert tests {:name "lazy text buffer logical queries consume split CRLF once" :fn lazy-text-buffer-logical-queries-consume-split-crlf-once})
(table.insert tests {:name "lazy text buffer logical query required args error" :fn lazy-text-buffer-logical-query-required-args-error})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "lazy-text-buffer"
                       :tests tests})))

{:name "lazy-text-buffer"
 :tests tests
 :main main
 :conflict-main conflict-main
 :same-size-conflict-main same-size-conflict-main}
