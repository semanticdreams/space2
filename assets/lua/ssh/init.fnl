(local native-loader (. package.preload "ssh"))
(assert (= (type native-loader) :function)
        "native ssh module is not registered")

(native-loader)
