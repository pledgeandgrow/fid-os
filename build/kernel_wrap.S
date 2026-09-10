.section .text
.global _start
_start:
    .incbin "build/kernel-raw.bin"
