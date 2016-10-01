(use format srfi-1)

(define word-size 4)

;; data types
(define fixnum-mask 3)
(define fixnum-tag 0)
(define fixnum-shift 2)

(define char-shift 8)
(define char-tag 15)

(define boolean-mask 127)
(define boolean-shift 7)
(define boolean-tag 31)
(define null-tag 47)

(define (stack-pos si)
  (if (zero? si)
    "%eax"
    (string-append (->string si) "(%esp)")))

(define (immediate? v) ; literal value that fits in one word (i.e 1, #\a, #t, '())
  (or (integer? v) (char? v) (boolean? v) (null? v)))

(define (primcall? e) ; a call that takes one immediate argument (so it can be with only registers)
  (> (length e) 1))

(define (emit fmt . sp) ; used to build assembly
  (define label (eq? (string-ref fmt (- (string-length fmt) 1)) #\:))
  (define directive (eq? (string-ref fmt 0) #\.))
  (string-append
    (if (or label directive)
      ""
      "\t")
    (if (null? sp)
      fmt
      (apply (cut format #f fmt <> <...>) sp))
    "\n"))

(define (immediate-rep p) ; convert a lisp value to an immediate
  (cond
    ((integer? p) ; lower two bits are 00
     (arithmetic-shift p fixnum-shift))
    ((char? p)    ; lower eight bits are 00001111
     (bitwise-ior (arithmetic-shift (char->integer p) char-shift) char-tag))
    ((boolean? p) ; lower 7 bits are 0011111
     (bitwise-ior (arithmetic-shift (if p 1 0) boolean-shift) boolean-tag))
    ((null? p)    ; lower 8 bits are 00101111
     null-tag)))

(define (emit-immediate e si)
  (emit "movl $~a, ~a"
	(immediate-rep e)
	(stack-pos si)))

(define (emit-cmp-eax val) ; cmp eax to val (TODO: make this more efficient)
  (string-append
    (emit "mov $~a, %ecx" (immediate-rep #f)) ; move #t and #f into registers
    (emit "mov $~a, %edx" (immediate-rep #t))
    (emit "cmp $~a, %eax" val)
    (emit "cmovzl %edx, %ecx")
    (emit "mov %ecx, %eax"))) ; move the result to %eax

(define (emit-primative e si)
  (case (car e)
    ((add1)
     (string-append
       (emit-expr (cadr e) si)
       (emit "addl $~a, %eax" (immediate-rep 1))))
    ((sub1)
     (string-append
       (emit-expr (cadr e) si)
       (emit "subl $~a, %eax" (immediate-rep 1))))
    ((integer->char)
     (string-append
       (emit-expr (cadr e) si)
       (emit "shl $~a, %eax" 6)
       (emit "orl $~a, %eax" char-tag)))
    ((char->integer)
     (string-append
       (emit-expr (cadr e) si)
       (emit "shr $~a, %eax" 6)))
    ((null?)
     (string-append
       (emit-expr (cadr e) si)
       (emit-cmp-eax null-tag)))
    ((integer?)
     (string-append
       (emit-expr (cadr e) si)
       (emit "andl $~a, %eax" fixnum-mask) ; mask out data
       (emit-cmp-eax fixnum-tag)))
    ((boolean?)
     (string-append
       (emit-expr (cadr e) si)
       (emit "andl $~a, %eax" boolean-mask) ; mask out data
       (emit-cmp-eax boolean-tag)))
    ((zero?)
     (string-append
       (emit-expr (cadr e) si)
       (emit-cmp-eax 0)))
    ((+)
     (string-append (emit-expr (cadr e) si)
		    (emit "movl %eax, ~a"
			  (stack-pos si))
		    (emit-expr
		      (cadr e)
		      (- si word-size))
		    (emit "addl ~a, %eax"
			  (stack-pos si))))))

(define (emit-expr e si)
  (cond ((immediate? e)
	 (emit-immediate e si))
	((primcall? e)
	 (emit-primative e si))
	(else
	  (error "can't generate for expression " e))))

(define (compile-program p)
  (string-append
    (emit ".globl scheme_entry") ; boilerplate
    (emit ".type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit-expr p 0)
    (emit "ret")))
