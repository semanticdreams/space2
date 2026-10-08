(local StringUtils (require :string-utils))

(local fuzzy-match StringUtils.fuzzy-match)

(fn test-fuzzy-match []
  (assert (fuzzy-match "alpha" "alpha") "Exact match failed")
  (assert (fuzzy-match "alp" "alpha") "Prefix match failed")
  (assert (fuzzy-match "pha" "alpha") "Substring match failed")
  (assert (fuzzy-match "AlP" "alpha") "Case insensitive match failed")
  (assert (fuzzy-match "" "alpha") "Empty needle match failed")
  (assert (not (fuzzy-match "beta" "alpha")) "Mismatch passed")
  (assert (not (fuzzy-match "z" "alpha")) "Mismatch passed"))

(fn main []
    (test-fuzzy-match))

{:name "test-string-utils"
 :tests [{:name "fuzzy-match" :fn test-fuzzy-match}]
 :main main}
