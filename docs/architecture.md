# Fides OS — Architecture

> A bare-metal operating system written in Fides, compiled by the
> self-hosted Fides compiler, booted via GRUB/Multiboot2.

## 1. Boot Flow

```
    Power On
       │
       ▼
  BIOS / UEFI
       │
       ▼
  GRUB (from ISO)
       │  loads kernel binary at 0x100000
       │  sets up Multiboot2 info struct
       ▼
  boot trampoline (in PE backend)
       │  sets up stack at 0x90000
       │  saves multiboot pointer at 0x50000
       │  32-bit → 64-bit long mode switch
       │  GDT (kernel/user code/data + TSS)
       │  PAE, page tables (PML4 at 0x70000, PDPT at 0x71000)
       │  EFER.LME, paging
       │  far jump to 64-bit code
       ▼
  kernel/shell.fd :: main()
       │  p_serial_init()
       │  vga_clear()
       │  print banner
       │  init heap + buddy allocator + slab allocator
       │  init process table + scheduler
       │  init VFS + tmpfs + procfs
       │  init E1000 + network stack
       │  run shell loop (interactive)
       ▼
  Shell (interactive — 50+ commands)
```

## 2. Memory Layout

```
  0x000000 - 0x000FFF   ── unused / low memory
  0x000500 - 0x00050A   ── IDT descriptor (limit + base)
  0x001000 - 0x001FFF   ── IDT (256 entries × 16 bytes)
  0x004000 - 0x004067   ── TSS (104 bytes, rsp0=0x90000)
  0x00600  - 0x0068F    ── Scancode buffer (16 entries + head/tail)
  0x006D8  - 0x006FF    ── VFS current working directory (64-byte buffer)
  0x008000 - 0x008FFF   ── SMP AP trampoline (SIPI vector 0x08)
  0x10000  - 0x11FFF    ── User program load address
  0x12000              ── User stack (grows down)
  0x100000             ── Kernel load address (GRUB/Multiboot2)
  0xB8000              ── VGA text buffer (80×25, 2 bytes/cell)
  0x200000             ── Kernel stack region
  0x300000 - 0x30FFFF  ── Kernel heap (bump allocator, ptr at 0x300000)
  0x310000             ── Heap bitmap (page allocation tracking)
  0x320000 - 0x32FFFF  ── Scheduler process table + quantum + current proc
  0x330000 - 0x33FFFF  ── Kernel thread table (16 threads × 128 bytes)
  0x340000 - 0x34FFFF  ── Kernel thread stacks (16 × 4KB)
  0x350000 - 0x35FFFF  ── Disk block cache (8 sectors × 520 bytes)
  0x360000 - 0x36FFFF  ── Process stacks
  0x3F8                 ── COM1 serial port
  0x60 / 0x64           ── Keyboard data / status ports
  0x70 / 0x71            ── CMOS / RTC
  0x1F0 - 0x1F7         ── Primary ATA/PIO disk controller
  0x604 / 0xB004        ── QEMU ACPI shutdown ports
  0x150000             ── PCI device table
  0x160000 - 0x163FFF  ── Process descriptor table (64 procs × 64 bytes)
  0x170000 - 0x173FFF  ── Signal handler table (32 signals × 8 bytes)
  0x180000 - 0x183FFF  ── Pipe table
  0x190000 - 0x190FFF  ── File descriptor table (16 entries × 32 bytes)
  0x1A0000 - 0x1AEFFF  ── E1000 TX/RX descriptors, buffers, MAC, ARP cache
  0x1AE300 - 0x1AE30F  ── ICMP ping statistics (sent/recv/RTT)
  0x1AE400 - 0x1AE5FF  ── DHCP packet buffer + UDP socket table
  0x1AE500 - 0x1AE5FF  ── UDP socket table
  0x1AE600 - 0x1AE6FF  ── TCP socket table (4 sockets)
  0x1AE700 - 0x1AF6FF  ── TCP receive buffers (4 KB per socket)
  0x1AF710 - 0x1AF72F  ── UDP receive metadata (flag, len, src IP/port, dst port)
  0x1AF730 - 0x1AF73F  ── TCP accept flag + child socket id
  0x1AF740 - 0x1AF74F  ── DNS result + DHCP offered IP
  0x1AF750 - 0x1AF7CF  ── Unified socket API table (8 entries × 16 bytes)
  0x1AF800 - 0x1AF9FF  ── Generic UDP receive buffer (512 bytes)
  0x1AFA00 - 0x1AFAFF  ── DNS query buffer
  0x1B0000 - 0x1B0FFF  ── Framebuffer metadata + cursor + font data
  0x1C0000 - 0x1C0FFF  ── tmpfs entry table (64 entries × 48 bytes)
  0x1C1000 - 0x1C7FFF  ── tmpfs data area (~28 KB)
  0x1C8000 - 0x1C8FFF  ── procfs generated content buffer (4 KB)
  0x1C9000 - 0x1C97FF  ── procfs temp label buffers
  0x1CB000 - 0x1CBFFF  ── tmpfs read buffer (4 KB)
  0x1D0000 - 0x1D0FFF  ── Shell variable table (32 vars × 64 bytes)
  0x1D1000 - 0x1D2FFF  ── Output capture buffer (8KB, pipes/redirects)
  0x1D3000 - 0x1D4000  ── Pipe input buffer (4KB)
  0x1D5000 - 0x1D5008  ── Capture flag + length (console output capture)
  0x1D6000 - 0x1D6FFF  ── Shell history (16 entries × 128 bytes)
  0x1E0000 - 0x1E0FFF  ── Capability table (128 entries × 32 bytes)
  0x1E1000 - 0x1E2FFF  ── Message endpoints (8 × 1KB ring buffers)
  0x1E2000 - 0x1E20FF  ── Message test buffer (temp, cmd_msg)
  0x50000              ── Multiboot2 info pointer (saved by boot trampoline)
  0x70000 - 0x71FFF    ── Boot page tables (PML4 + PDPT, identity-mapped)
  0xFEE00000           ── LAPIC MMIO base
```

## 3. Subsystems

### 3.1 VGA Text Output
- **File:** `kernel/vga.fd`
- **Address:** `0xB8000`
- **Mode:** 80 columns × 25 rows, 2 bytes per cell (char + attr)
- **Functions:** `vga_putc`, `vga_clear`, `vga_scroll`, `con_putc`

### 3.2 Serial Output
- **File:** `kernel/serial.fd`
- **Port:** COM1 (`0x3F8`)
- **Functions:** `p_serial_init`, `p_serial_write`, `serial_putc`
- **Purpose:** Debug output mirrored to QEMU `-serial stdio`

### 3.3 Console
- **File:** `kernel/console.fd`
- **Functions:** `con_putc`, `con_putn`, `print_dec`, `print_hex`
- **Input buffer:** Character-by-character with `input_matches`/`input_matches8`/
  `input_prefix4`/`input_prefix8` helpers for command dispatch
- **Capture:** Output capture for pipes/redirects (CAPTURE_FLAG at 0x1D5000)

### 3.4 Keyboard Input (Interrupt-Driven)
- **File:** `kernel/keyboard.fd`
- **Ports:** `0x60` (data), `0x64` (status)
- **Mode:** Interrupt-driven (IRQ1 → IDT vector 0x21)
- **Handler:** `interrupt fn irq1_handler()` — reads scancode, stores in buffer, sends EOI
- **Buffer:** Circular buffer at 0x600 (16 entries), head/tail at 0x680/0x688
- **Functions:** `kbd_read_scancode()` — uses `hlt` to sleep until key press

### 3.5 Memory Management
- **File:** `kernel/kalloc.fd`
- **Bump allocator:** Heap at `0x300000`, 8-byte aligned, `p_malloc`/`p_free`
- **Page allocator:** Bitmap at `0x310000`, 256 pages × 4 KB, `page_alloc`/`page_free`
- **Heap allocator:** Free-list with 8-byte size header, `heap_alloc`/`heap_free`/`kmalloc`/`kfree`
- **Buddy allocator:** Multi-order free-page tracking (orders 0–10), `buddy_alloc`/
  `buddy_free`/`buddy_free_pages` — manages physical pages above the heap
- **Slab allocator:** 4 size classes (16/32/64/128 bytes), each with a fixed slot
  table — `slab_alloc`/`slab_free`/`slab_free_count` — reduces fragmentation for
  small kernel objects

### 3.6 Virtual Memory
- **File:** `kernel/vm.fd`
- **Boot page tables:** PML4 at `0x70000`, PDPT at `0x71000` (identity-mapped)
- **Functions:** `vm_map(vaddr, paddr, flags)`, `vm_unmap(vaddr)` — splits 1 GB
  pages into 2 MB entries, writes PTEs, invokes `p_invlpg`
- **mmap/munmap:** `mmap_anon(size, prot)` allocates via buddy allocator and maps
  pages; `munmap(addr)` unmaps and frees
- **Protection flags:** `VM_PROT_READ`, `VM_PROT_WRITE`, `VM_PROT_NX`
- **Guard pages:** `vm_guard(vaddr)` maps an inaccessible page to catch overflows
- **vm_protect:** `vm_protect(vaddr, prot)` changes PTE permission bits on existing
  mappings

### 3.7 Process Management & Scheduling
- **Files:** `kernel/sched.fd`, `kernel/syscall.fd`
- **Process table:** 64 entries × 64 bytes at `0x160000`
  - Fields: pid, state, entry, pml4, parent_pid, priority, child_count, exit_code,
    pending_signals
- **States:** `PROC_FREE`, `PROC_READY`, `PROC_RUNNING`, `PROC_BLOCKED`,
  `PROC_ZOMBIE`, `PROC_STOPPED`
- **Process API:** `proc_init`, `proc_create`, `proc_find`, `proc_exit`,
  `proc_set_priority`, `proc_get_parent`, `proc_count`
- **Syscalls:** `sys_fork` (create child descriptor), `sys_wait` (reap zombie,
  return exit code), `sys_kill` (deliver signal), `sys_exec` (load + replace)
- **Signals:** `SIGHUP`, `SIGINT`, `SIGQUIT`, `SIGKILL`, `SIGTERM`, `SIGCHLD`,
  `SIGSTOP` — `sys_sigaction` sets handlers, `sig_deliver_pending` dispatches
  pending signals (SIGKILL/SIGSTOP force immediate effect; others check handler
  or apply default termination)
- **Priority scheduling:** `proc_next_by_priority` selects the runnable process
  with the lowest nice value (−20..19); `proc_nice` sets the current process level
- **Cooperative threads:** `kthread_create`/`kthread_yield`/`kthread_join`/
  `kthread_exit` — the shell loop calls `kthread_yield()` when ticks ≥ 20

### 3.8 Filesystem / VFS
- **File:** `kernel/vfs.fd`
- **FAT32:** Full read/write — BPB parsing, cluster-to-sector, FAT entry reading,
  cluster reads, directory/file lookup, file creation/deletion, `cmd_touch`/`cmd_rm`
- **tmpfs:** In-memory filesystem at `0x1C0000` — 64 entries × 48 bytes, data
  area at `0x1C1000` (~28 KB). Supports files and directories.
  - API: `tmpfs_init`, `tmpfs_find`, `tmpfs_create`, `tmpfs_mkdir`,
    `tmpfs_write`, `tmpfs_read`, `tmpfs_remove`
- **VFS layer:** Unified interface dispatching by path prefix:
  - `/tmp/...` → tmpfs
  - `/proc/...` → procfs
  - otherwise → FAT32 (disk)
  - API: `vfs_open`, `vfs_read`, `vfs_write`, `vfs_chdir`
- **procfs:** Synthetic files generated on demand:
  - `/proc/meminfo` — free page count from buddy allocator
  - `/proc/cpuinfo` — CPU type and core count
  - `/proc/uptime` — kernel tick count
- **Directory operations:** `cmd_mkdir`, `cmd_rmdir`, `cmd_pwd`, `vfs_chdir`
- **Current working directory:** 64-byte buffer at `0x6D8`

### 3.9 File Descriptor Table
- **File:** `kernel/syscall.fd`
- **Table:** 16 entries × 32 bytes at `0x190000`
- **API:** `fd_init`, `sys_open`, `sys_close`, `sys_read_fd`, `sys_dup2`
  (duplicates an FD to the lowest free slot ≥ start)

### 3.10 Pipes
- **File:** `kernel/syscall.fd`
- **Table:** At `0x180000`, `MAX_PIPES` entries
- **API:** `sys_pipe` (create), `sys_pipe_read` (read from pipe),
  `sys_pipe_write` (write to pipe)

### 3.11 Disk I/O (ATA/PIO)
- **File:** `kernel/ata.fd`
- **Controller:** Primary ATA (`0x1F0-0x1F7`)
- **Mode:** PIO (programmed I/O, no DMA)
- **Functions:** `ata_read_sector(lba, buf)`, `ata_write_sector(lba, buf)`
- **Block cache:** 8-sector LRU at `0x350000`

### 3.12 Networking
- **File:** `kernel/net.fd`
- **E1000 driver:** PCI discovery (vendor 0x8086, device 0x100E), MMIO via BAR0,
  MAC from EEPROM, TX/RX descriptor rings (16 each)
- **Ethernet:** Frame send/receive, dispatch by ethertype
- **ARP:** Request/reply with 16-entry cache
- **IPv4:** Packet construction with header checksum
- **ICMP:** Echo request/reply (real `ping`) with sent/recv/loss/RTT statistics
- **UDP:** Send + receive (`udp_handle` routes to bound sockets, feeds DHCP/DNS)
- **TCP:** 3-way handshake, data transfer, FIN handling, listen/accept
  - States: CLOSED, SYN_SENT, ESTABLISHED, CLOSE_WAIT, FIN_WAIT, LISTEN, SYN_RCVD
  - `tcp_listen`/`tcp_accept` — passive SYN handling, child socket creation,
    SYN-ACK, final ACK transition
  - 4 sockets max, 4 KB receive buffer each
- **DNS:** `dns_resolve` — builds A-record queries, sends to 10.0.2.3:53,
  parses responses with label compression support
- **DHCP:** `dhcp_dora` — full DORA exchange (DISCOVER → OFFER → REQUEST → ACK),
  parses yiaddr from replies
- **Socket API:** Unified wrapper at `0x1AF750` (8 entries × 16 bytes)
  - `sock_socket`/`sock_bind`/`sock_listen`/`sock_accept`/`sock_connect`/
    `sock_send`/`sock_recv`/`sock_close` — wraps TCP and UDP

### 3.13 Framebuffer
- **File:** `kernel/framebuffer.fd`
- **Metadata:** At `0x1B0000` (addr, width, height, bpp, pitch)
- **Font:** Built-in 8×16 bitmap font (96 characters)
- **Functions:** `fb_putpixel`, `fb_draw_char`, `fb_putc`, `fb_scroll`,
  `fb_clear_screen`, `fb_set_info`

### 3.14 SMP
- **File:** `kernel/smp.fd`
- **AP trampoline:** At physical `0x8000` (SIPI vector 0x08)
- **Per-CPU state:** At `0x1C0000` (16 CPUs × 64 bytes)
- **AP stacks:** At `0x1C1000` (4 KB per AP)
- **Boot sequence:** INIT-SIPI-SIPI via LAPIC ICR
- **Status:** BSP boots; AP1 startup times out (root cause unresolved)

### 3.15 Shell
- **File:** `kernel/shell.fd`
- **Input buffer:** Fixed-size array, character-by-character
- **Command matching:** `input_matches` (5-char), `input_matches8` (8-char),
  `input_prefix4`, `input_prefix8` (prefix matching for commands with arguments)
- **50+ commands** — see README for full list
- **Scripting:** Variables (`name=value`, `$name`), pipes (`cmd1 | cmd2`),
  redirects (`cmd > file`, `cmd >> file`)

### 3.16 Shell Scripting
- **File:** `kernel/shell_script.fd`
- **Variables:** 32 vars × 64 bytes at `0x1D0000`
- **Capture buffer:** 8 KB at `0x1D1000`
- **Pipe buffer:** 4 KB at `0x1D3000`
- **Capture flag:** At `0x1D5000`
- **History:** 16 entries × 128 bytes at `0x1D6000`

### 3.17 Capability System (Fractal Kernel Phase 1)
- **File:** `kernel/capability.fd`
- **Table:** 128 entries × 32 bytes at `0x1E0000`
- **Entry:** type(8), perms(8), base(8), size(8)
- **Types:** MMIO, MEMORY, DISK, NETWORK, CONSOLE, KEYBOARD, MESSAGE, IRQ
- **Permissions:** READ, WRITE, EXEC, SEND, RECV, GRANT
- **API:** `capability_create`, `capability_check`, `capability_grant`,
  `capability_revoke`, `capability_get_base/size/type/perms`
- **Root capabilities** created at boot: console, disk, network MMIO,
  keyboard, memory heap (all with READ+WRITE+GRANT)
- **Shell command:** `caps` — list all capabilities

### 3.18 Message Passing (Fractal Kernel Phase 2)
- **File:** `kernel/msg.fd`
- **Endpoints:** 8 ring buffers at `0x1E1000` (1 KB each, 15 messages)
- **Message:** 64 bytes — op(8) + len(8) + 48-byte payload
- **Operations:** OPEN, CLOSE, READ, WRITE, SEEK, STAT, REPLY, ERROR,
  PING, SHUTDOWN
- **API:** `msg_create_endpoint`, `msg_send`, `msg_recv`, `msg_pending`
- **Permission-gated** via CAP_TYPE_MESSAGE capabilities
- **Shell command:** `msg` — test send/recv round-trip

### 3.19 Capability-Gated Filesystem (Fractal Proof of Concept)
- **File:** `kernel/vfs.fd` (appended functions)
- **API:** `vfs_cap_read_file`, `vfs_cap_write_file`, `vfs_cap_list`
- **Pattern:** caller passes a DISK capability; functions check type +
  permission before delegating to existing FAT32 operations
- **Shell command:** `capfs` — grants a read-only child cap, tests that
  reads succeed and writes are denied, then revokes and tests denial

### 3.20 Capability-Gated Console (Fractal Kernel)
- **File:** `kernel/console.fd` (appended functions)
- **API:** `con_cap_putc`, `con_cap_putn`, `con_cap_clear`,
  `con_cap_input_get`, `con_cap_print_dec`, `con_cap_print_hex`
- **Pattern:** caller passes a CONSOLE capability; functions check type +
  permission (WRITE for output, READ for input) before delegating
- **Shell command:** `capcon` — grants a write-only child cap, tests that
  writes succeed and reads are denied, revokes, tests denial

### 3.21 Capability-Gated Network (Fractal Kernel)
- **File:** `kernel/net.fd` (appended functions)
- **API:** `net_cap_send_frame`, `net_cap_poll`, `net_cap_ping`,
  `net_cap_status`
- **Pattern:** caller passes a NETWORK or MMIO capability; functions
  check type + permission (WRITE for send/ping, READ for poll/status)
- **Shell command:** `capnet` — grants a read-only child cap, tests that
  status succeeds and send/ping are denied, revokes, tests denial

### 3.22 Message-Based Filesystem (Fractal Kernel)
- **File:** `kernel/msg.fd` (appended functions)
- **Protocol:** client sends READ/WRITE/STAT messages to a filesystem
  endpoint; server processes them and sends REPLY/ERROR back
- **API:** `msg_fs_read_request`, `msg_fs_write_request`,
  `msg_fs_stat_request`, `msg_fs_recv_reply`, `msg_fs_server`
- **Server:** `msg_fs_server(fs_cap, disk_cap)` — receives a message,
  delegates to `vfs_cap_read_file`/`vfs_cap_write_file`, sends reply
- **Shell command:** `msgfs` — creates a FS endpoint, sends a READ
  request, processes it server-side, receives the reply; then sends
  a WRITE request and processes that too. Full round-trip via messages.

## 4. Build System

### 4.1 Compile
```bash
# Using self-hosted compiler (preferred):
../p-lang/release/fides-c3.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin

# Using Rust bootstrap compiler:
../p-lang/target/release/fidesc.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin
```

### 4.2 ISO
```bash
make iso
# Uses grub-mkrescue to create build/fides-os.iso
```

### 4.3 QEMU
```bash
# Headless (serial only):
qemu-system-x86_64 -cdrom build/fides-os.iso -m 256 -serial stdio -no-reboot -display none

# With display:
qemu-system-x86_64 -cdrom build/fides-os.iso -m 256 -serial stdio -no-reboot -display sdl

# With test disk:
qemu-system-x86_64 -cdrom build/fides-os.iso -hda build/testdisk.img -boot d -m 256 -serial stdio
```

## 5. Compiler Support

### 5.1 Self-Hosted PE Backend (`compiler/pe.fd`)
Bare-metal stubs generated for `--boot` mode:
- `p_inb`, `p_outb`, `p_inw`, `p_outw` — I/O port access
- `p_hlt`, `p_cli`, `p_sti` — CPU control
- `p_lidt`, `p_idt_set_entry` — IDT management
- `p_lgdt`, `p_gdt_set_entry` — GDT management
- `p_enter_user_mode` — ring 3 transition via iretq
- `p_cr3_read/write`, `p_cr0_read/write` — MMU
- `p_mem_read8/32/64`, `p_mem_write8/32/64` — Memory access
- `p_invlpg` — TLB invalidation
- `p_serial_init`, `p_serial_write` — Serial
- `p_malloc`, `p_free` — Heap (bump allocator in bare mode)

Boot trampoline features:
- 32-bit → 64-bit long mode switch
- GDT with kernel/user code/data segments + TSS
- IDT setup (auto-wires `irq1_handler` if present)
- PIC remap (IRQ0-15 → vectors 0x20-0x2F)
- TSS setup (rsp0=0x90000)
- Syscall handler (int 0x80, DPL=3)
- Page tables with user bit (ring 3 can access first 1GB)

### 5.2 Multi-Module Boot Mode
`emit_boot()` resolves `use` imports:
- Loads `.fd` files from disk relative to source path
- Registers imported modules with typechecker
- Merges all functions/structs/enums into one program
- Enables splitting the kernel into 30+ modules

## 6. Kernel Modules (kernel/*.fd)

The kernel is modular — `shell.fd` is the entry point that imports 30+
modules via `use` declarations. All modules compile under `--boot` mode
with bare-metal primitives (i64, port I/O, memory access).

| File | Status | Purpose |
|------|--------|---------|
| `shell.fd` | **ACTIVE** | Main entry + shell loop + command dispatch (50+ commands) |
| `vga.fd` | **ACTIVE** | VGA text mode output (0xB8000) |
| `serial.fd` | **ACTIVE** | COM1 serial output (0x3F8) |
| `console.fd` | **ACTIVE** | Console bridge + input buffer + print utils + capture |
| `isr.fd` | **ACTIVE** | Interrupt service routines (exceptions + IRQ0/IRQ12) |
| `keyboard.fd` | **ACTIVE** | Interrupt-driven keyboard + scancode buffer |
| `kalloc.fd` | **ACTIVE** | Heap + buddy page-frame allocator + slab allocator |
| `vm.fd` | **ACTIVE** | Virtual memory, page mapping, mmap/munmap, NX/guard pages |
| `sched.fd` | **ACTIVE** | Process table + cooperative scheduler + priority scheduling |
| `syscall.fd` | **ACTIVE** | Syscall interface, process descriptors, signals, FD table, pipes |
| `ata.fd` | **ACTIVE** | ATA/PIO disk driver (LBA28) |
| `vfs.fd` | **ACTIVE** | FAT32 + VFS layer + tmpfs + procfs |
| `initrd.fd` | **ACTIVE** | Initrd ramdisk loading + hierarchical file access |
| `pci.fd` | **ACTIVE** | PCI bus enumeration |
| `acpi.fd` | **ACTIVE** | ACPI power management |
| `mouse.fd` | **ACTIVE** | PS/2 mouse driver |
| `framebuffer.fd` | **ACTIVE** | VBE framebuffer + 8×16 bitmap font + text rendering |
| `apic.fd` | **ACTIVE** | APIC interrupt controller |
| `elf.fd` | **ACTIVE** | ELF executable loader |
| `net.fd` | **ACTIVE** | E1000 + ARP/IPv4/ICMP/UDP/TCP + DNS + DHCP + socket API |
| `dma.fd` | **ACTIVE** | ATA DMA (bus-master) info |
| `shell_script.fd` | **ACTIVE** | Shell variables, pipes, redirects |
| `smp.fd` | **ACTIVE** | SMP boot via LAPIC IPIs + AP trampoline |
| `audio.fd` | **ACTIVE** | PC speaker + audio tones |
| `graphics.fd` | **ACTIVE** | Graphics primitives |
| `gamepad.fd` | **ACTIVE** | Gamepad input |
| `gameloop.fd` | **ACTIVE** | Game loop + snake game |
| `gpio.fd` | **ACTIVE** | GPIO support |
| `button.fd` | **ACTIVE** | Button input |
| `arm_boot.fd` | **ACTIVE** | ARM Cortex-M target info |
| `capability.fd` | **ACTIVE** | Capability table (fractal kernel phase 1) |
| `msg.fd` | **ACTIVE** | Message passing endpoints (fractal kernel phase 2) |

## 7. Repository Boundaries

```
  p-lang/          ── Fides language + compiler (NOT the OS)
    compiler/*.fd    Self-hosted compiler (52 modules)
    src/*.rs         Rust bootstrap reference
    release/         fides-c3.exe (self-hosted binary)

  fides-os/        ── The operating system (THIS repo)
    kernel/*.fd      Kernel source (30+ modules)
    docs/            Architecture + roadmap
    build/           Output (kernel.bin, .iso)
```

## 8. Known Limitations & Restrictions

### PE Backend Interrupt Handler Code Layout Bug (CRITICAL BLOCKER)

The Fides PE backend has a code layout sensitivity specific to **interrupt
handlers**: any code change to an `@interrupt` function triggers an invalid
opcode (#UD) or page fault crash, even when the kernel binary size stays
the same.

This blocks:
- Preemptive scheduler (quantum-based context switch in the timer handler)
- AHCI/SATA DMA driver (requires interrupt handler modifications)
- Per-CPU GDT/TSS validation (requires interrupt handler modifications)

**Workaround:** The timer handler is frozen at its current code layout. The
cooperative scheduler uses the shell loop to check the tick counter and call
`kthread_yield()` instead of modifying the timer handler.

### SMP AP Startup

The `smp` command no longer crashes (fixed via `#UD` handler), but AP1
startup still fails:
- BSP APIC ID: 0, CPU count: 1
- AP1 boot sequence times out
- Root cause unresolved

### Cooperative Scheduling

The scheduler is cooperative, not preemptive:
- The shell loop checks `timer_get_ticks()` and calls `kthread_yield()`
  when ticks ≥ 20
- `kthread_yield()` resets the tick counter
- Full timer-driven register/context switching is NOT implemented
- True preemption requires fixing the PE backend interrupt handler bug

### Self-Hosted Compiler Non-Determinism

The self-hosted compiler (`fides-c3.exe`) occasionally fails to resolve the
`con_puts` builtin used by `arm_boot.fd`/`button.fd`, producing spurious
type errors. A retry succeeds. This does not affect the generated binary.

### No Real Hardware Testing

All testing is done in QEMU. No real hardware validation has been performed.
