(local tests [])
(local Remote (require :repo/remote))

(fn parse-github-ssh []
  (local parsed (Remote.parse "git@github.com:semanticdreams/spacecore.git"))
  (assert (= parsed.host :github))
  (assert (= parsed.owner "semanticdreams"))
  (assert (= parsed.name "spacecore"))
  (assert (= parsed.repo-id "github.com-semanticdreams-spacecore"))
  (assert (= parsed.remote-url "git@github.com:semanticdreams/spacecore.git")))

(fn parse-github-https []
  (local parsed (Remote.parse "https://github.com/user/repo.git"))
  (assert (= parsed.host :github))
  (assert (= parsed.owner "user"))
  (assert (= parsed.name "repo"))
  (assert (= parsed.repo-id "github.com-user-repo")))

(fn parse-github-https-no-ext []
  (local parsed (Remote.parse "https://github.com/user/repo"))
  (assert (= parsed.host :github))
  (assert (= parsed.owner "user"))
  (assert (= parsed.name "repo"))
  (assert (= parsed.repo-id "github.com-user-repo")))

(fn parse-gitlab-nested []
  (local parsed (Remote.parse "git@gitlab.com:group/subgroup/repo.git"))
  (assert (= parsed.host :gitlab))
  (assert (= parsed.owner "group/subgroup"))
  (assert (= parsed.name "repo"))
  (assert (= parsed.repo-id "gitlab.com-group.subgroup-repo")))

(fn parse-gitlab-flat []
  (local parsed (Remote.parse "git@gitlab.com:namespace/project.git"))
  (assert (= parsed.host :gitlab))
  (assert (= parsed.owner "namespace"))
  (assert (= parsed.name "project")))

(fn parse-unknown-host []
  (local parsed (Remote.parse "git@codeberg.org:someone/project.git"))
  (assert (= parsed.host :unknown))
  (assert (= parsed.owner "someone"))
  (assert (= parsed.name "project"))
  (assert (= parsed.repo-id "codeberg.org-someone-project")))

(fn parse-ssh-url []
  (local parsed (Remote.parse "ssh://git@gitlab.com/user/repo.git"))
  (assert (= parsed.host :gitlab))
  (assert (= parsed.owner "user"))
  (assert (= parsed.name "repo")))

(fn parse-strips-www []
  (local parsed (Remote.parse "https://www.github.com/owner/repo.git"))
  (assert (= parsed.host :github))
  (assert (= parsed.owner "owner"))
  (assert (= parsed.name "repo"))
  (assert (= parsed.repo-id "github.com-owner-repo")))

(fn derive-repo-id []
  (local id (Remote.derive-repo-id "git@github.com:a/b.git"))
  (assert (= id "github.com-a-b")))

(fn detect-host-github []
  (assert (= (Remote.detect-host "git@github.com:x/y.git") :github)))

(fn detect-host-unknown []
  (assert (= (Remote.detect-host "git@bitbucket.org:x/y.git") :unknown)))

(fn parse-rejects-empty []
  (local (ok _err) (pcall Remote.parse ""))
  (assert (not ok) "should reject empty URL"))

(fn parse-rejects-nil []
  (local (ok _err) (pcall Remote.parse nil))
  (assert (not ok) "should reject nil URL"))

(fn parse-rejects-bad-url []
  (local (ok _err) (pcall Remote.parse "not-a-url"))
  (assert (not ok) "should reject unparseable URL"))

(fn parse-spoof-host-github-rejected []
  (local parsed (Remote.parse "git@github.com.evil:user/repo.git"))
  (assert (= parsed.host :unknown) "spoofed github host should be :unknown"))

(fn parse-spoof-host-gitlab-rejected []
  (local parsed (Remote.parse "https://gitlab.com.evil/user/repo.git"))
  (assert (= parsed.host :unknown) "spoofed gitlab host should be :unknown"))

(fn rejects-https-userinfo-token-at []
  (local (ok _err) (pcall Remote.parse "https://token@github.com/owner/repo.git"))
  (assert (not ok) "should reject HTTPS URL with token@"))

(fn rejects-https-userinfo-user-password []
  (local (ok _err) (pcall Remote.parse "https://user:password@github.com/owner/repo.git"))
  (assert (not ok) "should reject HTTPS URL with user:password@"))

(fn rejects-query-string []
  (local (ok _err) (pcall Remote.parse "https://github.com/owner/repo.git?token=secret"))
  (assert (not ok) "should reject URL with query string"))

(fn rejects-fragment []
  (local (ok _err) (pcall Remote.parse "https://github.com/owner/repo.git#fragment"))
  (assert (not ok) "should reject URL with fragment"))

(fn rejects-https-userinfo-unknown-host []
  (local (ok _err) (pcall Remote.parse "https://token@codeberg.org/owner/repo.git"))
  (assert (not ok) "should reject HTTPS URL with token@ on unknown host"))

(fn rejects-scp-ssh-extra-at []
  (local (ok _err) (pcall Remote.parse "git@token@github.com:owner/repo.git"))
  (assert (not ok) "should reject SCP-style SSH with extra @"))

(fn rejects-ssh-url-extra-at []
  (local (ok _err) (pcall Remote.parse "ssh://git@token@gitlab.com/owner/repo"))
  (assert (not ok) "should reject ssh:// URL with extra @"))

(table.insert tests {:name "parse github ssh url" :fn parse-github-ssh})
(table.insert tests {:name "parse github https url" :fn parse-github-https})
(table.insert tests {:name "parse github https no .git" :fn parse-github-https-no-ext})
(table.insert tests {:name "parse gitlab nested group" :fn parse-gitlab-nested})
(table.insert tests {:name "parse gitlab flat namespace" :fn parse-gitlab-flat})
(table.insert tests {:name "parse unknown host url" :fn parse-unknown-host})
(table.insert tests {:name "parse ssh:// url" :fn parse-ssh-url})
(table.insert tests {:name "parse strips www prefix" :fn parse-strips-www})
(table.insert tests {:name "derive repo id" :fn derive-repo-id})
(table.insert tests {:name "detect github host" :fn detect-host-github})
(table.insert tests {:name "detect unknown host" :fn detect-host-unknown})
(table.insert tests {:name "rejects empty url" :fn parse-rejects-empty})
(table.insert tests {:name "rejects nil url" :fn parse-rejects-nil})
(table.insert tests {:name "rejects bad url" :fn parse-rejects-bad-url})
(table.insert tests {:name "spoofed github host is unknown" :fn parse-spoof-host-github-rejected})
(table.insert tests {:name "spoofed gitlab host is unknown" :fn parse-spoof-host-gitlab-rejected})
(table.insert tests {:name "rejects HTTPS token@ userinfo" :fn rejects-https-userinfo-token-at})
(table.insert tests {:name "rejects HTTPS user:password@ userinfo" :fn rejects-https-userinfo-user-password})
(table.insert tests {:name "rejects query string" :fn rejects-query-string})
(table.insert tests {:name "rejects fragment" :fn rejects-fragment})
(table.insert tests {:name "rejects HTTPS userinfo on unknown host" :fn rejects-https-userinfo-unknown-host})
(table.insert tests {:name "rejects SCP-style SSH with extra @" :fn rejects-scp-ssh-extra-at})
(table.insert tests {:name "rejects ssh:// URL with extra @" :fn rejects-ssh-url-extra-at})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "repo-remote"
                       :tests tests})))

{:name "repo-remote"
 :tests tests
 :main main}
