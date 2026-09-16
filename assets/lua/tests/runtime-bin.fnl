(local default-fs (require :fs))

(local candidates
  [["build" "space"]
   ["build" "space.exe"]
   ["build" "dist" "windows" "space-cli.exe"]
   ["space"]
   ["space.exe"]
   [".." "build" "space"]
   [".." "build" "space.exe"]])

(fn dependency [opts key default]
  (if (and opts (. opts key))
      (. opts key)
      default))

(fn path-exists? [fs path]
  (and path (not= path "") (fs.exists path)))

(fn candidate-path [fs parts]
  (var path (. parts 1))
  (for [index 2 (length parts)]
    (set path (fs.join-path path (. parts index))))
  path)

(fn executable-safe-path [path]
  (if (and path
           (= nil (string.find path "/" 1 true))
           (= nil (string.find path "\\" 1 true)))
      (.. "./" path)
      path))

(fn resolve [opts]
  (local fs (dependency opts :fs default-fs))
  (local getenv (dependency opts :getenv os.getenv))
  (local explicit-bin (getenv "SPACE_BIN"))
  (if (not= explicit-bin nil)
      (if (path-exists? fs explicit-bin)
          explicit-bin
          (error (.. "SPACE_BIN points to missing space binary: " explicit-bin)))
      (do
        (var resolved nil)
        (each [_ parts (ipairs candidates)]
          (local candidate (candidate-path fs parts))
          (when (and (not resolved) (path-exists? fs candidate))
            (set resolved (executable-safe-path candidate))))
        (if resolved
            resolved
            (error (.. "could not locate space binary from " (fs.cwd)))))))

{:resolve resolve}
