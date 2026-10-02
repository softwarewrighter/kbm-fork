/* host-linux.S -- run kbm's k sources as a native x86-64 Linux process.
 *
 * Purpose: a known-good execution of the *same* k sources on a CPU with real
 * AVX-512, giving golden transcripts that a BareMetal, sw-os-ml or ARM64
 * port can be diffed against.
 *
 * k's z.h routes every OS call through `call b_k` with the Linux syscall
 * number in rax and args in rdi, rsi, rdx, r10 (copied from rcx), r8, r9 --
 * the native syscall ABI -- so b_k is a bare `syscall`. On BareMetal the
 * same symbol is s.asm's translation layer (read/write/exit only).
 */
	.text
	.globl	b_k
b_k:
	syscall
	ret

	.globl	_start
_start:
	xor	%ebp, %ebp
	mov	(%rsp), %rdi		/* argc */
	lea	8(%rsp), %rsi		/* argv */
	and	$-16, %rsp
	call	main
	mov	%eax, %edi
	mov	$60, %eax		/* exit */
	syscall
	.section .note.GNU-stack,"",@progbits
