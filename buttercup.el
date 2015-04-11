;;; buttercup.el --- Behavior-Driven Emacs Lisp Testing -*-lexical-binding:t-*-

;; Copyright (C) 2015  Jorgen Schaefer <contact@jorgenschaefer.de>

;; Version: 1.0
;; Author: Jorgen Schaefer <contact@jorgenschaefer.de>

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Buttercup is a behavior-driven development framework for testing
;; Emacs Lisp code. It is heavily inspired by the Jasmine test
;; framework for JavaScript.

;; A test suite begins with a call to the Buttercup macro `describe` with
;; the first parameter describing the suite and the rest being the body
;; of code that implements the suite.

;; (describe "A suite"
;;   (it "contains a spec with an expectation"
;;     (expect t :to-be t)))

;; The ideas for project were shamelessly taken from Jasmine
;; <https://jasmine.github.io>.

;; All the good ideas are theirs. All the problems are mine.

;;; Code:

(require 'cl)
(require 'buttercup-compat)

;;;;;;;;;;
;;; expect

(define-error 'buttercup-failed
  "Buttercup test failed")

(defmacro expect (arg &optional matcher &rest args)
  "Expect a condition to be true.

This macro knows three forms:

\(expect arg :matcher args...)
  Fail the current test iff the matcher does not match these arguments.
  See `buttercup-define-matcher' for more information on matchers.

\(expect (function arg...))
  Fail the current test iff the function call does not return a true value.

\(expect ARG)
  Fail the current test iff ARG is not true."
  (cond
   ((and (not matcher)
         (consp arg))
    `(buttercup-expect ,(cadr arg)
                       #',(car arg)
                       ,@(cddr arg)))
   ((and (not matcher)
         (not (consp arg)))
    `(buttercup-expect ,arg))
   (t
    `(buttercup-expect ,arg ,matcher ,@args))))

(defun buttercup-expect (arg &optional matcher &rest args)
  "The function for the `expect' macro.

See the macro documentation for details."
  (if (not matcher)
      (when (not arg)
        (buttercup-fail "Expected %S to be non-nil" arg))
    (let ((result (buttercup--apply-matcher matcher (cons arg args))))
      (if (consp result)
          (when (not (car result))
            (buttercup-fail "%s" (cdr result)))
        (when (not result)
          (buttercup-fail "Expected %S %S %S"
                          arg
                          matcher
                          (mapconcat (lambda (obj)
                                       (format "%S" obj))
                                     args
                                     " ")))))))

(defun buttercup-fail (format &rest args)
  "Fail the current test with the given description.

This is the mechanism underlying `expect'. You can use it
directly if you want to write your own testing functionality."
  (signal 'buttercup-failed (apply #'format format args)))

(defmacro buttercup-define-matcher (matcher args &rest body)
  "Define a matcher to be used in `expect'.

The BODY should return either a simple boolean, or a cons cell of
the form (RESULT . MESSAGE). If RESULT is nil, MESSAGE should
describe why the matcher failed. If RESULT is non-nil, MESSAGE
should describe why a negated matcher failed."
  (declare (indent defun))
  `(put ,matcher 'buttercup-matcher
        (lambda ,args
          ,@body)))

(defun buttercup--apply-matcher (matcher args)
  "Apply MATCHER to ARGS.

MATCHER is either a matcher defined with
`buttercup-define-matcher', or a function."
  (let ((function (or (get matcher 'buttercup-matcher)
                      matcher)))
    (when (not (functionp function))
      (error "Not a test: %S" matcher))
    (apply function args)))

;;;;;;;;;;;;;;;;;;;;;
;;; Built-in matchers

(buttercup-define-matcher :not (obj matcher &rest args)
  (let ((result (buttercup--apply-matcher matcher (cons obj args))))
    (if (consp result)
        (cons (not (car result))
              (cdr result))
      (not result))))

(buttercup-define-matcher :to-be (a b)
  (if (eq a b)
      (cons t (format "Expected %S not to be `eq' to %S" a b))
    (cons nil (format "Expected %S to be `eq' to %S" a b))))

(buttercup-define-matcher :to-equal (a b)
  (if (equal a b)
      (cons t (format "Expected %S not to `equal' %S" a b))
    (cons nil (format "Expected %S to `equal' %S" a b))))

(buttercup-define-matcher :to-match (text regexp)
  (if (string-match regexp text)
      (cons t (format "Expected %S to match the regexp %S"
                      text regexp))
    (cons nil (format "Expected %S not to match the regexp %S"
                      text regexp))))

(buttercup-define-matcher :to-be-truthy (arg)
  (if arg
      (cons t (format "Expected %S not to be true" arg))
    (cons nil (format "Expected %S to be true" arg))))

(buttercup-define-matcher :to-contain (seq elt)
  (if (member elt seq)
      (cons t (format "Expected %S not to contain %S" seq elt))
    (cons nil (format "Expected %S to contain %S" seq elt))))

(buttercup-define-matcher :to-be-less-than (a b)
  (if (< a b)
      (cons t (format "Expected %S not to be less than %S" a b))
    (cons nil (format "Expected %S to be less than %S" a b))))

(buttercup-define-matcher :to-be-greater-than (a b)
  (if (> a b)
      (cons t (format "Expected %S not to be greater than %S" a b))
    (cons nil (format "Expected %S to be greater than %S" a b))))

(buttercup-define-matcher :to-be-close-to (a b precision)
  (if (< (abs (- a b))
         (/ 1 (expt 10.0 precision)))
      (cons t (format "Expected %S not to be close to %S to %s positions"
                      a b precision))
    (cons nil (format "Expected %S to be greater than %S to %s positions"
                      a b precision))))

(buttercup-define-matcher :to-throw (function &optional signal signal-args)
  (condition-case err
      (progn
        (funcall function)
        (cons nil (format "Expected %S to throw an error" function)))
    (error
     (cond
      ((and signal signal-args)
       (cond
        ((not (memq signal (get (car err) 'error-conditions)))
         (cons nil (format "Expected %S to throw a child signal of %S, not %S"
                           function signal (car err))))
        ((not (equal signal-args (cdr err)))
         (cons nil (format "Expected %S to throw %S with args %S, not %S with %S"
                           function signal signal-args (car err) (cdr err))))
        (t
         (cons t (format (concat "Expected %S not to throw a child signal "
                                 "of %S with args %S, but it did throw %S")
                         function signal signal-args (car err))))))
      (signal
       (if (not (memq signal (get (car err) 'error-conditions)))
           (cons nil (format "Expected %S to throw a child signal of %S, not %S"
                             function signal (car err)))
         (cons t (format (concat "Expected %S not to throw a child signal "
                                 "of %S, but it threw %S")
                         function signal (car err)))))
      (t
       (cons t (format "Expected %S not to throw an error" function)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Suite and spec data structures

(cl-defstruct buttercup-suite
  ;; The name of this specific suite
  description
  ;; Any children of this suite, both suites and specs
  children
  ;; The parent of this suite, another suite
  parent
  ;; Closure to run before and after each spec in this suite and its
  ;; children
  before-each
  after-each
  ;; Likewise, but before and after all specs.
  before-all
  after-all
  ;; These are set if there are errors in after-all.
  ;; One of: passed failed pending
  status
  failure-description
  failure-stack)

(cl-defstruct buttercup-spec
  ;; The description of the it form this was generated from
  description
  ;; The suite this spec is a member of
  parent
  ;; The closure to run for this spec
  function
  ;; One of: passed failed pending
  status
  failure-description
  failure-stack)

(defun buttercup-suite-add-child (parent child)
  "Add a CHILD suite to a PARENT suite."
  (setf (buttercup-suite-children parent)
        (append (buttercup-suite-children parent)
                (list child)))
  (if (buttercup-suite-p child)
      (setf (buttercup-suite-parent child)
            parent)
    (setf (buttercup-spec-parent child)
          parent)))

(defun buttercup-suite-parents (suite)
  "Return a list of parents of SUITE."
  (if (buttercup-suite-parent suite)
      (cons (buttercup-suite-parent suite)
            (buttercup-suite-parents (buttercup-suite-parent suite)))
    nil))

(defun buttercup-spec-parents (spec)
  "Return a list of parents of SPEC."
  (if (buttercup-spec-parent spec)
      (cons (buttercup-spec-parent spec)
            (buttercup-suite-parents (buttercup-spec-parent spec)))
    nil))

(defun buttercup-suites-total-specs-defined (suite-list)
  "Return the number of specs defined in all suites in SUITE-LIST."
  (let ((nspecs 0))
    (dolist (spec-or-suite (buttercup--specs-and-suites suite-list))
      (when (buttercup-spec-p spec-or-suite)
        (setq nspecs (1+ nspecs))))
    nspecs))

(defun buttercup-suites-total-specs-failed (suite-list)
  "Return the number of failed specs in all suites in SUITE-LIST."
  (let ((nspecs 0))
    (dolist (spec-or-suite (buttercup--specs-and-suites suite-list))
      (when (and (buttercup-spec-p spec-or-suite)
                 (eq (buttercup-spec-status spec-or-suite) 'failed))
        (setq nspecs (1+ nspecs))))
    nspecs))

(defun buttercup--specs-and-suites (spec-or-suite-list)
  "Return the number of specs defined in SUITE-OR-SPEC and its children."
  (let ((specs-and-suites nil))
    (dolist (spec-or-suite spec-or-suite-list)
      (setq specs-and-suites (append specs-and-suites
                                     (list spec-or-suite)))
      (when (buttercup-suite-p spec-or-suite)
        (setq specs-and-suites
              (append specs-and-suites
                      (buttercup--specs-and-suites
                       (buttercup-suite-children spec-or-suite))))))
    specs-and-suites))

(defun buttercup-suite-full-name (suite)
  "Return the full name of SUITE, which includes the names of the parents."
  (let ((name-parts (mapcar #'buttercup-suite-description
                            (cons suite (buttercup-suite-parents suite)))))
    (mapconcat #'identity
               (reverse name-parts)
               " ")))

(defun buttercup-spec-full-name (spec)
  "Return the full name of SPEC, which includes the full name of its suite."
  (let ((parent (buttercup-spec-parent spec)))
    (if parent
        (concat (buttercup-suite-full-name parent)
                " "
                (buttercup-spec-description spec))
      (buttercup-spec-description spec))))

;;;;;;;;;;;;;;;;;;;;
;;; Suites: describe

(defvar buttercup-suites nil
  "The list of all currently defined Buttercup suites.")

(defvar buttercup--current-suite nil
  "The suite currently being defined.

Do not set this globally. It is let-bound by the `describe'
form.")

(defmacro describe (description &rest body)
  "Describe a suite of tests."
  (declare (indent 1) (debug (&define sexp def-body)))
  `(buttercup-describe ,description (lambda () ,@body)))

(defun buttercup-describe (description body-function)
  "Function to handle a `describe' form."
  (let* ((enclosing-suite buttercup--current-suite)
         (buttercup--current-suite (make-buttercup-suite
                                    :description description)))
    (funcall body-function)
    (if enclosing-suite
        (buttercup-suite-add-child enclosing-suite
                                   buttercup--current-suite)
      (setq buttercup-suites (append buttercup-suites
                                     (list buttercup--current-suite))))))

;;;;;;;;;;;;;
;;; Specs: it

(defmacro it (description &rest body)
  "Define a spec."
  (declare (indent 1) (debug (&define sexp def-body)))
  `(buttercup-it ,description (lambda () ,@body)))

(defun buttercup-it (description body-function)
  "Function to handle an `it' form."
  (when (not buttercup--current-suite)
    (error "`it' has to be called from within a `describe' form."))
  (buttercup-suite-add-child buttercup--current-suite
                             (make-buttercup-spec
                              :description description
                              :function body-function)))

;;;;;;;;;;;;;;;;;;;;;;
;;; Setup and Teardown

(defmacro before-each (&rest body)
  "Run BODY before each spec in the current suite."
  (declare (indent 0) (debug (&define def-body)))
  `(buttercup-before-each (lambda () ,@body)))

(defun buttercup-before-each (function)
  "The function to handle a `before-each' form."
  (setf (buttercup-suite-before-each buttercup--current-suite)
        (append (buttercup-suite-before-each buttercup--current-suite)
                (list function))))

(defmacro after-each (&rest body)
  "Run BODY after each spec in the current suite."
  (declare (indent 0) (debug (&define def-body)))
  `(buttercup-after-each (lambda () ,@body)))

(defun buttercup-after-each (function)
  "The function to handle an `after-each' form."
  (setf (buttercup-suite-after-each buttercup--current-suite)
        (append (buttercup-suite-after-each buttercup--current-suite)
                (list function))))

(defmacro before-all (&rest body)
  "Run BODY before every spec in the current suite."
  (declare (indent 0) (debug (&define def-body)))
  `(buttercup-before-all (lambda () ,@body)))

(defun buttercup-before-all (function)
  "The function to handle a `before-all' form."
  (setf (buttercup-suite-before-all buttercup--current-suite)
        (append (buttercup-suite-before-all buttercup--current-suite)
                (list function))))

(defmacro after-all (&rest body)
  "Run BODY after every spec in the current suite."
  (declare (indent 0) (debug (&define def-body)))
  `(buttercup-after-all (lambda () ,@body)))

(defun buttercup-after-all (function)
  "The function to handle an `after-all' form."
  (setf (buttercup-suite-after-all buttercup--current-suite)
        (append (buttercup-suite-after-all buttercup--current-suite)
                (list function))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Disabled Suites: xdescribe

(defmacro xdescribe (description &rest body)
  "Like `describe', but mark the suite as disabled.

A disabled suite is not run."
  (declare (indent 1))
  `(buttercup-xdescribe ,description (lambda () ,@body)))

(defun buttercup-xdescribe (description function)
  "Like `buttercup-describe', but mark the suite as disabled.

A disabled suite is not run."
  nil)

;;;;;;;;;;;;;;;;;;;;;;
;;; Pending Specs: xit

(defmacro xit (description &rest body)
  "Like `it', but mark the spec as disabled.

A disabled spec is not run."
  (declare (indent 1))
  `(buttercup-xit ,description (lambda () ,@body)))

(defun buttercup-xit (description function)
  "Like `buttercup-it', but mark the spec as disabled.

A disabled spec is not run."
  nil)

;;;;;;;;;
;;; Spies

(defvar buttercup--spy-contexts (make-hash-table :test 'eq
                                                 :weakness 'key)
  "A mapping of currently-defined spies to their contexts.")

(cl-defstruct spy-context
  args
  return-value
  current-buffer)

(defun spy-on (symbol &optional keyword arg)
  "Create a spy (mock) for the function SYMBOL.

KEYWORD can have one of the following values:

  :and-call-through -- Track calls, but call the original
      function.

  :and-return-value -- Track calls, but return ARG instead of
      calling the original function.

  :and-call-fake -- Track calls, but call ARG instead of the
      original function.

  :and-throw-error -- Signal ARG as an error instead of calling
      the original function.

  nil -- Track calls, but simply return nil instead of calling
      the original function."
  (cond
   ((eq keyword :and-call-through)
    (let ((orig (symbol-function symbol)))
      (buttercup--spy-on-and-call-fake symbol
                                       (lambda (&rest args)
                                         (apply orig args)))))
   ((eq keyword :and-return-value)
    (buttercup--spy-on-and-call-fake symbol
                                     (lambda (&rest args)
                                       arg)))
   ((eq keyword :and-call-fake)
    (buttercup--spy-on-and-call-fake symbol
                                     arg))
   ((eq keyword :and-throw-error)
    (buttercup--spy-on-and-call-fake symbol
                                     (lambda (&rest args)
                                       (signal arg "Stubbed error"))))
   (t
    (buttercup--spy-on-and-call-fake symbol
                                     (lambda (&rest args)
                                       nil)))))

(defun buttercup--spy-on-and-call-fake (spy fake-function)
  "Replace the function in symbol SPY with a spy that calls FAKE-FUNCTION."
  (let ((orig-function (symbol-function spy)))
    (fset spy (buttercup--make-spy fake-function))
    (buttercup--add-cleanup (lambda ()
                              (fset spy orig-function)))))

(defun buttercup--make-spy (fake-function)
  "Create a new spy function which tracks calls to itself."
  (let (this-spy-function)
    (setq this-spy-function
          (lambda (&rest args)
            (let ((return-value (apply fake-function args)))
              (buttercup--spy-calls-add
               this-spy-function
               (make-spy-context :args args
                                 :return-value return-value
                                 :current-buffer (current-buffer)))
              return-value)))
    this-spy-function))

(defvar buttercup--cleanup-functions nil)

(defmacro buttercup--with-cleanup (&rest body)
  `(let ((buttercup--cleanup-functions nil))
     (unwind-protect (progn ,@body)
       (dolist (fun buttercup--cleanup-functions)
         (ignore-errors
           (funcall fun))))))

(defun buttercup--add-cleanup (function)
  (setq buttercup--cleanup-functions
        (cons function buttercup--cleanup-functions)))

(defun spy-calls-all (spy)
  "Return the contexts of calls to SPY."
  (gethash (symbol-function spy)
           buttercup--spy-contexts))

(defun buttercup--spy-calls-add (spy-function context)
  "Add CONTEXT to the recorded calls to SPY."
  (puthash spy-function
           (append (gethash spy-function
                            buttercup--spy-contexts)
                   (list context))
           buttercup--spy-contexts))

(defun spy-calls-reset (spy)
  "Reset SPY, removing all recorded calls."
  (puthash (symbol-function spy)
           nil
           buttercup--spy-contexts))

(buttercup-define-matcher :to-have-been-called (spy)
  (if (spy-calls-all spy)
      t
    nil))

(buttercup-define-matcher :to-have-been-called-with (spy &rest args)
  (let* ((calls (mapcar 'spy-context-args (spy-calls-all spy))))
    (if (member args calls)
        t
      nil)))

(defun spy-calls-any (spy)
  "Return t iff SPY has been called at all, nil otherwise."
  (if (spy-calls-all spy)
      t
    nil))

(defun spy-calls-count (spy)
  "Return the number of times SPY has been called so far."
  (length (spy-calls-all spy)))

(defun spy-calls-args-for (spy index)
  "Return the context of the INDEXth call to SPY."
  (let ((context (elt (spy-calls-all spy)
                      index)))
    (if context
        (spy-context-args context)
      nil)))

(defun spy-calls-all-args (spy)
  "Return the arguments to all calls to SPY."
  (mapcar 'spy-context-args (spy-calls-all spy)))

(defun spy-calls-most-recent (spy)
  "Return the context of the most recent call to SPY."
  (car (last (spy-calls-all spy))))

(defun spy-calls-first (spy)
  "Return the context of the first call to SPY."
  (car (spy-calls-all spy)))

;;;;;;;;;;;;;;;;
;;; Test Runners

;;;###autoload
(defun buttercup-run-at-point ()
  "Run the buttercup suite at point."
  (interactive)
  (let ((buttercup-suites nil)
        (lexical-binding t))
    (eval-defun nil)
    (buttercup-run)
    (message "Suite executed successfully")))

;;;###autoload
(defun buttercup-run-discover ()
  "Discover and load test files, then run all defined suites.

Takes directories as command line arguments, defaulting to the
current directory."
  (dolist (dir (or command-line-args-left '(".")))
    (dolist (file (directory-files-recursively dir
                                               "\\'test-\\|-test.el\\'"))
      (when (not (string-match "/\\." file))
        (load file nil t))))
  (buttercup-run))

;;;###autoload
(defun buttercup-run-markdown ()
  (let ((lisp-buffer (generate-new-buffer "elisp")))
    (dolist (file command-line-args-left)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (while (re-search-forward "```lisp\n\\(\\(?:.\\|\n\\)*?\\)```"
                                  nil t)
          (let ((code (match-string 1)))
            (with-current-buffer lisp-buffer
              (insert code))))))
    (with-current-buffer lisp-buffer
      (setq lexical-binding t)
      (eval-region (point-min)
                   (point-max)))
    (buttercup-run)))

(defun buttercup-run ()
  (if buttercup-suites
      (progn
        (funcall buttercup-reporter 'buttercup-started buttercup-suites)
        (mapc #'buttercup--run-suite buttercup-suites)
        (funcall buttercup-reporter 'buttercup-done buttercup-suites))
    (error "No suites defined")))

(defvar buttercup--before-each nil
  "A list of functions to call before each spec.

Do not change the global value.")

(defvar buttercup--after-each nil
  "A list of functions to call after each spec.

Do not change the global value.")

(defun buttercup--run-suite (suite)
  (let* ((buttercup--before-each (append buttercup--before-each
                                         (buttercup-suite-before-each suite)))
         (buttercup--after-each (append (buttercup-suite-after-each suite)
                                        buttercup--after-each)))
    (funcall buttercup-reporter 'suite-started suite)
    (dolist (f (buttercup-suite-before-all suite))
      (funcall f))
    (dolist (sub (buttercup-suite-children suite))
      (cond
       ((buttercup-suite-p sub)
        (buttercup--run-suite sub))
       ((buttercup-spec-p sub)
        (buttercup--run-spec sub))))
    (dolist (f (buttercup-suite-after-all suite))
      (funcall f))
    (funcall buttercup-reporter 'suite-done suite)))

(defun buttercup--run-spec (spec)
  (funcall buttercup-reporter 'spec-started spec)
  (buttercup--with-cleanup
   (dolist (f buttercup--before-each)
     (funcall f))
   (let ((res (buttercup--funcall (buttercup-spec-function spec))))
     (setf (buttercup-spec-status spec)
           (elt res 0))
     (setf (buttercup-spec-failure-description spec)
           (elt res 1))
     (setf (buttercup-spec-failure-stack spec)
           (elt res 2)))
   (dolist (f buttercup--after-each)
     (funcall f)))
  (funcall buttercup-reporter 'spec-done spec))

;;;;;;;;;;;;;
;;; Reporters

(defvar buttercup-reporter #'buttercup-reporter-batch
  "The reporter function for buttercup test runs.

During a run of buttercup, the value of this variable is called
as a function with two arguments. The first argument is a symbol
describing the event, the second depends on the event.

The following events are known:

buttercup-started -- The test run is starting. The argument is a
  list of suites this run will execute.

suite-started -- A suite is starting. The argument is the suite.
  See `make-buttercup-suite' for details on this structure.

spec-started -- A spec in is starting. The argument is the spec.
  See `make-buttercup-spec' for details on this structure.

spec-done -- A spec has finished executing. The argument is the
  spec.

suite-done -- A suite has finished. The argument is the spec.

buttercup-done -- All suites have run, the test run is over.")

(defun buttercup-reporter-batch (event arg)
  (pcase event
    (`buttercup-started
     (buttercup--print "Running %s specs.\n\n"
                       (buttercup-suites-total-specs-defined arg)))

    (`suite-started
     (let ((level (length (buttercup-suite-parents arg))))
       (buttercup--print "%s%s\n"
                         (make-string (* 2 level) ?\s)
                         (buttercup-suite-description arg))))

    (`spec-started
     (let ((level (length (buttercup-spec-parents arg))))
       (buttercup--print "%s%s\n"
                         (make-string (* 2 level) ?\s)
                         (buttercup-spec-description arg))))

    (`spec-done
     (cond
      ((eq (buttercup-spec-status arg) 'passed)
       t)
      ((eq (buttercup-spec-status arg) 'failed)
       (let ((description (buttercup-spec-failure-description arg))
             (stack (buttercup-spec-failure-stack arg)))
         (when stack
           (buttercup--print "\nTraceback (most recent call last):\n")
           (dolist (frame stack)
             (buttercup--print "  %S\n" (cdr frame))))
         (if (stringp description)
             (buttercup--print "FAILED: %s\n"
                               (buttercup-spec-failure-description arg))
           (buttercup--print "%S: %S\n\n" (car err) (cdr err)))
         (buttercup--print "\n")))
      (t
       (buttercup--print "??? %S\n" (buttercup-spec-status arg)))))

    (`suite-done
     (when (= 0 (length (buttercup-suite-parents arg)))
       (buttercup--print "\n")))

    (`buttercup-done
     (buttercup--print "Ran %s specs, %s failed.\n"
                       (buttercup-suites-total-specs-defined arg)
                       (buttercup-suites-total-specs-failed arg)
                       )
     (when (> (buttercup-suites-total-specs-failed arg) 0)
       (error "")))

    (t
     (error "Unknown event %s" event))))

(defun buttercup--print (fmt &rest args)
  (let ((print-escape-newlines t))
    (princ (apply #'format fmt args))))

;;;;;;;;;;;;;
;;; Utilities

(defun buttercup--funcall (function &rest arguments)
  "Call FUNCTION with ARGUMENTS.

Returns a list of three values. The first is the state:

passed -- The second value is the return value of the function
  call, the third is nil.

failed -- The second value is the description of the expectation
  which failed or the error, the third is the backtrace or nil."
  (catch 'buttercup-debugger-continue
    (let ((debugger #'buttercup--debugger)
          (debug-on-error t)
          (debug-ignored-errors nil))
      (list 'passed
            (apply function arguments)
            nil))))

(defun buttercup--debugger (&rest args)
  ;; If we do not do this, Emacs will not run this handler on
  ;; subsequent calls. Thanks to ert for this.
  (setq num-nonmacro-input-events (1+ num-nonmacro-input-events))
  (throw 'buttercup-debugger-continue
         (if (and (eq (elt args 0) 'error)
                  (eq (car (elt args 1)) 'buttercup-failed))
             (list 'failed (cdr (elt args 1)) nil)
           (list 'error args (buttercup--backtrace)))))

(defun buttercup--backtrace ()
  (let* ((n 0)
         (frame (backtrace-frame n))
         (frame-list nil)
         (in-program-stack nil))
    (while frame
      (when in-program-stack
        (push frame frame-list))
      (when (eq (elt frame 1)
                'buttercup--debugger)
        (setq in-program-stack t))
      (when (eq (elt frame 1)
                'buttercup--funcall)
        (setq in-program-stack nil
              frame-list (nthcdr 6 frame-list)))
      (setq n (1+ n)
            frame (backtrace-frame n)))
    frame-list))

(provide 'buttercup)
;;; buttercup.el ends here
