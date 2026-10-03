OUTPUT_ARCH("i386:x86-64")
ENTRY(_start)
SECTIONS
{
	. = 0xFFFF800000000000;
	.text : {
		*(.text.startup)
		*(.text)
	}
	.data : {
		*(.data .rodata) QUAD(ADDR(.bss)+SIZEOF(.bss))
	}
	.bss : {
		__bss_start = .;
		*(.bss)
		__bss_stop = .;
	}
}
/* Bounds of the large-code-model .lbss, where -mcmodel=large puts every
   zero-initialized global (the .bss above stays empty). PORTABLE builds
   zero this range at startup (sys.c); symbols only, so k.app is unchanged. */
__lbss_start = ADDR(.lbss);
__lbss_end = ADDR(.lbss) + SIZEOF(.lbss);
