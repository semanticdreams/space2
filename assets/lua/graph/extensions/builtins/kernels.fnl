(local Common (require :graph/extensions/builtins/common))
(local KernelsNodeModule (require :graph/nodes/kernels))
(local {:KernelNode KernelNode} (require :graph/nodes/kernel))
(local {:KernelInstanceNode KernelInstanceNode} (require :graph/nodes/kernel-instance))

(local schemes ["kernels" "kernel" "kernel-instance"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn install-loaders [options graph ctx]
  (local kernels (assert options.kernels "builtin-graph-kernels requires :kernels"))
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-kernels [] (KernelsNodeModule {:kernels kernels}))
  (fn make-kernel [id _key]
    (local kernel (kernels:get-kernel id))
    (when kernel
      (KernelNode {:kernel-id kernel.id :kernels kernels})))
  (fn make-kernel-instance [id _key]
    (local instance (kernels:get-instance id))
    (when instance
      (KernelInstanceNode {:instance-id instance.id :kernels kernels})))
  (add! (graph:register-key-loader "kernels"
      (Common.exact-key-loader "kernels" make-kernels)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "kernel"
      (Common.prefix-loader "kernel:" make-kernel)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "kernel-instance"
      (Common.prefix-loader "kernel-instance:" make-kernel-instance)
      (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-kernels"
      :unit-id "builtin-graph-kernels"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
