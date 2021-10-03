(cl:in-package :alien-works.host)


(defvar *init-hooks* nil)
(a:define-constant +buffer-size+ 4096)

(declaim (special *event*))


(defun sdl-error ()
  (cffi:foreign-string-to-lisp (%sdl:get-error)))

(cffi:defcfun ("SDL_GetModState" sdl-get-mod-state) :unsigned-int)

(u:define-enumval-extractor scancode %sdl:scancode)
(u:define-enumbit-combiner key-modifier %sdl:keymod)


(defun %host:get-clipboard-foreign-text ()
  (%sdl:get-clipboard-text))


(defun %host:set-clipboard-foreign-text (foreign-string)
  (%sdl:set-clipboard-text foreign-string))

;;;
;;; DISPLAY
;;;
(defstruct (display
            (:constructor %make-display))
  name
  x
  y
  width
  height
  orientation)


(defun make-display (id)
  (cref:c-with ((rect %sdl:rect))
    (let (x y w h)
      (%sdl:get-display-bounds id (rect &))
      (setf w (rect :w)
            h (rect :h)
            x (rect :x)
            y (rect :y))
      (%make-display
       :name (cffi:foreign-string-to-lisp (%sdl:get-display-name id))
       :width w
       :height h
       :x x
       :y y
       :orientation (%sdl:get-display-orientation id)))))


(defun list-displays ()
  (loop for i from (%sdl:get-num-video-displays)
        collect (make-display i)))

;;;
;;; WINDOW
;;;
(declaim (special *primary* *secondary*))

(u:define-enumval-extractor gl-attr %sdl:g-lattr)
(u:define-enumval-extractor gl-profile %sdl:g-lprofile)
(u:define-enumbit-combiner gl-context-flags %sdl:g-lcontext-flag)
(u:define-enumbit-combiner window-flags %sdl:window-flags)


(defun setup-opengl-version (major minor)
  (%sdl:gl-set-attribute (gl-attr :context-major-version) major)
  (%sdl:gl-set-attribute (gl-attr :context-minor-version) minor)
  (let ((win (%sdl:create-window "SETUP"
                                 %sdl:+windowpos-undefined+
                                 %sdl:+windowpos-undefined+
                                 1 1
                                 (window-flags :opengl :hidden))))
    (unless (cffi:null-pointer-p win)
      (let ((ctx (%sdl:gl-create-context win)))
        (unwind-protect
             (unless (cffi:null-pointer-p ctx)
               (prog1 t
                 (%sdl:gl-delete-context ctx)))
          (%sdl:destroy-window win))))))


(defun setup-most-recent-opengl-context ()
  (loop for (major minor) in '((4 6) (4 5) (4 3) (4 1))
          thereis (setup-opengl-version major minor)
        finally (error "Required OpenGL version is not available (4.1+)")))


(defun call-with-window (callback)
  (%sdl:set-main-ready)
  (unless (zerop (%sdl:init (logior %sdl:+init-timer+
                                    %sdl:+init-video+
                                    %sdl:+init-gamecontroller+
                                    %sdl:+init-haptic+)))
    (error "Failed to initialize SDL"))
  (%init-host)
  (%sdl:gl-set-attribute (gl-attr :share-with-current-context) 1)
  (%sdl:gl-set-attribute (gl-attr :context-profile-mask)
                         (gl-profile :core))

  (setup-most-recent-opengl-context)

  (let ((window (cffi:with-foreign-string (name "ALIEN-WORKS")
                  (%sdl:create-window name
                                      %sdl:+windowpos-undefined+
                                      %sdl:+windowpos-undefined+
                                      1280 960
                                      (window-flags :opengl :allow-highdpi :shown)))))
    (when (cffi:null-pointer-p window)
      (error "Failed to create a window"))
    (let ((main-ctx (%sdl:gl-create-context window))
          (primary-ctx (%sdl:gl-create-context window))
          (secondary-ctx (%sdl:gl-create-context window)))
      (unless (= (%sdl:gl-make-current window main-ctx) 0)
        (error "Failed to make main GL context current"))
      (unwind-protect
           (cref:c-with ((event %sdl:event))
             (let ((*event* (event &))
                   (*primary* primary-ctx)
                   (*secondary* secondary-ctx))
               (funcall callback window (%native-gl-context *primary*))))
        (%sdl:gl-delete-context secondary-ctx)
        (%sdl:gl-delete-context primary-ctx)
        (%sdl:gl-delete-context main-ctx)
        (%sdl:destroy-window window)
        (%sdl:quit)))))


(defmacro with-window ((window &key (context (gensym))) &body body)
  `(call-with-window (lambda (,window ,context)
                       (declare (ignorable ,context))
                       ,@body)))


(defun make-shared-context-thread (window action)
  (let ((ctx *secondary*))
    (bt:make-thread
     (lambda ()
       (%sdl:gl-make-current window ctx)
       (funcall action))
     :name "shared-context-thread")))


(defun window-surface (window)
  (cref:c-with ((wm-info %sdl:sys-w-minfo))
    (setf (wm-info :version :major) %sdl:+major-version+
          (wm-info :version :minor) %sdl:+minor-version+
          (wm-info :version :patch) %sdl:+patchlevel+)

    (%sdl:get-window-wm-info window (wm-info &))
    (%window-surface (wm-info &))))


(defun window-width (window)
  (cref:c-with ((width :int))
    (%sdl:get-window-size window (width &) (cffi:null-pointer))
    width))


(defun window-height (window)
  (cref:c-with ((height :int))
    (%sdl:get-window-size window (cffi:null-pointer) (height &))
    height))


(defun framebuffer-width (window)
  (cref:c-with ((width :int))
    (%sdl:gl-get-drawable-size window (width &) (cffi:null-pointer))
    width))


(defun framebuffer-height (window)
  (cref:c-with ((height :int))
    (%sdl:gl-get-drawable-size window (cffi:null-pointer) (height &))
    height))


(defun window-display (window)
  (make-display (%sdl:get-window-display-index window)))


;;;
;;; EVENTS
;;;
(defun handle-events (handler)
  (loop for result = (%sdl:poll-event *event*)
        while (> result 0)
        do (funcall handler *event*)))


(defun event-type (event)
  (let* ((id (cref:c-ref event %sdl:event :type))
         (type (cffi:foreign-enum-keyword '%sdl:event-type id :errorp nil)))
    (if type type :uknown)))


(defstruct mouse-state
  (x 0 :type fixnum)
  (y 0 :type fixnum)
  (buttons 0 :type fixnum))


(defun mouse-state (&optional mouse-state)
  (let ((mouse-state (if mouse-state mouse-state (make-mouse-state))))
    (cref:c-with ((x :int)
                  (y :int))
      (setf (mouse-state-buttons mouse-state) (%sdl:get-mouse-state (x &) (y &))
            (mouse-state-x mouse-state) x
            (mouse-state-y mouse-state) y))
    mouse-state))


(defun mouse-state-left-button-pressed-p (state)
  (/= (logand (mouse-state-buttons state) %sdl:+button-lmask+) 0))


(defun mouse-state-right-button-pressed-p (state)
  (/= (logand (mouse-state-buttons state) %sdl:+button-rmask+) 0))


(defun mouse-state-middle-button-pressed-p (state)
  (/= (logand (mouse-state-buttons state) %sdl:+button-mmask+) 0))


(defun %host:event-input-foreign-text (event)
  (cref:c-ref event %sdl:event :text :text &))


(defun event-mouse-button (event)
  (case (cref:c-ref event %sdl:event :button :button)
    (#.%sdl:+button-left+ :left)
    (#.%sdl:+button-right+ :right)
    (#.%sdl:+button-middle+ :middle)
    (otherwise nil)))


(defun event-mouse-wheel (event)
  (cref:c-val ((event %sdl:event))
    (values (event :wheel :y) (event :wheel :x))))


(defun event-key-scan-code (event)
  (cref:c-ref event %sdl:event :key :keysym :scancode))


(defstruct keyboard-modifier-state
  (buttons 0 :type fixnum))


(defun keyboard-modifier-state (&optional keyboard-modifier-key-state)
  (let ((state (or keyboard-modifier-key-state (make-keyboard-modifier-state))))
    (setf (keyboard-modifier-state-buttons state) (sdl-get-mod-state))
    state))


(defun keyboard-modifier-state-pressed-p (state &rest modifiers)
  (/= 0 (logand (keyboard-modifier-state-buttons state)
                (apply #'key-modifier modifiers))))


(define-compiler-macro keyboard-modifier-state-some-pressed-p (state &rest modifiers)
  `(/= 0 (logand (keyboard-modifier-state-buttons ,state)
                 (key-modifier ,@modifiers))))


;;;
;;; RUNNING
;;;
(defun provided-workdir ()
  (let ((workdir (uiop:getenv "ALIEN_WORKS_WORKDIR")))
    (unless (a:emptyp workdir)
      (uiop:ensure-directory-pathname workdir))))


(defun working-directory ()
  (or (provided-workdir) (uiop:getcwd)))


(defun add-known-foreign-library-directories ()
  (loop with workdir = (provided-workdir)
        with libpaths = (mapcar #'uiop:ensure-directory-pathname
                                (remove-if #'a:emptyp
                                           (uiop:split-string (uiop:getenv "ALIEN_WORKS_LIBRARY_PATH")
                                                              :separator ":")))
        for libdir in (nconc
                       (when workdir
                         (list (merge-pathnames "lib/" workdir)
                               (merge-pathnames "usr/lib/" workdir)
                               workdir))
                       (nreverse libpaths))
        do (pushnew libdir cffi:*foreign-library-directories* :test #'equal)))


(defun run ()
  (add-known-foreign-library-directories)
  (loop with args = (uiop:command-line-arguments)
        for hook in *init-hooks*
        do (apply hook args)))


(defmacro definit (name (&rest lambda-list) &body body)
  (let ((initializer (a:symbolicate 'alien-works-init$ name)))
    `(progn
       (pushnew ',initializer *init-hooks*)
       (defun ,initializer ,@(if lambda-list
                                 `(,lambda-list)
                                 (a:with-gensyms (args-param)
                                   `((&rest ,args-param)
                                     (declare (ignore ,args-param)))))
         ,@body))))



;;;
;;;
;;;
(defun memcpy (destination source size)
  (%sdl:memcpy destination source size))


(defun memset (destination value size)
  (%sdl:memset destination value size))


;;;
;;; STREAMS
;;;
(defclass host-stream ()
  ((buffer :initform (sv:make-static-vector +buffer-size+ :element-type '(unsigned-byte 8))
           :reader %buffer-of)
   (handle :initarg :handle
           :reader %handle-of)
   (location :initarg :location)
   (size :initarg :size)))


(defun open-host-stream-from-location (location direction &optional size)
  (cond
    ((or (stringp location) (pathnamep location))
     (%sdl:rw-from-file (uiop:native-namestring location)
                        (ecase direction
                          (:input "rb")
                          (:output "wb")
                          (:append "ab"))))
    ((cffi:pointerp location)
     (ecase direction
       (:input (%sdl:rw-from-const-mem location (truncate (or size 0))))
       ((:output :append) (%sdl:rw-from-mem location (truncate (or size 0))))))))


(defun reopen-host-stream-for-append (stream)
  (with-slots (handle location size) stream
    (%sdl:r-wclose handle)
    (setf handle (open-host-stream-from-location location :append size))))


(defmethod initialize-instance :after ((this host-stream) &key direction location size)
  (with-slots (handle) this
    (setf handle (open-host-stream-from-location location direction size))
    (when (cffi:null-pointer-p handle)
      (signal (make-condition 'file-error :pathname location)))))


(defmethod cl:close ((this host-stream) &key abort &allow-other-keys)
  (declare (ignore abort))
  (with-slots (handle buffer) this
    (when handle
      (%sdl:r-wclose handle)
      (sv:free-static-vector buffer)
      (setf handle nil
            buffer nil))))


(defclass host-input-stream (host-stream gray:fundamental-binary-input-stream) ())


(defmethod gray:stream-clear-input ((this host-input-stream))
  (declare (ignore this)))


(defmethod gray:stream-read-sequence ((this host-input-stream) sequence start end &key)
  (let ((total-size (- end start)))
    (when (< total-size 0)
      (error "End must be equal or greater than start"))
    (loop with bytes-left = total-size
          with bytes-read = 0
          for destination-idx = (+ start bytes-read)
          while (> bytes-left 0)
          do (let* ((step (min bytes-left +buffer-size+))
                    (read (%sdl:r-wread (%handle-of this)
                                        (sv:static-vector-pointer (%buffer-of this))
                                        1 step)))
               (incf bytes-read read)
               (if (< read step)
                   (setf bytes-left 0)
                   (decf bytes-left read))
               (unless (zerop read)
                 (replace sequence (%buffer-of this)
                          :start1 destination-idx :end1 (+ destination-idx read)
                          :start2 0 :end2 read)))
          finally (return bytes-read))))


(defmethod gray:stream-file-position ((this host-input-stream))
  (%sdl:r-wseek (%handle-of this) 0 %sdl:+rw-seek-cur+))


(defmethod (setf gray:stream-file-position) (value (this host-input-stream))
  (%sdl:r-wseek (%handle-of this) (truncate value) %sdl:+rw-seek-cur+))


(defmethod gray:stream-read-byte ((this host-input-stream))
  (let ((bytes-read (%sdl:r-wread (%handle-of this) (sv:static-vector-pointer (%buffer-of this)) 1 1)))
    (if (zerop bytes-read)
        :EOF
        (aref (%buffer-of this) 0))))


(defclass host-output-stream (host-stream gray:fundamental-binary-output-stream) ())


(defmethod gray:stream-write-byte ((this host-output-stream) byte)
  (setf (aref (%buffer-of this) 0) byte)
  (%sdl:r-wwrite (%handle-of this) (sv:static-vector-pointer (%buffer-of this)) 1 1)
  byte)


(defmethod gray:stream-write-sequence ((this host-output-stream) sequence start end &key)
  (let ((total-size (- end start)))
    (when (< total-size 0)
      (error "End must be equal or greater than start"))
    (loop with bytes-left = total-size
          with bytes-written = 0
          for source-idx = (+ start bytes-written)
          while (> bytes-left 0)
          do (let ((step (min bytes-left +buffer-size+)))
               (replace (%buffer-of this) sequence
                        :start1 0 :end1 step
                        :start2 source-idx :end2 (+ source-idx step))
               (%sdl:r-wwrite (%handle-of this)
                              (sv:static-vector-pointer (%buffer-of this))
                              1 step)
               (incf bytes-written step)
               (decf bytes-left step)))
    sequence))


(defmethod gray:stream-force-output ((this host-output-stream))
  (reopen-host-stream-for-append this))


(defmethod gray:stream-finish-output ((this host-output-stream))
  (reopen-host-stream-for-append this))


(defmethod gray:stream-clear-output ((this host-output-stream))
  (declare (ignore this)))


(defun open-host-file (location &key (direction :input) size)
  (ecase direction
    (:input (make-instance 'host-input-stream :location location :size size :direction :input))
    (:output (make-instance 'host-output-stream :location location :size size :direction :output))))


(defmacro with-open-host-file ((var location &rest keys) &body body)
  `(let ((,var (open-host-file ,location ,@keys)))
     (unwind-protect
          (progn ,@body)
       (close ,var))))


(defun read-host-file-into-static-vector (location &key ((:into provided-static-vector))
                                                     offset ((:size provided-size))
                                                     element-type)
  (when (and element-type
             provided-static-vector
             (not (subtypep element-type (array-element-type provided-static-vector))))
    (error ":INTO array and :ELEMENT-TYPE are not compatible"))
  (let ((element-type (or (and provided-static-vector
                               (array-element-type provided-static-vector))
                          element-type
                          '(unsigned-byte 8))))
    (unless (and (listp element-type)
                 (member (first element-type) '(unsigned-byte signed-byte))
                 (member (second element-type) '(8 16 32 64)))
      (error "Element type of static-vector must be either unsigned-byte or signed-byte of size 8, 16, 32 or 64"))
    (when (and provided-static-vector
               provided-size
               (> provided-size (length provided-static-vector)))
      (error "Provided size is smaller than length of provided static-vector"))
    (let ((file (%sdl:rw-from-file (namestring location) "rb")))
      (when (cffi:null-pointer-p file)
        (error "Failed to open ~A: ~A" location (sdl-error)))
      (unwind-protect
           (let* ((file-size (%sdl:r-wseek file 0 %sdl:+rw-seek-end+))
                  (offset (if (> file-size 0)
                              (mod (or offset 0) file-size)
                              0))
                  (rest-file-size (- file-size offset))
                  (calculated-size
                    (min rest-file-size
                         (or provided-size rest-file-size)
                         (or (and provided-static-vector (length provided-static-vector))
                             rest-file-size))))
             (when (< file-size 0)
               (error "Failed to lookup ~A size: ~A" location (sdl-error)))
             (when (> (+ offset (or provided-size 0)) file-size)
               (error "Sum of offset and provided size is greater than size of the ~A: got ~A, expected no more than ~A"
                      location (+ offset calculated-size) file-size))
             (%sdl:r-wseek file offset %sdl:+rw-seek-set+)
             (let* ((out (if provided-static-vector
                             provided-static-vector
                             (sv:make-static-vector calculated-size
                                                    :element-type element-type)))
                    (objects-read (%sdl:r-wread file (sv:static-vector-pointer out)
                                                calculated-size
                                                1)))
               (unless (= objects-read 1)
                 (unless provided-static-vector
                   (sv:free-static-vector out))
                 (error "Failed to read ~A of size ~A: ~A" location file-size (sdl-error)))
               (values out file-size)))
        (%sdl:r-wclose file)))))
