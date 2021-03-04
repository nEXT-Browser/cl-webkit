;;; webkit2.uri-scheme-request.lisp --- bindings for WebKitURISchemeRequest

;; This file is part of cl-webkit.
;;
;; cl-webkit is free software; you can redistribute it and/or modify
;; it under the terms of the MIT license.
;; See `COPYING' in the source distribution for details.

;;; Code:

(in-package #:webkit2)

(defctype webkit-uri-scheme-request :pointer)

(defcfun "webkit_uri_scheme_request_get_scheme" :string
  (request webkit-uri-scheme-request))
(export 'webkit-uri-scheme-request-get-scheme)

(defcfun "webkit_uri_scheme_request_get_uri" :string
  (request webkit-uri-scheme-request))
(export 'webkit-uri-scheme-request-get-uri)

(defcfun "webkit_uri_scheme_request_get_path" :string
  (request webkit-uri-scheme-request))
(export 'webkit-uri-scheme-request-get-path)

(defcfun "webkit_uri_scheme_request_get_web-view" (g-object webkit-web-view)
  (request webkit-uri-scheme-request))
(export 'webkit-uri-scheme-request-get-web-view)

(defcfun "webkit_uri_scheme_request_finish" :void
  (request webkit-uri-scheme-request)
  (stream :pointer)  ; XXX: GInputStream
  (stream-length :int)
  (contents :string))
(export 'webkit-uri-scheme-request-finish)

(defcfun ("webkit_uri_scheme_request_finish_error" %webkit-uri-scheme-request-finish-error) :void
  (request webkit-uri-scheme-request)
  (g-error :pointer))

(defun webkit-uri-scheme-request-finish-error (request error-string)
  (%webkit-uri-scheme-request-finish-error
   request (glib::%g-error-new-literal
            +webkit-plugin-error+
            :webkit-plugin-error-connection-cancelled
            error-string)))
(export 'webkit-uri-scheme-request-finish-error)

(cffi:defcallback uri-scheme-processed :void ((request :pointer) (user-data :pointer))
  (let ((callback (find (cffi:pointer-address user-data) callbacks :key (function callback-id))))
    (flet ((g-memory-input-stream-new-from-data (data-string)
             (let* ((ffi-string (cffi:foreign-string-alloc data-string))
                    ;; TODO: Can we rely on lisp's `length' here?
                    ;; Will it give the same result as strlen on ffi-string?
                    (ffi-string-length (length data-string))
                    (stream (cffi:foreign-funcall "g_memory_input_stream_new_from_data"
                                                  :string ffi-string
                                                  :unsigned-int ffi-string-length
                                                  ;; TODO: This should ideally be g_free()
                                                  ;; to free the ffi-string automatically.
                                                  :pointer (cffi:null-pointer))))
               ;; ffi-string is returned because we need to free it afterwards
               (values stream ffi-string ffi-string-length))))
      (handler-case
          (progn
            (setf callbacks (delete callback callbacks))
            ;; TODO: Use `unwind-protect' to free the allocated objects?
            (when (callback-function callback)
              (multiple-value-bind (data-type data)
                  ;; Callback function should return data type (e.g., "text/html") as a first value
                  ;; and data-string itself as a second value.
                  (funcall (callback-function callback) request)
                (multiple-value-bind (stream ffi-string data-length)
                    (g-memory-input-stream-new-from-data data)
                  (webkit-uri-scheme-request-finish request stream data-length data-type)
                  (g:g-object-unref stream)
                  ;; That's why g-memory-input-stream-new-from-data returns the string
                  (cffi:foreign-string-free ffi-string)))))
        (error (c)
          (webkit-uri-scheme-request-finish-error
           request (format nil "The custom url request for URI ~a failed"
                           (webkit-uri-scheme-request-ger-uri request)))
          (when callback
            (when (callback-error-function callback)
              (funcall (callback-error-function callback) c))
            (setf callbacks (delete callback callbacks))))))))

(defun webkit-web-context-register-uri-scheme-callback (context scheme &optional call-back error-call-back)
  (incf callback-counter)
  (push (make-callback :id callback-counter :object context
                       :function call-back
                       :error-function error-call-back)
        callbacks)
  (webkit-web-context-register-uri-scheme
   context scheme
   (cffi:callback uri-scheme-processed)
   (cffi:make-pointer callback-counter)
   (cffi:null-pointer)))
(export 'webkit-web-context-register-uri-scheme-callback)
