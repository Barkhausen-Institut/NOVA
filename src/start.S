/*
 * Startup Code
 *
 * Copyright (C) 2009-2011 Udo Steinberg <udo@hypervisor.org>
 * Economic rights: Technische Universitaet Dresden (Germany)
 *
 * Copyright (C) 2012 Udo Steinberg, Intel Corporation.
 *
 * This file is part of the NOVA microhypervisor.
 *
 * NOVA is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * NOVA is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License version 2 for more details.
 */

#include "arch.hpp"
#include "memory.hpp"
#include "selectors.hpp"

/*
 * Initialization Code
 */
.section .init

.globl                  __start_bsp

/*
 * Multiboot Header
 */
__boot_header:          .long   0x1badb002
                        .long   0x0
                        .long  -0x1badb002

/*
 * Global Descriptor Table (GDT)
 */
.align                  8, 0x90
__boot_gdt:             .word   0
                        .word   __boot_gdt__ - __boot_gdt - 1
                        .long   __boot_gdt
#ifdef __x86_64__
                        .quad   0x00a09b0000000000
                        .quad   0x00a0930000000000
                        .quad   0x00a0fb0000000000
                        .quad   0x00a0f30000000000
#else
                        .quad   0x00cf9b000000ffff
                        .quad   0x00cf93000000ffff
                        .quad   0x00cffb000000ffff
                        .quad   0x00cff3000000ffff
#endif
__boot_gdt__:

.macro                  INIT_STATE
                        mov     $SEL_KERN_DATA, %ecx
                        mov     %ecx, %ss
                        mov     $SEL_USER_DATA, %ecx
                        mov     %ecx, %ds
                        mov     %ecx, %es
                        mov     %ecx, %fs
                        mov     %ecx, %gs
                        mov     $STACK, %esp
.endm

.macro                  INIT_PAGING
#ifdef __x86_64__
                        mov     $0xc0000080, %ecx
                        rdmsr
                        or      $0x101, %eax
                        wrmsr
                        mov     $0x6b8, %edx
#else
                        mov     $0x698, %edx
#endif
                        mov     %edx, %cr4
                        mov     $PDBR, %edx
                        mov     %edx, %cr3
                        mov     $0x8001002b, %edx
                        mov     %edx, %cr0
.endm

/*
 * AP Startup Code
 */
.code16

#ifdef GEM5

__start_ap:             cli
                        ljmpl    $0x8, $1f + 0x1000 - (__start_ap + SEL_KERN_CODE << 4)

1:                      // init segment registers
                        mov     %cs, %ax
                        mov     %ax, %ds
                        mov     %ax, %es
                        mov     %ax, %ss
                        // load temporary GDT
                        lgdtl   %ds:__prot_gdt + 2 + 0x1000 - (__start_ap + SEL_KERN_CODE << 4)
                        // enable protected mode
                        mov     $0x1, %eax
                        mov     %eax, %cr0
                        // far jump to protected mode
                        ljmpl   $0x8, $__prot_mode_ap + 0x1000 - __start_ap

.code32

__prot_mode_ap:         // set segment registers to use the 32-bit DS
                        mov     $0x18, %ax
                        mov     %ax, %ds
                        mov     %ax, %es
                        mov     %ax, %ss
                        // setup paging and enable long mode
                        INIT_PAGING
                        // far jump to long mode
                        ljmpl    $0x10, $__start_all

.align                  8, 0x90
__prot_gdt:             .word   0
                        .word   __prot_gdt__ - __prot_gdt - 1
                        .long   __prot_gdt + 0x1000 - __start_ap
                        .quad   0x00cf9b000000ffff      // 32-bit CS
                        .quad   0x00af9b000000ffff      // 64-bit CS
                        .quad   0x00cf93000000ffff      // 32-bit DS
__prot_gdt__:

#else

__start_ap:             INIT_PAGING
                        lgdtl   %cs:__gdt_desc - __start_ap
                        ljmpl   $SEL_KERN_CODE, $__start_all

__gdt_desc:             .word   __boot_gdt__ - __boot_gdt - 1
                        .long   __boot_gdt

#endif

/*
 * BSP Startup Code
 */
#ifdef GEM5
.code64
#else
.code32
#endif

__start_bsp:            mov     $(__start_bsp - __start_ap), %ecx
                        mov     $__start_ap, %esi
                        mov     $0x1000, %edi
                        rep     movsb
#ifdef __x86_64__
                        mov     $(LVL3L + 0x27), %ecx
                        mov     %ecx, LVL4  + SIZE * (LOAD_ADDR >> (3 * PTE_BPL + PAGE_BITS) & ((1 << PTE_BPL) - 1))
                        mov     $(LVL2L + 0x27), %ecx
                        mov     %ecx, LVL3L + SIZE * (LOAD_ADDR >> (2 * PTE_BPL + PAGE_BITS) & ((1 << PTE_BPL) - 1))

                        mov     $(LVL3H + 0x27), %ecx
                        mov     %ecx, LVL4  + SIZE * (LINK_ADDR >> (3 * PTE_BPL + PAGE_BITS) & ((1 << PTE_BPL) - 1))
                        mov     $(LVL2H + 0x27), %ecx
                        mov     %ecx, LVL3H + SIZE * (LINK_ADDR >> (2 * PTE_BPL + PAGE_BITS) & ((1 << PTE_BPL) - 1))
#endif
                        mov     $0xe3, %ecx
                        mov     $LVL2L, %edi
1:                      mov     %ecx, (%edi)
                        add     $(1 << (PTE_BPL + PAGE_BITS)), %ecx
                        add     $SIZE, %edi
                        cmp     $LOAD_E, %ecx
                        jb      1b

                        mov     $(LINK_P + 0x1e3), %ecx
                        mov     $(LVL2H + SIZE * (LINK_ADDR >> (PTE_BPL + PAGE_BITS) & ((1 << PTE_BPL) - 1))), %edi
1:                      mov     %ecx, (%edi)
                        add     $(1 << (PTE_BPL + PAGE_BITS)), %ecx
                        add     $SIZE, %edi
                        cmp     $LINK_E, %ecx
                        jb      1b

                        // init paging
#ifdef GEM5
                        mov     $0xc0000080, %ecx
                        rdmsr
                        or      $0x101, %eax
                        wrmsr
                        mov     $0x6b8, %rdx
                        mov     %rdx, %cr4
                        mov     $PDBR, %rdx
                        mov     %rdx, %cr3
                        mov     $0x8001002b, %rdx
                        mov     %rdx, %cr0

__start_all:            lgdt    __boot_gdt + 2

#else
                        INIT_PAGING
                        lgdt    __boot_gdt + 2
                        ljmp    $SEL_KERN_CODE, $__start_all

/*
 * Common Startup Code
 */
#ifdef __x86_64__
.code64
#endif

__start_all:
#endif

                        INIT_STATE
                        test    %REG(bx), %REG(bx)
                        je      2f

                        mov     %REG(bx), %ARG_1
                        call    init
                        jmp     3f

1:                      pause
2:                      xchg    %REG(bx), boot_lock
                        test    %REG(bx), %REG(bx)
                        je      1b

3:                      call    kern_ptab_setup
                        jmp     1f

.text

1:                      mov     %REG(ax), %cr3
                        mov     $(CPU_LOCAL_STCK + PAGE_SIZE), %REG(sp)
                        jmp     bootstrap
