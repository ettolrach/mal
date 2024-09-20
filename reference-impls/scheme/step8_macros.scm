(import (scheme base))
(import (scheme write))
(import (scheme process-context))

(import (lib util))
(import (lib reader))
(import (lib printer))
(import (lib types))
(import (lib env))
(import (lib core))

(define (READ input)
  (read-str input))

(define (starts-with? ast sym)
  (let ((items (mal-value ast)))
    (and (not (null? items))
         (let ((a0 (car items)))
           (and (mal-instance-of? a0 'symbol)
                (eq? (mal-value a0) sym))))))

(define (qq-lst xs)
  (if (null? xs)
      (mal-list '())
      (let ((elt (car xs))
            (acc (qq-lst (cdr xs))))
        (if (and (mal-instance-of? elt 'list) (starts-with? elt 'splice-unquote))
            (mal-list (list (mal-symbol 'concat) (cadr (mal-value elt)) acc))
            (mal-list (list (mal-symbol 'cons) (QUASIQUOTE elt) acc))))))

(define (QUASIQUOTE ast)
  (case (and (mal-object? ast) (mal-type ast))
    ((list)       (if (starts-with? ast 'unquote)
                    (cadr (mal-value ast))
                    (qq-lst (->list (mal-value ast)))))
    ((vector)     (mal-list (list (mal-symbol 'vec) (qq-lst (->list (mal-value ast))))))
    ((map symbol) (mal-list (list (mal-symbol 'quote) ast)))
    (else         ast)))

(define (EVAL ast env)
    (let ((dbgeval (env-get env 'DEBUG-EVAL)))
      (when (and (mal-object? dbgeval)
                 (not (memq (mal-type dbgeval) '(false nil))))
        (display (str "EVAL: " (pr-str ast #t) "\n"))))
    (case (and (mal-object? ast) (mal-type ast))
      ((symbol)
       (let ((key (mal-value ast)))
         (or (env-get env key) (error (str "'" key "' not found")))))
      ((vector)
       (mal-vector (vector-map (lambda (item) (EVAL item env))
                               (mal-value ast))))
      ((map)
       (mal-map (alist-map (lambda (key value) (cons key (EVAL value env)))
                           (mal-value ast))))
      ((list)
       (let ((items (mal-value ast)))
         (if (null? items)
                  ast
                  (let ((a0 (car items)))
                    (case (and (mal-object? a0) (mal-value a0))
                      ((def!)
                       (let ((symbol (mal-value (cadr items)))
                             (value (EVAL (list-ref items 2) env)))
                         (env-set env symbol value)
                         value))
                      ((defmacro!)
                       (let ((symbol (mal-value (cadr items)))
                             (value (EVAL (list-ref items 2) env)))
                         (when (func? value)
                           (func-macro?-set! value #t))
                         (env-set env symbol value)
                         value))
                      ((let*)
                       (let ((env* (make-env env))
                             (binds (->list (mal-value (cadr items))))
                             (form (list-ref items 2)))
                         (let loop ((binds binds))
                           (when (pair? binds)
                             (let ((key (mal-value (car binds))))
                               (when (null? (cdr binds))
                                 (error "unbalanced list"))
                               (let ((value (EVAL (cadr binds) env*)))
                                 (env-set env* key value)
                                 (loop (cddr binds))))))
                         (EVAL form env*))) ; TCO
                      ((do)
                       (let ((forms (cdr items)))
                         (if (null? forms)
                             mal-nil
                             ;; the evaluation order of map is unspecified
                             (let loop ((forms forms))
                               (let ((form (car forms))
                                     (tail (cdr forms)))
                                 (if (null? tail)
                                     (EVAL form env) ; TCO
                                     (begin
                                       (EVAL form env)
                                       (loop tail))))))))
                      ((if)
                       (let* ((condition (EVAL (cadr items) env))
                              (type (and (mal-object? condition)
                                         (mal-type condition))))
                         (if (memq type '(false nil))
                             (if (< (length items) 4)
                                 mal-nil
                                 (EVAL (list-ref items 3) env)) ; TCO
                             (EVAL (list-ref items 2) env)))) ; TCO
                      ((quote)
                       (cadr items))
                      ((quasiquote)
                       (EVAL (QUASIQUOTE (cadr items)) env)) ; TCO
                      ((fn*)
                       (let* ((binds (->list (mal-value (cadr items))))
                              (binds (map mal-value binds))
                              (body (list-ref items 2))
                              (fn (lambda args
                                    (let ((env* (make-env env binds args)))
                                      (EVAL body env*)))))
                         (make-func body binds env fn)))
                      (else
                       (let ((op (EVAL a0 env)))
                       (if (and (func? op) (func-macro? op))
                        (EVAL (apply (func-fn op) (cdr items)) env) ; TCO
                        (let* ((ops (map (lambda (item) (EVAL item env)) (cdr items))))
                         (if (func? op)
                             (let* ((outer (func-env op))
                                    (binds (func-params op))
                                    (env* (make-env outer binds ops)))
                               (EVAL (func-ast op) env*)) ; TCO
                             (apply op ops)))))))))))
      (else ast)))

(define (PRINT ast)
  (pr-str ast #t))

(define repl-env (make-env #f))
(for-each (lambda (kv) (env-set repl-env (car kv) (cdr kv))) ns)

(define (rep input)
  (PRINT (EVAL (READ input) repl-env)))

(define args (cdr (command-line)))

(env-set repl-env 'eval (lambda (ast) (EVAL ast repl-env)))
(env-set repl-env '*ARGV* (mal-list (map mal-string (cdr-safe args))))

(rep "(def! not (fn* (a) (if a false true)))")
(rep "(def! load-file (fn* (f) (eval (read-string (str \"(do \" (slurp f) \"\nnil)\")))))")
(rep "(defmacro! cond (fn* (& xs) (if (> (count xs) 0) (list 'if (first xs) (if (> (count xs) 1) (nth xs 1) (throw \"odd number of forms to cond\")) (cons 'cond (rest (rest xs)))))))")

(define (main)
  (let loop ()
    (let ((input (readline "user> ")))
      (when input
        (guard
         (ex ((error-object? ex)
              (when (not (memv 'empty-input (error-object-irritants ex)))
                (display "[error] ")
                (display (error-object-message ex))
                (newline)))
             ((and (pair? ex) (eq? (car ex) 'user-error))
              (display "[error] ")
              (display (pr-str (cdr ex) #t))
              (newline)))
         (display (rep input))
         (newline))
        (loop))))
  (newline))

(if (null? args)
    (main)
    (rep (string-append "(load-file \"" (car args) "\")")))