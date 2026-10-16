(local package package)
(local table table)
(local ipairs ipairs)
(local _G _G)

(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
;; Lua-level OpenGL mock for capturing renderer interactions during tests.

(fn new-handle-generator []
  (var next-id 1)
  (fn []
    (local id next-id)
    (set next-id (+ next-id 1))
    id))

(fn record-call [calls name args]
  (table.insert calls {:name name :args args}))

(fn make-shader [state name vertex fragment]
  (local shader {:name name
                 :vertex vertex
                 :fragment fragment
                 :calls []})
  (record-call state.shader-loads "load-shader-from-files"
               {:name name :vertex vertex :fragment fragment
                :shader shader})

  (fn record [method args]
    (record-call shader.calls method args))

  (set shader.use (fn [self] (record "use" {:shader self})))
  (set shader.setMatrix4
       (fn [self uniform value]
         (record "setMatrix4" {:shader self
                               :uniform uniform
                               :value value})))
  (set shader.setVector3f
       (fn [self uniform x y z]
         (record "setVector3f" {:shader self
                                :uniform uniform
                                 :value [x y z]})))
  (set shader.setVector2f
       (fn [self uniform x y]
         (record "setVector2f" {:shader self :uniform uniform :value [x y]})))
  (set shader.setInteger
       (fn [self uniform value]
         (record "setInteger" {:shader self
                               :uniform uniform
                               :value value})))
  (set shader.setFloat
       (fn [self uniform value]
         (record "setFloat" {:shader self
                             :uniform uniform
                             :value value})))
  shader)

(fn install-fxaa-gl! [gl record-gl next-handle]
  (each [constant value (pairs {:GL_RGB 0x1907 :GL_UNSIGNED_BYTE 0x1401
                                :GL_TEXTURE_MIN_FILTER 0x2801 :GL_TEXTURE_MAG_FILTER 0x2800
                                :GL_LINEAR 0x2601 :GL_TEXTURE_WRAP_S 0x2802 :GL_TEXTURE_WRAP_T 0x2803
                                :GL_CLAMP_TO_EDGE 0x812F :GL_DEPTH_COMPONENT 0x1902})]
    (tset gl constant value))
  (set gl.glGenTextures (fn [count]
    (local handle (next-handle))
    (record-gl "glGenTextures" {:count count :handle handle})
    handle))
  (set gl.glDeleteTextures (fn [texture]
    (record-gl "glDeleteTextures" {:texture texture})))
  (set gl.glDeleteRenderbuffers (fn [renderbuffer]
    (record-gl "glDeleteRenderbuffers" {:renderbuffer renderbuffer})))
  (set gl.glTexImage2D (fn [target level internal-format width height border format type]
    (record-gl "glTexImage2D" {:target target :level level :internal-format internal-format
                              :width width :height height :border border :format format :type type})))
  (set gl.glTexParameteri (fn [target pname param]
    (record-gl "glTexParameteri" {:target target :pname pname :param param})))
  (set gl.glFramebufferTexture2D (fn [target attachment textarget texture level]
    (record-gl "glFramebufferTexture2D" {:target target :attachment attachment
                                       :textarget textarget :texture texture :level level})))
  (set gl.checkFramebuffer (fn [] (record-gl "checkFramebuffer" {}))))

(fn MockOpenGL []
  (local state {:gl-calls []
                :shader-loads []
                :clipboard nil
                :read-pixels-bytes nil})
  (local next-handle (new-handle-generator))

  (fn record-gl [name args]
    (record-call state.gl-calls name args))

  (local gl {})
  (install-fxaa-gl! gl record-gl next-handle)
  (each [constant value (pairs
                          {:GL_ARRAY_BUFFER 0x8892
                           :GL_ELEMENT_ARRAY_BUFFER 0x8893
                           :GL_SHADER_STORAGE_BUFFER 0x90D2
                           :GL_FRAMEBUFFER 0x8D40
                           :GL_RENDERBUFFER 0x8D41
                           :GL_STREAM_DRAW 0x88E0
                           :GL_TIME_ELAPSED 0x88BF
                           :GL_QUERY_RESULT 0x8866
                           :GL_QUERY_RESULT_AVAILABLE 0x8867
                           :GL_FLOAT 0x1406
                           :GL_FALSE 0
                           :GL_TRUE 1
                           :GL_UNSIGNED_INT 0x1405
                           :GL_TRIANGLES 0x0004
                           :GL_TRIANGLE_STRIP 0x0005
                           :GL_LINES 0x0001
                           :GL_LINE_STRIP 0x0003
                           :GL_POINTS 0x0000
                           :GL_TEXTURE0 0x84C0
                           :GL_TEXTURE_2D 0x0DE1
                           :GL_TEXTURE_CUBE_MAP 0x8513
                           :GL_STATIC_DRAW 0x88E4
                           :GL_PROGRAM_POINT_SIZE 0x8642
                           :GL_COLOR_ATTACHMENT0 0x8CE0
                           :GL_DEPTH_ATTACHMENT 0x8D00
                           :GL_DEPTH_BUFFER_BIT 0x0100
                           :GL_COLOR_BUFFER_BIT 0x4000
                           :GL_NEAREST 0x2600
                           :GL_BACK 0x0405
                           :GL_READ_FRAMEBUFFER 0x8CA8
                           :GL_DRAW_FRAMEBUFFER 0x8CA9
                           :GL_DEPTH_TEST 0x0B71
                           :GL_CULL_FACE 0x0B44
                           :GL_RGBA8 0x8058})]
    (set (. gl constant) value))

  (set gl.glGenVertexArrays
       (fn [count]
         (local handle (next-handle))
         (record-gl "glGenVertexArrays" {:count count :handle handle})
         handle))

  (set gl.glGenBuffers
       (fn [count]
         (local handle (next-handle))
         (record-gl "glGenBuffers" {:count count :handle handle})
         handle))

  (set gl.glGenQueries
       (fn [count]
         (local handle (next-handle))
         (record-gl "glGenQueries" {:count count :handle handle})
         handle))

  (set gl.glDeleteVertexArrays
       (fn [array]
         (record-gl "glDeleteVertexArrays" {:array array})))

  (set gl.glDeleteBuffers
       (fn [buffer]
         (record-gl "glDeleteBuffers" {:buffer buffer})))

  (set gl.glDeleteQueries
       (fn [count queries]
         (record-gl "glDeleteQueries" {:count count :queries queries})))

  (set gl.glBeginQuery
       (fn [target query]
         (record-gl "glBeginQuery" {:target target :query query})))

  (set gl.glEndQuery
       (fn [target]
         (record-gl "glEndQuery" {:target target})))

  (set gl.glGetQueryObjectuiv
       (fn [query pname]
         (record-gl "glGetQueryObjectuiv" {:query query :pname pname})
         (if (= pname gl.GL_QUERY_RESULT_AVAILABLE)
             1
             0)))

  (set gl.glGetQueryObjectui64v
       (fn [query pname]
         (record-gl "glGetQueryObjectui64v" {:query query :pname pname})
         (if (= pname gl.GL_QUERY_RESULT)
             1000000
             0)))

  (set gl.glBindVertexArray
       (fn [vao]
         (record-gl "glBindVertexArray" {:vao vao})))

  (set gl.glBindBuffer
       (fn [target buffer]
         (record-gl "glBindBuffer" {:target target :buffer buffer})))

  (set gl.glBindBufferBase
       (fn [target index buffer]
         (record-gl "glBindBufferBase" {:target target :index index :buffer buffer})))

  (set gl.glBindFramebuffer
       (fn [target framebuffer]
         (record-gl "glBindFramebuffer" {:target target :framebuffer framebuffer})))

  (set gl.glGenFramebuffers
       (fn [count]
         (local handle (next-handle))
         (record-gl "glGenFramebuffers" {:count count :handle handle})
         handle))

  (set gl.glDeleteFramebuffers
       (fn [framebuffer]
         (record-gl "glDeleteFramebuffers" {:framebuffer framebuffer})))

  (set gl.glGenRenderbuffers
       (fn [count]
         (local handle (next-handle))
         (record-gl "glGenRenderbuffers" {:count count :handle handle})
         handle))

  (set gl.glBindRenderbuffer
       (fn [target buffer]
         (record-gl "glBindRenderbuffer" {:target target :buffer buffer})))

  (set gl.glRenderbufferStorage
       (fn [target format width height]
         (record-gl "glRenderbufferStorage"
                    {:target target :format format :width width :height height})))

  (set gl.glFramebufferRenderbuffer
       (fn [target attachment renderbuffertarget renderbuffer]
         (record-gl "glFramebufferRenderbuffer"
                    {:target target
                     :attachment attachment
                     :renderbuffertarget renderbuffertarget
                     :renderbuffer renderbuffer})))

  (set gl.glEnable
       (fn [flag]
         (record-gl "glEnable" {:flag flag})))

  (set gl.glDisable
       (fn [flag]
         (record-gl "glDisable" {:flag flag})))

  (set gl.glDepthFunc
       (fn [func]
         (record-gl "glDepthFunc" {:func func})))

  (set gl.glClearColor
       (fn [r g b a]
         (record-gl "glClearColor" {:r r :g g :b b :a a})))

  (set gl.glClear
       (fn [mask]
         (record-gl "glClear" {:mask mask})))

  (set gl.glFinish
       (fn []
         (record-gl "glFinish" {})))

  (set gl.glReadBuffer
       (fn [src]
         (record-gl "glReadBuffer" {:src src})))

  (set gl.glReadPixels
       (fn [x y width height format _type]
         (record-gl "glReadPixels" {:x x :y y :width width :height height :format format})
         (or state.read-pixels-bytes (string.rep "\0" (* width height 4)))))

  (set gl.glEnableVertexAttribArray
       (fn [attrib]
         (record-gl "glEnableVertexAttribArray" {:attrib attrib})))

  (set gl.glVertexAttribDivisor
       (fn [attrib divisor]
         (record-gl "glVertexAttribDivisor" {:attrib attrib :divisor divisor})))

  (set gl.glVertexAttribPointer
       (fn [index size type normalized stride offset]
         (record-gl "glVertexAttribPointer"
                    {:index index
                     :size size
                     :type type
                     :normalized normalized
                     :stride stride
                     :offset offset})))

  (set gl.glVertexAttribIPointer
       (fn [index size type stride offset]
         (record-gl "glVertexAttribIPointer"
                    {:index index
                     :size size
                     :type type
                     :stride stride
                     :offset offset})))

  (set gl.bufferDataFromVectorBuffer
       (fn [vector target usage]
         (record-gl "bufferDataFromVectorBuffer"
                    {:target target
                     :usage usage
                     :vector vector
                     :length (and vector (vector:length))})))

  (set gl.bufferSubDataFromVectorBuffer
       (fn [vector target offset-bytes size-bytes]
         (record-gl "bufferSubDataFromVectorBuffer"
                    {:target target
                     :vector vector
                     :offset-bytes offset-bytes
                     :size-bytes size-bytes
                     :length (and vector (vector:length))})))

  (set gl.bufferDataUIntFromVectorBuffer
       (fn [vector target usage]
         (record-gl "bufferDataUIntFromVectorBuffer"
                    {:target target
                     :usage usage
                     :vector vector
                     :length (and vector (vector:length))})))

  (set gl.bufferSubDataUIntFromVectorBuffer
       (fn [vector target offset-elements element-count]
         (record-gl "bufferSubDataUIntFromVectorBuffer"
                    {:target target
                     :vector vector
                     :offset-elements offset-elements
                     :element-count element-count
                     :length (and vector (vector:length))})))

  (set gl.glDrawArrays
       (fn [mode start count]
         (record-gl "glDrawArrays" {:mode mode :start start :count count})))

  (set gl.glMultiDrawArrays
       (fn [mode firsts counts]
         (record-gl "glMultiDrawArrays"
                    {:mode mode
                     :firsts firsts
                     :counts counts
                     :drawcount (math.min (# firsts) (# counts))})))

  (set gl.glDrawArraysInstanced
       (fn [mode start count instancecount]
         (record-gl "glDrawArraysInstanced"
                    {:mode mode
                     :start start
                     :count count
                     :instances instancecount})))

  (set gl.glDrawElementsInstanced
       (fn [mode count type index-offset-bytes instancecount]
         (record-gl "glDrawElementsInstanced"
                    {:mode mode
                     :count count
                     :type type
                     :index-offset-bytes index-offset-bytes
                     :instances instancecount})))

  (set gl.glBlitFramebuffer
       (fn [srcX0 srcY0 srcX1 srcY1 dstX0 dstY0 dstX1 dstY1 mask filter]
         (record-gl "glBlitFramebuffer"
                    {:srcX0 srcX0 :srcY0 srcY0 :srcX1 srcX1 :srcY1 srcY1
                     :dstX0 dstX0 :dstY0 dstY0 :dstX1 dstX1 :dstY1 dstY1
                     :mask mask :filter filter})))

  (set gl.glActiveTexture
       (fn [slot]
         (record-gl "glActiveTexture" {:slot slot})))

  (set gl.glBindTexture
       (fn [target texture]
         (record-gl "glBindTexture" {:target target :texture texture})))

  (set gl.glDepthMask
       (fn [value]
         (record-gl "glDepthMask" {:value value})))

  (set gl.glViewport
       (fn [x y width height]
         (record-gl "glViewport" {:x x :y y :width width :height height})))

  (set gl.glBufferData
       (fn [target data usage]
         (record-gl "glBufferData"
                    {:target target :data data :usage usage})))

  (set gl.glBufferDataUInt
       (fn [target data usage]
         (record-gl "glBufferDataUInt"
                    {:target target :data data :usage usage})))

  (set gl.clipboard-set
       (fn [value]
         (set state.clipboard value)
         true))

  (set gl.clipboard-get
       (fn []
         (or state.clipboard "")))

  (set gl.clipboard-has
       (fn []
         (not (= state.clipboard nil))))

  (local shader-module {})
  (set shader-module.load-shader-from-files
       (fn [name vertex fragment]
         (make-shader state name vertex fragment)))

  (local mock {:gl gl
               :shaders shader-module
               :state state
               :previous-gl nil
               :previous-shaders nil
               :previous-preload nil
               :installed false})

(set mock.install
     (fn [self]
       (when (not self.installed)
          (set self.previous-gl (. package.loaded "gl"))
          (set self.previous-shaders (. package.loaded "shaders"))
          (set self.previous-preload (. package.preload "shaders"))
          (set (. package.loaded "gl") gl)
          (set (. package.loaded "shaders") shader-module)
          (set (. package.preload "shaders") (fn [] shader-module))
          (set self.installed true))))

  (set mock.restore
       (fn [self]
         (when self.installed
          (if self.previous-gl
              (set (. package.loaded "gl") self.previous-gl)
              (set (. package.loaded "gl") nil))
          (if self.previous-shaders
              (set (. package.loaded "shaders") self.previous-shaders)
              (set (. package.loaded "shaders") nil))
          (if self.previous-preload
              (set (. package.preload "shaders") self.previous-preload)
              (set (. package.preload "shaders") nil))
          (set self.installed false))))

  (set mock.reset
       (fn [self]
         (set state.gl-calls [])
         (set state.shader-loads [])))

  (set mock.get-gl-calls
       (fn [self name]
         (local matches [])
         (each [_ entry (ipairs state.gl-calls)]
           (when (or (not name) (= entry.name name))
             (table.insert matches entry)))
         matches))

  (set mock.set-read-pixels
       (fn [_self bytes]
         (set state.read-pixels-bytes bytes)))

  (set mock.get-shader-loads
       (fn [_self]
         state.shader-loads))

  mock)

MockOpenGL
