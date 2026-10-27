/* A51 boot-1 shim: linked at 0, header first, everything PC-relative. */
ENTRY(_start)
SECTIONS
{
	. = 0;
	.text.head : { *(.text.head) }
	.text : { *(.text*) }
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }
	.bss : {
		*(.bss*)
		*(COMMON)
	}
	_end = .;
	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
