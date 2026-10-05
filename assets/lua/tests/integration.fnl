(local suite
  {:name "integration"
   :modules
   [:tests.test-zmq
    :tests.test-remote-control
    :tests.test-aubio
    :tests.test-aubio-helpers
    :tests.test-aubio-pipelines
    :tests.test-aubio-stream
    :tests.test-audio-input
    :tests.test-ripgrep
    :tests.test-ripgrep-view
    :tests.test-process
    :tests.test-codex-sdk
    :tests.test-opencode-sdk
    :tests.test-terminal
    :tests.test-terminal-widget
    :tests.test-terminal-renderer
    :tests.test-terminal-scrollback
    :tests.test-jobs
    :tests.test-video
    :tests.test-video-widget
    :tests.test-http-server
    :tests.test-mcp
    :tests.test-mcp-http
    :tests.test-keyring
    :tests.test-wallet
    :tests.test-wallet-manager
    :tests.test-wallet-store
    :tests.test-wallet-recover-dialog
    :tests.test-wallet-view
    :tests.test-wallet-send-dialog
    :tests.test-qr-code
    :tests.test-wallet-rpc
    :tests.test-wallet-core
    :tests.test-drawing-document
    :tests.test-drawing-input
    :tests.test-drawing-render
    :tests.test-drawing-sidebar
    :tests.test-external-editor
    :tests.test-fs
    :tests.test-fs-view
    :tests.test-ssh-integration
    :tests.test-xapian
    :tests.test-xdg-icon-browser
    :tests.test-jpeg-texture-decode
    :tests.test-llm-graph
    :tests.test-llm-store
    :tests.test-llm-chat-view
    :tests.test-llm-conversation-messages-view
    :tests.test-hackernews-story-list-view
    :tests.test-hackernews-story-view
    :tests.test-hackernews-user-view
    :tests.test-hackernews-offline
    :tests.test-hackernews-graph-view-node-views]})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-modules suite)))

{:name "integration"
 :modules suite.modules
 :main main}
