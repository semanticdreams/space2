(fn capability-name [name]
  (tostring name))

(fn require-capability [host name]
  (local service (and host (. host name)))
  (if service
      service
      (error (.. "[app-host] missing required capability: " (capability-name name)))))

{:require require-capability}
