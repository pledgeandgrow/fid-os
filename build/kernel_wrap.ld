PHDRS { text PT_LOAD; }
SECTIONS { . = 0x100000; .text : { *(.text) } :text }
