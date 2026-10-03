# change B to the path to BareMetal-OS
B=../BareMetal-OS
CFLAGS=-Ofast -fno-builtin -funsigned-char -fno-unwind-tables -Wno-parentheses -Wno-incompatible-pointer-types \
       -Wfatal-errors -nostdlib -mno-red-zone -mcmodel=large -fomit-frame-pointer \
       $(ARCH) $(KFLAGS) -I$B/src/BareMetal/api
# Default: kbm as shipped (AVX-512; needs Bochs or a real AVX-512 CPU).
# `make PORTABLE=1`: no AVX-512 (ksrc/kvec.h) and OS calls via k_sys
# (ksrc/ksys.h -> s.asm), so it also runs under QEMU TCG, e.g. on a Mac.
# Add KHEAP=n for a smaller heap (ksrc/kheap.h), e.g. KHEAP=22 for 256 MiB.
ifdef PORTABLE
ARCH=-march=x86-64-v2
KFLAGS=-DKSYS -Wno-psabi $(if $(KHEAP),-DKHEAP=$(KHEAP))
NFLAGS=-dKSYS
else
ARCH=-march=icelake-client
endif
CC=$(shell which clang-13 clang |head -1)
l=-z max-page-size=0x1000 -z noexecstack
img=$B/sys/baremetal_os.img
app=$B/sys/k.app

all:$(img)
# Rebuild everything when the flavor (default vs PORTABLE) changes; otherwise
# objects from the other flavor are silently reused.
FLAVOR=$(ARCH) $(KFLAGS) $(NFLAGS)
.flavor: FORCE
	@echo '$(FLAVOR)' | cmp -s - $@ || echo '$(FLAVOR)' > $@
FORCE:
sys.o a.o z.o s.o: .flavor
_.h: makefile $(wildcard ksrc/*.[hc])
	cp ksrc/*.[hc] .
z.c:_.h
a.c:_.h
s.o:s.asm
	nasm -f elf64 $(NFLAGS) s.asm -I$B/src/BareMetal
$(img):sys.o a.o z.o s.o
	ld -T app.ld $l sys.o a.o z.o s.o -o k
	objcopy -O binary k $(app)
	cd $B && ./baremetal.sh k.app
bochs:$(img)
	bochs -qf /dev/null -rc bochsrc \
	 boot:disk ata0-master:type=disk,path=$(img) cpu:model=sapphire_rapids megs:1200 || true
disasm:
	objdump -drwC -Mintel -S k | less
clean:
	rm -rf k *.o *.s $(img) $(app) ?.[ch] kvec.h ksys.h kheap.h z.k .flavor
