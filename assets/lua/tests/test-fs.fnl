(local tests [])
(local fs (require :fs))
(local process (require :process))
(local RuntimeBin (require :tests.runtime-bin))

(var temp-counter 0)
(local fs-temp-root (fs.join-path "/tmp/space/tests" "fs-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path fs-temp-root (.. "fs-test-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn list-names [entries]
  (local names [])
  (each [_ entry (ipairs entries)]
    (table.insert names entry.name))
  names)

(fn contains? [items needle]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item needle)
      (set found true)))
  found)

(fn string-contains? [haystack needle]
  (not= nil (string.find (tostring haystack) needle 1 true)))

(fn repeated-text [chunk count]
  (local parts [])
  (for [i 1 count]
    (table.insert parts chunk))
  (table.concat parts))

(fn assert-read-text-window-error [description f]
  (local (ok err) (pcall f))
  (assert (not ok) description)
  (assert (string-contains? err "fs.read_text_window")
          (.. description ": expected fs.read_text_window in " (tostring err))))

(fn assert-read-byte-range-error [description f]
  (local (ok err) (pcall f))
  (assert (not ok) description)
  (assert (string-contains? err "fs.read_byte_range")
          (.. description ": expected fs.read_byte_range in " (tostring err))))

(fn assert-atomic-replace-segment-error [description f file token]
  (local (ok err) (pcall f file token))
  (assert (not ok) description)
  (assert (string-contains? err "fs.atomic_replace_if_current")
          (.. description ": expected fs.atomic_replace_if_current in " (tostring err))))

(fn replace-with-stale-token [file token]
  (fs.atomic-replace-if-current file [{:text "new"}] token))

(fn replace-with-negative-offset [file token]
  (fs.atomic-replace-if-current file [{:source-path file :offset -1 :bytes 1}] token))

(fn replace-with-negative-byte-count [file token]
  (fs.atomic-replace-if-current file [{:source-path file :offset 0 :bytes -1}] token))

(fn replace-with-missing-source-path [file token]
  (fs.atomic-replace-if-current file [{:offset 0 :bytes 1}] token))

(fn replace-with-empty-segment [file token]
  (fs.atomic-replace-if-current file [{}] token))

(fn replace-with-single-segment-table [file token]
  (fs.atomic-replace-if-current file {:text "new"} token))

(fn replace-with-sparse-segment-table [file token]
  (local segments [])
  (tset segments 2 {:text "later"})
  (fs.atomic-replace-if-current file segments token))

(fn space-bin []
  (RuntimeBin.resolve))

(fn child-env []
  {:SPACE_DISABLE_AUDIO "1"
   :SPACE_ASSETS_PATH (os.getenv "SPACE_ASSETS_PATH")
   :FENNEL_PATH (os.getenv "FENNEL_PATH")
   :FENNEL_MACRO_PATH (os.getenv "FENNEL_MACRO_PATH")
   :SPACE_BIN (space-bin)})

(fn fs-write-read-stat []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "note.txt"))
    (fs.write-file file "hello world")
    (assert (= (fs.read-file file) "hello world"))
    (local info (fs.stat file))
    (assert info.exists "file should exist")
    (assert info.is-file "file should be regular")
    (assert (= info.name "note.txt"))
    (assert (= info.size 11))
    (assert (not info.is-dir))
    (assert (= (fs.parent file) root)))))

(fn fs-list-dir-hidden-filter []
  (with-temp-dir (fn [root]
    (local visible (fs.join-path root "visible.txt"))
    (local hidden (fs.join-path root ".secret"))
    (fs.write-file visible "v")
    (fs.write-file hidden "h")
    (local entries (fs.list-dir root false))
    (local names (list-names entries))
    (assert (contains? names "visible.txt") "visible entry missing")
    (assert (not (contains? names ".secret")) "hidden entry should be filtered"))))

(fn fs-copy-rename-remove []
  (with-temp-dir (fn [root]
    (local source (fs.join-path root "source.txt"))
    (fs.write-file source "contents")
    (local copy (fs.join-path root "copy.txt"))
    (fs.copy-file source copy true)
    (assert (= (fs.read-file copy) "contents"))
    (local renamed (fs.join-path root "renamed.txt"))
    (fs.rename copy renamed)
    (assert (not (fs.exists copy)) "copy path should be gone after rename")
    (assert (fs.exists renamed) "renamed file should exist")
    (assert (fs.remove renamed) "remove should report true")
    (assert (not (fs.exists renamed)) "renamed file should be removed"))))

(fn fs-read-text-window-bounded-range []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "window.txt"))
    (fs.write-file file "abcdef")
    (local window (fs.read-text-window file 2 3))
    (assert (= window.path file))
    (assert (= window.offset 2))
    (assert (= window.next-offset 5))
    (assert (= window.size 6))
    (assert (= window.bytes-read 3))
    (assert (not window.eof))
    (assert (= window.text "cde"))
    (assert (= window.truncated-utf8 false)))))

(fn fs-read-text-window-caps-max-bytes []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "large.txt"))
    (fs.write-file file (repeated-text "a" 262145))
    (local window (fs.read-text-window file 0 999999))
    (assert (= window.bytes-read 262144))
    (assert (= (# window.text) 262144))
    (assert (= window.next-offset 262144)))))

(fn fs-read-text-window-sanitizes-display-text []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "binary.txt"))
    (fs.write-file file (.. "a" (string.char 0) "b" (string.char 255) "c"))
    (local window (fs.read-text-window file 0 5))
    (assert (not (string-contains? window.text (string.char 0))) "text should not contain NUL")
    (assert (string-contains? window.text "�") "text should contain replacement character"))))

(fn fs-read-text-window-preserves-trailing-ascii-after-invalid-lead []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "malformed.txt"))
    (fs.write-file file (.. (string.char 0xE2) "("))
    (local window (fs.read-text-window file 0 2))
    (assert (= window.text "�(") "invalid lead should be replaced and trailing ASCII preserved")
    (assert (= window.truncated-utf8 false) "invalid lead plus ASCII should not be marked truncated"))))

(fn fs-read-text-window-rejects-invalid-arguments []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:invalid-argument-main"]
                              :env (child-env)
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "invalid-argument child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn invalid-argument-main []
  (assert-read-text-window-error "empty path should fail"
                                 (fn [] (fs.read-text-window "" 0 1)))
  (assert-read-text-window-error "negative offset should fail"
                                 (fn [] (fs.read-text-window "/tmp/space-fs-window.txt" -1 1)))
  (assert-read-text-window-error "zero max-bytes should fail"
                                  (fn [] (fs.read-text-window "/tmp/space-fs-window.txt" 0 0))))

(fn fs-file-token-reports-regular-file-identity []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "token.txt"))
    (fs.write-file file "abcdef")
    (local token (fs.file-token file))
    (assert (= token.path (fs.absolute file)))
    (assert token.exists)
    (assert token.is-file)
    (assert (= token.size 6))
    (assert token.modified)
    (assert token.permissions))))

(fn fs-file-token-repeated-calls-are-stable-for-unchanged-file []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "stable-token.txt"))
    (fs.write-file file "abcdef")
    (local baseline (fs.file-token file))
    (assert (= (type baseline.modified) :string) "file-token modified should be stable string primitive")
    (assert (= (type baseline.change-id) :string) "file-token change-id should be stable string primitive")
    (for [_ 1 100]
      (local current (fs.file-token file))
      (assert (= current.path baseline.path))
      (assert (= current.exists baseline.exists))
      (assert (= current.is-file baseline.is-file))
      (assert (= current.size baseline.size))
      (assert (= current.permissions baseline.permissions))
      (assert (= current.modified baseline.modified))
      (assert (= current.change-id baseline.change-id))))))

(fn fs-file-token-detects-immediate-same-size-replacement []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "same-size-token.txt"))
    (fs.write-file file "abcdef")
    (local baseline (fs.file-token file))
    (fs.write-file file "uvwxyz")
    (local current (fs.file-token file))
    (assert (not= current.change-id baseline.change-id)
            "same-size replacement should change bounded file token identity"))))

(fn fs-read-byte-range-returns-bounded-raw-bytes []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "range.txt"))
    (fs.write-file file "abcdef")
    (local range (fs.read-byte-range file 2 3))
    (assert (= range.offset 2))
    (assert (= range.next-offset 5))
    (assert (= range.size 6))
    (assert (= range.bytes-read 3))
    (assert (= range.bytes "cde"))
    (assert (not range.eof))
    (fs.write-file file (repeated-text "a" 262145))
    (local capped (fs.read-byte-range file 0 999999))
    (assert (= capped.bytes-read 262144))
    (assert (= (# capped.bytes) 262144))
    (assert (= capped.next-offset 262144)))))

(fn fs-read-byte-range-rejects-invalid-arguments []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:read-byte-range-invalid-argument-main"]
                              :env (child-env)
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "read-byte-range invalid-argument child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn read-byte-range-invalid-argument-main []
  (assert-read-byte-range-error "empty path should fail"
                                (fn [] (fs.read-byte-range "" 0 1)))
  (assert-read-byte-range-error "negative offset should fail"
                                (fn [] (fs.read-byte-range "/tmp/space-fs-range.txt" -1 1)))
  (assert-read-byte-range-error "zero max-bytes should fail"
                                (fn [] (fs.read-byte-range "/tmp/space-fs-range.txt" 0 0))))

(fn fs-atomic-replace-if-current-writes-text-and-source-segments []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "atomic.txt"))
    (fs.write-file file "abcdef")
    (local token (fs.file-token file))
    (local result
      (fs.atomic-replace-if-current
        file
        [{:source-path file :offset 0 :bytes 2}
         {:text "XY"}
         {:source-path file :offset 4 :bytes 2}]
        token))
    (assert result.saved)
    (assert (= result.path (fs.absolute file)))
    (assert (= (fs.read-file file) "abXYef"))
    (assert result.token)
    (assert (= result.token.size 6)))))

(fn fs-atomic-replace-if-current-rejects-stale-token []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:atomic-replace-stale-token-main"]
                              :env (child-env)
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "atomic-replace stale-token child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn atomic-replace-stale-token-main []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "stale.txt"))
    (fs.write-file file "abcdef")
    (local token (fs.file-token file))
    (fs.write-file file "changed")
    (assert-atomic-replace-segment-error "stale token should fail" replace-with-stale-token file token))))

(fn write-raced-file [file]
  (fn []
    (fs.write-file file "raced")))

(fn fs-atomic-replace-if-current-rejects-modification-before-final-replace []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:atomic-replace-raced-final-replace-main"]
                              :env (child-env)
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "atomic-replace raced final replace child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn atomic-replace-raced-final-replace-main []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "raced.txt"))
    (fs.write-file file "abcdef")
    (local token (fs.file-token file))
    (local (ok err)
      (pcall fs.atomic-replace-if-current
             file
             [{:text "replacement"}]
             token
             {:test-before-final-validate (write-raced-file file)}))
    (assert (not ok) "save should reject modification after temp write and before final replace")
    (assert (string-contains? err "fs.atomic_replace_if_current: file changed since token")
            (.. "expected final token conflict error, got " (tostring err)))
    (assert (= (fs.read-file file) "raced")
            "detected stale save must preserve external content and not publish replacement"))))

(fn fs-atomic-replace-if-current-rejects-malformed-segments []
  (local result (process.run {:args [(space-bin) "-m" "tests.test-fs:atomic-replace-invalid-segment-main"]
                              :env (child-env)
                              :timeout 30}))
  (assert (= result.exit-code 0)
          (.. "atomic-replace invalid-segment child should pass; stdout=" (or result.stdout "")
              " stderr=" (or result.stderr ""))))

(fn atomic-replace-invalid-segment-main []
  (with-temp-dir (fn [root]
    (local file (fs.join-path root "invalid-segment.txt"))
    (fs.write-file file "abcdef")
    (local token (fs.file-token file))
    (assert-atomic-replace-segment-error "negative offset should fail" replace-with-negative-offset file token)
    (assert-atomic-replace-segment-error "negative byte count should fail" replace-with-negative-byte-count file token)
    (assert-atomic-replace-segment-error "missing source path should fail" replace-with-missing-source-path file token)
    (assert-atomic-replace-segment-error "segment without text or source path should fail" replace-with-empty-segment file token)
    (assert-atomic-replace-segment-error "single segment table should fail" replace-with-single-segment-table file token)
    (assert (= (fs.read-file file) "abcdef"))
    (assert-atomic-replace-segment-error "sparse segment table should fail" replace-with-sparse-segment-table file token)
    (assert (= (fs.read-file file) "abcdef")))))

(table.insert tests {:name "fs write/read/stat" :fn fs-write-read-stat})
(table.insert tests {:name "fs list_dir filters hidden files" :fn fs-list-dir-hidden-filter})
(table.insert tests {:name "fs copy and rename" :fn fs-copy-rename-remove})
(table.insert tests {:name "fs read-text-window reads bounded range" :fn fs-read-text-window-bounded-range})
(table.insert tests {:name "fs read-text-window caps max bytes" :fn fs-read-text-window-caps-max-bytes})
(table.insert tests {:name "fs read-text-window sanitizes display text" :fn fs-read-text-window-sanitizes-display-text})
(table.insert tests {:name "fs read-text-window preserves trailing ascii after invalid lead" :fn fs-read-text-window-preserves-trailing-ascii-after-invalid-lead})
(table.insert tests {:name "fs read-text-window rejects invalid arguments" :fn fs-read-text-window-rejects-invalid-arguments})
(table.insert tests {:name "fs file-token reports regular file identity" :fn fs-file-token-reports-regular-file-identity})
(table.insert tests {:name "fs file-token repeated calls are stable for unchanged file" :fn fs-file-token-repeated-calls-are-stable-for-unchanged-file})
(table.insert tests {:name "fs file-token detects immediate same-size replacement" :fn fs-file-token-detects-immediate-same-size-replacement})
(table.insert tests {:name "fs read-byte-range returns bounded raw bytes" :fn fs-read-byte-range-returns-bounded-raw-bytes})
(table.insert tests {:name "fs read-byte-range rejects invalid arguments" :fn fs-read-byte-range-rejects-invalid-arguments})
(table.insert tests {:name "fs atomic-replace-if-current writes text and source segments" :fn fs-atomic-replace-if-current-writes-text-and-source-segments})
(table.insert tests {:name "fs atomic-replace-if-current rejects stale token" :fn fs-atomic-replace-if-current-rejects-stale-token})
(table.insert tests {:name "fs atomic-replace-if-current rejects modification before final replace" :fn fs-atomic-replace-if-current-rejects-modification-before-final-replace})
(table.insert tests {:name "fs atomic-replace-if-current rejects malformed segments" :fn fs-atomic-replace-if-current-rejects-malformed-segments})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs"
                       :tests tests})))

{:name "fs"
  :tests tests
  :main main
  :invalid-argument-main invalid-argument-main
  :read-byte-range-invalid-argument-main read-byte-range-invalid-argument-main
  :atomic-replace-stale-token-main atomic-replace-stale-token-main
  :atomic-replace-raced-final-replace-main atomic-replace-raced-final-replace-main
  :atomic-replace-invalid-segment-main atomic-replace-invalid-segment-main}
