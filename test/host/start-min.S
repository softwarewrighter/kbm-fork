/* start-min.S -- minimal x86-64 Linux entry for standalone test programs. */
	.text
	.globl	w2
w2:				/* w2(n, s): write(1, s, n) */
	mov	%rdi, %rdx
	mov	$1, %edi
	mov	$1, %eax
	syscall
	ret
	.globl	_start
_start:
	and	$-16, %rsp
	call	main
	mov	%eax, %edi
	mov	$60, %eax
	syscall
	.section .note.GNU-stack,"",@progbits
