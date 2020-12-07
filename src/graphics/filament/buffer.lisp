(cl:in-package :%alien-works.graphics)



;;;
;;; VERTEX BUFFER
;;;
(u:define-enumval-extractor vertex-attribute-enum %filament:filament-vertex-attribute)
(u:define-enumval-extractor vertex-attribute-type-enum %filament:filament-vertex-buffer-attribute-type)

(defun expand-vertex-buffer-builder-function (name args)
  (flet ((%explode-function (signature)
           (explode-function signature args)))
    (ecase name
      (:buffer-count
       (%explode-function
        '(%filament:filament-buffer-count
          '(:pointer %filament::filament-vertex-buffer-builder)
          '%filament:uint8-t)))
      (:vertex-count
       (%explode-function
        '(%filament:filament-vertex-count
          '(:pointer %filament::filament-vertex-buffer-builder)
          '%filament:uint32-t)))
      (:attribute
       (%explode-function
        '(%filament:filament-attribute
          '(:pointer %filament::filament-vertex-buffer-builder)
          '%filament:filament-vertex-attribute
          '%filament:uint8-t
          '%filament:filament-vertex-buffer-attribute-type
          '%filament:uint32-t
          '%filament:uint8-t)))
      (:normalized
       (%explode-function
        '(%filament:filament-normalized
          '(:pointer %filament::filament-vertex-buffer-builder)
          '%filament:filament-vertex-attribute
          ':bool))))))


(defmacro with-vertex-buffer-builder ((name &rest steps) &body body)
  (flet ((ctor-expander ()
           '(%filament:filament-vertex-buffer-builder))
         (build-expander (builder)
           `(%filament:filament-build
             '(:pointer %filament:filament-vertex-buffer-builder) ,builder
             '(:pointer %filament:filament-engine) !::engine)))
    (explode-builder name
                     #'expand-vertex-buffer-builder-function
                     #'ctor-expander
                     #'build-expander
                     '(!::engine)
                     steps
                     body)))


(defun update-vertex-buffer (buffer engine index data size &optional (offset 0))
  (iffi:with-intricate-instance
      (descriptor %filament:filament-backend-buffer-descriptor
                  '(:pointer :void) data
                  '%filament::size-t size
                  '%filament::filament-backend-buffer-descriptor-callback (cffi:null-pointer)
                  '(:pointer :void) (cffi:null-pointer))
    (%filament::filament-set-buffer-at
     '(:pointer %filament::filament-vertex-buffer) buffer
     '(:pointer %filament::filament-engine) engine
     '%filament::uint8-t index
     '(:pointer %filament::filament-vertex-buffer-buffer-descriptor) descriptor
     '%filament::uint32-t offset)))


;;;
;;; INDEX BUFFER
;;;
(u:define-enumval-extractor index-type-enum %filament:filament-index-buffer-index-type)

(defun expand-index-buffer-builder-function (name args)
  (flet ((%explode-function (signature)
           (explode-function signature args)))
    (ecase name
      (:index-count
       (%explode-function
        '(%filament:filament-index-count
          '(:pointer %filament::filament-index-buffer-builder)
          '%filament:uint32-t)))
      (:buffer-type
       (%explode-function
        '(%filament:filament-buffer-type
          '(:pointer %filament::filament-index-buffer-builder)
          '%filament:filament-index-buffer-index-type))))))


(defmacro with-index-buffer-builder ((name &rest steps) &body body)
  (flet ((ctor-expander ()
           '(%filament:filament-index-buffer-builder))
         (build-expander (builder)
           `(%filament:filament-build
             '(:pointer %filament:filament-index-buffer-builder) ,builder
             '(:pointer %filament:filament-engine) !::engine)))
    (explode-builder name
                     #'expand-index-buffer-builder-function
                     #'ctor-expander
                     #'build-expander
                     '(!::engine)
                     steps
                     body)))


(defun update-index-buffer (buffer engine data size &optional (offset 0))
  (iffi:with-intricate-instance
      (descriptor %filament:filament-backend-buffer-descriptor
                  '(:pointer :void) data
                  '%filament::size-t size
                  '%filament::filament-backend-buffer-descriptor-callback (cffi:null-pointer)
                  '(:pointer :void) (cffi:null-pointer))
    (%filament::filament-set-buffer
     '(:pointer %filament::filament-index-buffer) buffer
     '(:pointer %filament::filament-engine) engine
     '(:pointer %filament::filament-index-buffer-buffer-descriptor) descriptor
     '%filament::uint32-t offset)))