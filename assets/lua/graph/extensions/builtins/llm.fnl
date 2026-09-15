(local Common (require :graph/extensions/builtins/common))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmModelNode (require :graph/nodes/llm-model))
(local LlmNode (require :graph/nodes/llm))
(local LlmProviderNode (require :graph/nodes/llm-provider))
(local LlmToolCallNode (require :graph/nodes/llm-tool-call))
(local LlmToolNode (require :graph/nodes/llm-tool))
(local LlmToolResultNode (require :graph/nodes/llm-tool-result))
(local LlmToolsNode (require :graph/nodes/llm-tools))

(local schemes
  ["llm" "llm-provider" "llm-model" "llm-tools" "llm-conversations"
   "llm-tool" "llm-conversation" "llm-message" "llm-tool-call" "llm-tool-result"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn install-loaders [options graph ctx]
  (local llm-store (assert options.llm-store "builtin-graph-llm requires :llm-store"))
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-llm [] (LlmNode))
  (fn make-provider [] (LlmProviderNode {}))
  (fn make-model [] (LlmModelNode {}))
  (fn make-tools [] (LlmToolsNode {}))
  (fn make-conversations [] (LlmConversationsNode {:store llm-store}))
  (fn make-tool [name key] (LlmToolNode {:name name :key key}))
  (fn make-conversation [id key]
    (local record (llm-store:get-conversation id))
    (when record
      (LlmConversationNode {:llm-id id :store llm-store :key key})))
  (fn make-message [id key]
    (local record (llm-store:get-item id))
    (when record
      (assert (= record.type "message") "llm-message loader expected record.type == message")
      (LlmMessageNode {:llm-id id :store llm-store :key key})))
  (fn make-tool-call [id key]
    (local record (llm-store:get-item id))
    (when record
      (assert (= record.type "tool-call") "llm-tool-call loader expected record.type == tool-call")
      (LlmToolCallNode {:llm-id id :store llm-store :key key})))
  (fn make-tool-result [id key]
    (local record (llm-store:get-item id))
    (when record
      (assert (= record.type "tool-result") "llm-tool-result loader expected record.type == tool-result")
      (LlmToolResultNode {:llm-id id :store llm-store :key key})))
  (add! (graph:register-key-loader "llm"
      (Common.exact-key-loader "llm" make-llm)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-provider"
      (Common.exact-key-loader "llm-provider" make-provider)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-model"
      (Common.exact-key-loader "llm-model" make-model)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-tools"
      (Common.exact-key-loader "llm-tools" make-tools)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-conversations"
      (Common.exact-key-loader "llm-conversations" make-conversations)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-tool"
      (Common.prefix-loader "llm-tool:" make-tool)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-conversation"
      (Common.prefix-loader "llm-conversation:" make-conversation)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-message"
      (Common.prefix-loader "llm-message:" make-message)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-tool-call"
      (Common.prefix-loader "llm-tool-call:" make-tool-call)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "llm-tool-result"
      (Common.prefix-loader "llm-tool-result:" make-tool-result)
      (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-llm"
      :unit-id "builtin-graph-llm"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
