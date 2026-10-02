; BareMetal Linux syscall translation
; x86-64 passes syscall arguments as follows:
; SC	RETURN	ARG0	ARG1	ARG2	ARG3	ARG4	ARG5
; RAX	RAX	RDI	RSI	RDX	R10	R8	R9

; -----------------------------------------------------------------------------
; b_k -- BareMetal Linux syscall API for k
%include 'api/libBareMetal.asm'
global b_k
extern b_read
b_k:
	cmp ax, 0
	je b_k_read_stdin
	cmp ax, 1
	je b_k_write_stdout
	cmp ax, 60
	je b_k_exit
	mov rax,$-1
	ret
b_k_read_stdin:
	call b_read
	ret
b_k_write_stdout:
	push rcx
	mov rcx, rdx
	call [0x00100018]		; b_output
	pop rcx
	mov rax, rdx
	ret
b_k_exit:
	mov rcx, SHUTDOWN
	call [b_system]
	ret
;-----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; k_sys -- C-ABI entry used by `make PORTABLE=1` builds (see ksrc/ksys.h)
; IN: RDI = nr (x86-64 Linux numbering), RSI, RDX, RCX = first three args
; Reshuffles to b_k's convention (AX = nr, RDI/RSI/RDX = args).
; Assembled only with -dKSYS, so the default build is byte-identical.
%ifdef KSYS
global k_sys
k_sys:
	mov rax, rdi
	mov rdi, rsi
	mov rsi, rdx
	mov rdx, rcx
	jmp b_k
%endif
;-----------------------------------------------------------------------------
