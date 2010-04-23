(require :asdf)

(defpackage :roslisp-exec
    (:use :cl))

(in-package :roslisp-exec)

(let ((p (sb-ext:posix-getenv "ROS_ROOT")))
  (unless p (error "ROS_ROOT not set"))
  (let ((roslisp-path (merge-pathnames (make-pathname :directory '(:relative "asdf"))
                                       (ros-load:ros-package-path "roslisp"))))
    (handler-case
        (let ((ros-load:*current-ros-package* (second sb-ext:*posix-argv*)))
          (asdf:operate 'asdf:compile-op (third sb-ext:*posix-argv*)))
      (error (e)
        (format *error-output* "Compilation failed due to condition: ~a~&" e)
        (sb-ext:quit :unix-status 1)))

    (with-open-file (strm (fifth sb-ext:*posix-argv*) :if-exists :supersede :direction :output)
      (let ((*standard-output* strm))
        (pprint '(require :asdf))
        (pprint '(defmethod asdf:perform :around ((o asdf:load-op)
                                                  (c asdf:cl-source-file))
                  (handler-case (call-next-method o c)
                    ;; If a fasl was stale, try to recompile and load (once).
                    (sb-ext:invalid-fasl ()
                      (asdf:perform (make-instance 'asdf:compile-op) c)
                      (call-next-method)))))
        (pprint '(push :roslisp-standalone-executable *features*))
        (pprint '(declaim (sb-ext:muffle-conditions sb-ext:compiler-note)))
        (pprint '(load (format nil "~a/.sbclrc-roslisp" (sb-ext:posix-getenv "HOME")) :if-does-not-exist nil))
        (pprint `(push ,roslisp-path asdf:*central-registry*))
        (pprint '(defun roslisp-debugger-hook (condition me)
                  (declare (ignore me))
                  (flet ((failure-quit (&key recklessly-p)
                           (sb-ext:quit :unix-status 1 :recklessly-p recklessly-p)))
                    (handler-case
                        (progn
                          (format *error-output*
                                  "~&Roslisp exiting due to condition: ~a~&" condition)
                          (finish-output *error-output*)
                          (failure-quit))
                      (condition ()
                        (failure-quit :recklessly-p t))))))
        (pprint '(unless (let ((v (sb-ext:posix-getenv "ROSLISP_BACKTRACE_ON_ERRORS"))) (and (stringp v) (> (length v) 0)))
                  (setq sb-ext:*invoke-debugger-hook* #'roslisp-debugger-hook)))

        (pprint `(handler-bind ((style-warning #'muffle-warning)
                                (warning #'print))
                   (asdf:operate 'asdf:load-op :ros-load-manifest :verbose nil)
                   (setf (symbol-value (intern "*CURRENT-ROS-PACKAGE*" :ros-load))
                         ,(second sb-ext:*posix-argv*))                   
                   (let ((*standard-output* (make-broadcast-stream))
                         (sys ,(third sb-ext:*posix-argv*)))
                      (handler-case (asdf:operate 'asdf:load-op sys :verbose nil)
                       (asdf:missing-component (c)
                         (error "Couldn't find asdf system (filename ~a.asd and system name ~a) or some dependency.  Original condition was ~a."
                                 sys sys c))))
                   (load (merge-pathnames (make-pathname :name ,(format nil "~a-init.lisp" (third sb-ext:*posix-argv*))
                                                         :directory '(:relative "roslisp" ,(second sb-ext:*posix-argv*)))
                                          (funcall (symbol-function (intern "ROS-HOME" :ros-load))))
                         :if-does-not-exist nil)
                   (funcall (symbol-function (read-from-string ,(fourth sb-ext:*posix-argv*))))
                   (sb-ext:quit)))))))
(sb-ext:quit)