/* boards/mcu/rv32-virt/start.S -- reset entry for k on QEMU riscv32 `virt`.
 * Stand-in for the ESP32-P4 (RV32IMAFC) and, built soft-float,
 * for RV32IMAC cores (RP2350 Hazard3, ESP32-C3/C6). Real boards get this from their
 * SDK (ESP-IDF); the part that matters here is enabling the FPU before any
 * C runs: with mstatus.FS = Off, the first float instruction traps. */
	.section .text.init, "ax"
	.option norvc
	.globl	_start
_start:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	sp, __stack_top
#ifdef __riscv_flen			/* only when the ISA has F/D */
	li	t0, (1 << 13)		/* mstatus.FS = Initial: FPU on */
	csrs	mstatus, t0
	fscsr	zero
#endif
	la	t0, __bss_start
	la	t1, __bss_end
1:	bgeu	t0, t1, 2f
	sw	zero, 0(t0)
	addi	t0, t0, 4
	j	1b
2:	call	kmain
3:	wfi
	j	3b
