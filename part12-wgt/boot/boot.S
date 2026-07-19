#include "sysregs.h"

#define MAIN_STACK      0x400000

.section ".text.boot"  // Make sure the linker puts this at the start of the kernel image

.global _start  // Execution starts here

_start:
    // Only the main core arrives here - the firmware's stub has already
    // parked cores 1-3, leaving them spinning on the Pi 4's spin table.
    // The stub has also sorted out the timer and dropped us to EL2. We
    // couldn't program the timer ourselves if we wanted to: cntfrq_el0
    // is only writable from EL3, and EL3 is behind us now

    adr     x0, el1_entry        // Tell el2_to_el1 where this core continues...
    b       el2_to_el1           // ...and take the drop to EL1

el1_entry:
    // We're in EL1, with the FPU on
    // Clean the BSS section
    ldr     x1, =__bss_start     // Start address
    ldr     w2, =__bss_size      // Size of the section
3:  cbz     w2, 4f               // Quit loop if zero
    str     xzr, [x1], #8
    sub     w2, w2, #1
    cbnz    w2, 3b               // Loop if non-zero

    // Set stack to start somewhere safe
    mov     sp, #MAIN_STACK

    // Jump to our main() routine in C (make sure it doesn't return)
4:  bl      main
    // In case it does return, halt the master core too
5:  wfe
    b       5b

.global secondary_entry  // Cores 1-3 arrive here when released from the stub's spin table

secondary_entry:
    // Like core 0, we arrive from the stub at EL2. Every register that
    // el2_to_el1 touches is per-core, so each core takes the drop itself
    // - not least because the comms and ticker cores need the FPU too!

    adr     x0, secondary_el1
    b       el2_to_el1

secondary_el1:
    mrs     x1, mpidr_el1        // Check our processor ID
    and     x1, x1, #3

    ldr     x2, =__stack_start   // Get ourselves a fresh stack - location depends on CPU core asking
    lsl     x3, x1, #14          // Multiply core_number by 16KB (the per-core stack size in link.ld)
    add     x3, x2, x3           // Add to the address
    mov     sp, x3

    adr     x5, spin_cpu0        // Base watch address
1:  ldr     x4, [x5, x1, lsl #3] // Add (8 * core_number) to the base address and load what's there
    cbnz    x4, 2f               // If it's non-zero, go run it...
    wfe                          // ...otherwise sleep until the next event
    b       1b
2:  blr     x4                   // Run the code at the address in x4 (sets x30, so it can return to us)
    b       1b                   // Once that code returns, we start looping and watching all over again

el2_to_el1:
    // Configure EL1 for the calling core and drop down into it, continuing
    // at the address passed in x0. In the kernel_old=1 days we did this from
    // EL3 with scr_el3/spsr_el3/elr_el3 - it's the same dance, one level down

    msr     elr_el2, x0          // Where eret will land us

    mov     x0, #0x33ff
    msr     cptr_el2, x0         // Disable coprocessor traps to EL2
    mov     x0, #3 << 20
    msr     cpacr_el1, x0        // Enable FP/SIMD at EL1

    ldr     x0, =SCTLR_VALUE_MMU_DISABLED
    msr     sctlr_el1, x0

    ldr     x0, =HCR_VALUE
    msr     hcr_el2, x0          // EL1 will run in AArch64 (not AArch32)

    mov     x0, #3
    msr     cnthctl_el2, x0      // Let EL1 read the physical timer/counter (wait_msec needs this!)...
    msr     cntvoff_el2, xzr     // ...and give the virtual counter no offset

    ldr     x0, =SPSR_VALUE
    msr     spsr_el2, x0         // Land at EL1h with interrupts masked

    eret

.globl get_el
get_el:
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    ret

.ltorg

// Our own per-core release words, watched by secondary_entry. Not to be
// confused with the firmware stub's spin table down at 0xd8-0xf0! Nothing
// needs these at a fixed address any more, so they can be plain labels -
// no more .org juggling to keep them clear of a growing boot.S
.balign 8
.globl spin_cpu0
spin_cpu0:
        .quad 0

.globl spin_cpu1
spin_cpu1:
        .quad 0

.globl spin_cpu2
spin_cpu2:
        .quad 0

.globl spin_cpu3
spin_cpu3:
        .quad 0
