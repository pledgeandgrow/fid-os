# Fides OS — Roadmap

> What's done, what's next, and what's hard.

## Status Summary

| # | Goal | Status |
|---|------|--------|
| 1 | Shell commands (echo, mem, info, time, poweroff) | ✅ Done |
| 2 | Interrupt-driven keyboard (IDT, PIC, IRQ1) | ✅ Done |
| 3 | Memory management (p_malloc/p_free heap) | ✅ Done |
| 4 | Port bare-metal stubs to self-hosted compiler | ✅ Done |
| 5 | Multi-module kernel linking | ✅ Done |
| 6 | Filesystem / disk I/O (ATA/PIO) | ✅ Done |
| 7 | User-mode program loading | ✅ Done |
| 8 | Modular kernel (shell.fd split into 30+ modules) | ✅ Done |
| 9 | E1000 network driver + TCP/IP stack | ✅ Done |
| 10 | Graphical framebuffer text rendering | ✅ Done |
| 11 | SMP boot via LAPIC IPIs | ✅ Done |
| 12 | Shell scripting (pipes, redirects, variables) | ✅ Done |
| 13 | MMIO page mapping (LAPIC + E1000) | ✅ Done |
| 14 | Multiboot2 info parsing + framebuffer | ✅ Done |
| 15 | Kernel panic register dump + stack trace | ✅ Done |
| 16 | LAPIC timer (enable/disable/count) | ✅ Done |
| 17 | Kernel threads (create/yield/join/exit) | ✅ Done |
| 18 | Spinlocks (atomic xchg) | ✅ Done |
| 19 | FAT32 write support (create/delete files) | ✅ Done |
| 20 | Initrd directory tree (hierarchical paths) | ✅ Done |
| 21 | Disk block cache (8-sector LRU) | ✅ Done |
| 22 | DHCP client (DISCOVER) | ✅ Done |
| 23 | UDP socket API (create/send/close) | ✅ Done |
| 24 | ICMP ping statistics (sent/recv/loss/RTT) | ✅ Done |
| 25 | ARP table management (arp command) | ✅ Done |
| 26 | Shell history (up/down arrow recall) | ✅ Done |
| 27 | Shell tab completion | ✅ Done |
| 28 | PS/2 mouse cursor (absolute position + framebuffer) | ✅ Done |
| 29 | Syscall expansion (open/close + existing) | ✅ Done |
| 30 | Buddy page-frame allocator | ✅ Done |
| 31 | Slab allocator (4 size classes) | ✅ Done |
| 32 | mmap / munmap (anonymous mapping) | ✅ Done |
| 33 | Memory protection (NX bit, guard pages) | ✅ Done |
| 34 | Process descriptors (PID, state, priority, parent, children) | ✅ Done |
| 35 | fork() / wait() / kill() | ✅ Done |
| 36 | Signals (SIGTERM, SIGKILL, SIGINT, SIGCHLD, SIGSTOP, handlers) | ✅ Done |
| 37 | Priority scheduling (nice levels −20..19) | ✅ Done |
| 38 | VFS layer (unified interface for tmpfs/procfs/FAT32) | ✅ Done |
| 39 | Directory operations (mkdir, rmdir, chdir, pwd) | ✅ Done |
| 40 | tmpfs / ramdisk (in-memory filesystem) | ✅ Done |
| 41 | procfs (/proc/meminfo, /proc/cpuinfo, /proc/uptime) | ✅ Done |
| 42 | FD table duplication (dup / dup2) | ✅ Done |
| 43 | TCP listen / accept (passive server-side) | ✅ Done |
| 44 | DNS resolver (A-record query + response parsing) | ✅ Done |
| 45 | DHCP full DORA (DISCOVER → OFFER → REQUEST → ACK) | ✅ Done |
| 46 | Socket API (socket, bind, listen, accept, connect, send, recv, close) | ✅ Done |
| 47 | UDP receive handler (route to bound sockets) | ✅ Done |
| 48 | Pipe read/write syscalls | ✅ Done |
| 49 | 15 new shell commands (buddy, slab, mmap, procs, nice, kill, fork, tmpfs, mkdir, rmdir, tmpwrite, tmpread, pwd, cd, dns, dhcpd, listen) | ✅ Done |
| 50 | Preemptive scheduler | ⚠ Cooperative only (PE backend bug) |
| 51 | Per-CPU GDT + TSS | ⚠ Needs working SMP |
| 52 | AHCI/SATA driver | ⚠ Needs PCI DMA |
| 53 | Keyboard scancode set 2 | ✅ 0xE0 handling works (addition not OR) |
| 54 | SMP AP startup fix | ⚠ AP1 times out (root cause unresolved) |

---

## Done

### 1. Shell Commands (original 12)
- `help` — list all commands
- `clear` — clear VGA screen
- `echo <text>` — print text back
- `mem` — show memory map (kernel, VGA, stack, heap)
- `info` — system info (arch, boot, display, input, serial)
- `time` — read CMOS RTC, show HH:MM:SS
- `reboot` — restart system
- `poweroff` — ACPI shutdown
- `malloc` — test heap allocation
- `disk` — read disk sector 0 via ATA/PIO
- `run` — load & run user program in ring 3
- `halt` — stop CPU

### 2. Interrupt-Driven Keyboard
- Boot trampoline auto-wires `irq1_handler` to IDT vector 0x21
- PIC remapped (IRQ0-15 → vectors 0x20-0x2F)
- IRQ1 unmasked, all other IRQs masked
- Scancode circular buffer at 0x600 (16 entries)
- `kbd_read_scancode()` uses `hlt` to sleep until key press
- CPU no longer busy-waits — sleeps until interrupt

### 3. Memory Management (bump allocator)
- Bare-metal bump allocator in PE backend
- Heap at `0x300000`, 8-byte aligned
- `p_malloc(size)` returns pointer, `p_free(ptr)` is no-op
- Ported to both Rust (`src/pe.rs`) and self-hosted (`compiler/pe.fd`)

### 4. Port to Self-Hosted Compiler
- `p_outw`, `p_inw` — 16-bit I/O port access
- `p_malloc`, `p_free` — bare-metal heap
- `p_hlt` — fixed to not disable interrupts
- All stubs added to `compiler/pe.fd`

### 5. Multi-Module Kernel Linking
- `emit_boot()` now resolves `use` imports
- Loads `.fd` files from disk
- Merges modules into single program
- Verified with `vga_test.fd` + `vga_helper.fd`

### 6. Filesystem / Disk I/O
- `ata_read_sector(lba, buf)` — full ATA/PIO read
- `p_inw` stub for 16-bit port reads
- `disk` command reads sector 0, shows hex + MBR signature
- Tested with QEMU + test disk image

### 7. User-Mode Program Loading
- GDT with user code (0x18/0x1B) and user data (0x20/0x23) segments
- TSS at 0x4000 with rsp0=0x90000 (kernel stack for syscalls)
- `p_enter_user_mode(entry, stack)` — iretq to ring 3
- Syscall handler (int 0x80, DPL=3) — modifies iret frame to return to kernel
- `user_program_done()` — called when user program exits
- `run` command loads user program from disk sector 1 to 0x10000
- User stack at 0x12000
- Page tables have user bit set (ring 3 can access first 1GB)

### 8. Modular Kernel
- `shell.fd` split from 3019-line monolith into 30+ module files
- All modules compile under `--boot` mode with bare-metal primitives
- Multi-module `--boot` linking verified: ~760 KB boot-ready Multiboot2 image
- Module dependency graph resolved (no circular imports)

### 9. E1000 Network Driver + TCP/IP Stack
- E1000 PCI discovery (vendor 0x8086, device 0x100E)
- MMIO register access via BAR0
- MAC address read from EEPROM
- TX/RX descriptor rings (16 descriptors each)
- Ethernet frame send/receive
- ARP request/reply with cache (16 entries)
- IPv4 packet construction with checksum
- ICMP echo request/reply (real `ping`)
- UDP send
- TCP send (SYN/ACK/FIN flags)
- `net` command shows E1000 status, MAC, IP
- `ping` command sends real ICMP echo, waits for reply

### 10. Graphical Framebuffer Text Rendering
- Framebuffer metadata at 0x1B0000 (addr, width, height, bpp, pitch)
- Built-in 8x16 bitmap font (96 characters, programmatically generated)
- `fb_putpixel(x, y, color)`, `fb_draw_char(x, y, c, fg, bg)`, `fb_putc(c)`
- `fb_scroll()`, `fb_clear_screen()`, `fb_set_info(addr, w, h, bpp, pitch)`
- `fb` command shows framebuffer status

### 11. SMP Boot via LAPIC IPIs
- AP trampoline at physical 0x8000 (SIPI vector 0x08)
- Trampoline: real mode → 32-bit → 64-bit long mode transition
- Reuses BSP page tables (PML4 at 0x70000)
- Per-CPU state at 0x1C0000 (16 CPUs × 64 bytes)
- INIT-SIPI-SIPI sequence per Intel spec
- `smp` command boots AP 1, shows per-CPU status

### 12. Shell Scripting
- Variable storage at 0x1D0000 (32 variables × 64 bytes)
- Variable assignment: `name=value`
- Variable expansion: `$name` → value
- `vars` command shows all variables
- Pipe support: `cmd1 | cmd2`
- Redirect support: `cmd > file` and `cmd >> file`
- Output capture buffer at 0x1D1000 (8KB)

---

## Done (Goals 30–49 — Memory, Process, VFS, Networking)

### 30. Buddy Page-Frame Allocator
- **File:** `kernel/kalloc.fd`
- Multi-order free-page tracking (orders 0–10, 4 KB to 4 MB)
- `buddy_alloc(order)` — allocate 2^order pages
- `buddy_free(page, order)` — free pages and coalesce buddies
- `buddy_free_pages()` — query free page count
- Manages physical pages above the existing heap region
- `buddy` shell command shows free page count

### 31. Slab Allocator
- **File:** `kernel/kalloc.fd`
- 4 size classes: 16, 32, 64, 128 bytes
- Each class has a fixed slot table with in-use tracking
- `slab_alloc(size)` — allocate from appropriate class
- `slab_free(ptr)` — return slot to free list
- `slab_free_count(class)` — query free slots per class
- `slab` shell command shows per-class stats
- Reduces fragmentation for small kernel objects

### 32. mmap / munmap
- **File:** `kernel/vm.fd`
- `mmap_anon(size, prot)` — allocate via buddy allocator, map pages
  with specified protection flags
- `munmap(addr)` — unmap pages and free physical frames
- Uses boot page tables at 0x70000/0x71000
- `mmap` shell command tests anonymous mapping + read-back + unmap

### 33. Memory Protection (NX, Guard Pages)
- **File:** `kernel/vm.fd`
- Protection flags: `VM_PROT_READ`, `VM_PROT_WRITE`, `VM_PROT_NX`
- `vm_protect(vaddr, prot)` — change PTE permission bits on existing mappings
- `vm_guard(vaddr)` — map an inaccessible page to catch stack/buffer overflows
- Page-table entry bit manipulation with `p_invlpg` for TLB flush

### 34. Process Descriptors
- **File:** `kernel/syscall.fd`
- 64 entries × 64 bytes at `0x160000`
- Fields: pid, state, entry, pml4, parent_pid, priority, child_count,
  exit_code, pending_signals
- States: FREE, READY, RUNNING, BLOCKED, ZOMBIE, STOPPED
- `proc_init`, `proc_create`, `proc_find`, `proc_exit`, `proc_count`
- `procs` shell command shows full table with PID, state, priority, parent, entry

### 35. fork() / wait() / kill()
- **File:** `kernel/syscall.fd`
- `sys_fork()` — create child descriptor sharing parent's entry/pml4,
  inherit priority; parent gets child PID
- `sys_wait(pid)` — poll for zombie child, reap it, return encoded
  (pid << 16 | exit_code); `pid == -1` waits for any child
- `sys_kill(pid, sig)` — deliver signal to target process
- `fork` shell command tests descriptor creation

### 36. Signals
- **File:** `kernel/syscall.fd`
- Signal numbers: SIGHUP(1), SIGINT(2), SIGQUIT(3), SIGKILL(9), SIGTERM(15),
  SIGCHLD(17), SIGSTOP(19)
- `sys_sigaction(sig, handler)` — register a handler address
- `sig_deliver_pending()` — called before returning to a process; checks
  handler, applies default action if none (terminate for SIGTERM/SIGINT/etc.)
- SIGKILL and SIGSTOP cannot be caught — force immediate effect
- Pending signals stored as bitmask in process descriptor
- `kill <pid> <sig>` shell command sends signals

### 37. Priority Scheduling
- **File:** `kernel/sched.fd`
- `proc_next_by_priority(current)` — select next READY process by lowest
  nice value (−20 highest .. 19 lowest); ties broken by table order
- `proc_nice(level)` / `proc_set_priority(pid, nice)` — set priority
- `nice <level>` shell command adjusts current process priority
- Integrates with the process descriptor table in syscall.fd

### 38. VFS Layer
- **File:** `kernel/vfs.fd`
- `vfs_open(path, len)` — dispatches by path prefix:
  - `/tmp/...` → tmpfs (returns entry index | 0x100)
  - `/proc/...` → procfs (returns file id | 0x300)
  - otherwise → FAT32 (returns cluster | 0x200)
- `vfs_read(handle, buf, max)` — reads from tmpfs, FAT32, or procfs
- `vfs_write(handle, data, len)` — writes to tmpfs
- `vfs_chdir(path, len)` — update CWD buffer at 0x6D8
- `vfs_init()` — initializes tmpfs + sets default CWD to "/"

### 39. Directory Operations
- **File:** `kernel/vfs.fd`
- `tmpfs_mkdir(name, len)` — create directory entry in tmpfs
- `tmpfs_remove(name, len)` — remove file or empty directory
- `cmd_mkdir`, `cmd_rmdir` — shell commands
- `cmd_pwd` — print working directory
- `vfs_chdir` — change directory (shell `cd` command)

### 40. tmpfs / Ramdisk
- **File:** `kernel/vfs.fd`
- Entry table at `0x1C0000` (64 entries × 48 bytes)
- Data area at `0x1C1000` (~28 KB, grows upward)
- Entry layout: in_use(1), type(1: file/dir), name(32), data_off(8), size(8)
- `tmpfs_init`, `tmpfs_find`, `tmpfs_create`, `tmpfs_write`, `tmpfs_read`
- `tmpfs` shell command lists all entries with type and size
- `tmpwrite <name> <text>` and `tmpread <name>` shell commands

### 41. procfs
- **File:** `kernel/vfs.fd`
- Synthetic files generated on demand into buffer at `0x1C8000`:
  - `/proc/meminfo` — free page count from buddy allocator
  - `/proc/cpuinfo` — CPU type (x86-64) and core count
  - `/proc/uptime` — kernel tick count
- `procfs_open(name, len)` — match filename, return file id | 0x300
- `procfs_read(file_id, buf, max)` — generate content into buffer

### 42. FD Table Duplication (dup / dup2)
- **File:** `kernel/syscall.fd`
- `sys_dup2(fd, start)` — copy FD table entry to lowest free slot ≥ start
- Copies all 32 bytes of the entry (in-use flag, file reference, offset)
- FD table at `0x190000` (16 entries × 32 bytes)

### 43. TCP Listen / Accept
- **File:** `kernel/net.fd`
- `tcp_listen(sid)` — mark socket as LISTEN state
- `tcp_accept(sid)` — poll for incoming connections; returns child socket id
- Passive SYN handling in `tcp_handle`:
  - On SYN to a LISTEN socket, allocate child socket, send SYN-ACK
  - Child enters SYN_RCVD state
  - On final ACK, child transitions to ESTABLISHED
  - Sets TCP_ACCEPT_FLAG + TCP_ACCEPT_SID for `tcp_accept` to return
- New states: `TCP_LISTEN`, `TCP_SYN_RCVD`
- `listen` shell command tests listen/accept on port 80

### 44. DNS Resolver
- **File:** `kernel/net.fd`
- `dns_resolve(name_addr, name_len)` — build A-record query, send to
  10.0.2.3:53 via UDP, parse response
- Query construction: 12-byte header + length-prefixed labels + type/class
- Response parsing: skips question section, reads first answer's RDATA
  (4-byte IPv4 address), handles label compression pointers
- `dns <hostname>` shell command resolves and prints IP

### 45. DHCP Full DORA
- **File:** `kernel/net.fd`
- `dhcp_dora()` — full DISCOVER → OFFER → REQUEST → ACK exchange
- `dhcp_build_packet(pkt, msg_type, requested_ip)` — constructs DHCP
  packets with op, htype, MAC, cookie, option 53 (message type),
  option 50 (requested IP), option 54 (server id)
- `dhcp_parse_reply()` — extracts yiaddr from OFFER/ACK
- Uses UDP broadcast (255.255.255.255:67→68)
- `dhcpd` shell command runs DORA and prints assigned IP

### 46. Socket API
- **File:** `kernel/net.fd`
- Unified wrapper at `0x1AF750` (8 entries × 16 bytes)
- Entry: type(4: TCP/UDP), sid(4), state(4), reserved(4)
- `sock_socket(type, port)` — create TCP or UDP socket
- `sock_bind(id, port)` — bind to local port
- `sock_listen(id)` / `sock_accept(id)` — TCP server
- `sock_connect(id, ip, port)` — TCP client
- `sock_send(id, data, len)` / `sock_recv(id, buf, max)` — data transfer
- `sock_close(id)` — close and free

### 47. UDP Receive Handler
- **File:** `kernel/net.fd`
- `udp_handle(buf, len, src_ip)` — dispatched from `eth_handle_frame`
  for IPv4 proto 17
- Parses src/dst port, payload length
- Stashes copy in generic UDP receive buffer (0x1AF800) for DHCP/DNS
- Routes payload to bound UDP socket by destination port

### 48. Pipe Read/Write Syscalls
- **File:** `kernel/syscall.fd`
- `sys_pipe_read(pipe_id, buf, len)` — read from pipe ring buffer
- `sys_pipe_write(pipe_id, buf, len)` — write to pipe ring buffer
- Pipe table at `0x180000`

### 49. New Shell Commands
- `buddy` — show buddy allocator free page count
- `slab` — show slab allocator per-class stats
- `mmap` — test anonymous mmap/munmap
- `procs` — full process table with priority
- `nice <level>` — set current process priority
- `kill <pid> <sig>` — send a signal
- `fork` — test fork (create child descriptor)
- `tmpfs` — list tmpfs entries
- `mkdir <name>` — create tmpfs directory
- `rmdir <name>` — remove tmpfs entry
- `tmpwrite <name> <text>` — write to tmpfs file
- `tmpread <name>` — read from tmpfs file
- `pwd` — print working directory
- `cd <path>` — change directory
- `dns <hostname>` — resolve hostname via DNS
- `dhcpd` — full DHCP DORA exchange
- `listen` — test TCP listen/accept

---

## Future Goals

### Compiler / Backend
- Stack frame support for local variables (stack-relative, not fixed addresses)
- Function pointer calls through vtable (driver dispatch, polymorphism)
- Proper struct-by-value passing in registers
- Inline assembly with clobber lists (safe interrupt handlers, atomic ops)
- Linker script support (custom sections, symbols, load addresses)
- Dead code elimination in boot mode (reduce kernel binary size)
- Position-independent code generation (ASLR, kernel modules)

### Memory Management
- Copy-on-write pages (for fork())
- Demand paging (load pages on fault, not all upfront)
- Swap space (page out to disk when memory is full)
- Memory-mapped files (mmap files directly into address space)
- Per-process address spaces (each process has own page tables)
- Heap defragmentation (compact heap, reduce fragmentation)
- OOM killer (graceful handling when memory is exhausted)
- Physical memory map from multiboot2 (use actual RAM size, not hardcoded)

### Process Management & Scheduling
- **Preemptive scheduler** — timer-driven context switch (blocked by PE bug #2)
- Process groups / sessions (job control, background processes)
- CPU affinity (pin processes to specific cores)
- Cgroups (resource limits per process group)
- Daemon processes (background services, init system)
- Loadable kernel modules (load .ko at runtime, not just boot-time)

### Filesystem
- ext2/ext4 read/write (Linux filesystem compatibility)
- ISO9660 (read from CD/DVD)
- initramfs / cpio (load initial filesystem from boot)
- Symlinks / hardlinks
- File permissions (owner, group, rwx bits)
- File locking (advisory and mandatory locks)
- Mount/unmount (mount filesystems at runtime)
- Sysfs (/sys for device/hardware info)

### Storage Drivers
- **AHCI/SATA driver** — DMA, faster I/O (blocked by PE bug #2)
- NVMe driver (PCIe SSDs, queue-based I/O)
- USB mass storage (USB flash drives)
- Partition table parsing (GPT, MBR partitions)
- DMA transfers (bus-mastering, reduce CPU overhead)
- Interrupt-driven I/O (instead of polling)
- RAID support (striping, mirroring)
- Disk encryption (LUKS, dm-crypt)

### Networking
- TCP retransmit and congestion control
- HTTP client (GET, POST, headers, chunked encoding)
- HTTP server (serve static files, basic routing)
- TLS/SSL (encrypted connections — big effort)
- IPv6 support (addressing, neighbor discovery)
- Routing table (static routes, default gateway)
- Network stack as kernel service (not just shell commands)
- Packet capture (tcpdump-like for debugging)
- Firewall (packet filtering rules)

### Graphics / GUI
- Framebuffer console (replace VGA as primary output)
- Graphics primitives (lines, rectangles, circles, bitmaps)
- Window manager (overlapping windows, drag, resize, close)
- Mouse cursor (bitmap cursor, click/hover/drag)
- GUI toolkit (buttons, text fields, menus, scrollbars)
- TrueType font rendering (scalable fonts, not just bitmap)
- Image display (BMP, PNG, JPEG decode)
- Screen resolution switching (VBE mode set)
- Double buffering (flicker-free rendering)
- GPU acceleration (if available via PCI)

### Input Devices
- USB keyboard/mouse (USB HID driver)
- Keyboard scancode set 2 (0xE0 extended keys — partially done)
- Multi-touch / trackpad (gesture support)
- Gamepad / joystick (for gaming use cases)

### Audio
- PC speaker (beep, simple tones)
- Sound Blaster 16 (PCM playback, basic audio)
- Intel HD Audio (modern audio codec, PCI)
- Audio mixer (multiple streams, volume control)
- WAV playback (load and play .wav files)

### USB
- USB host controller (xHCI for USB 3.0)
- USB device enumeration (detect, configure devices)
- USB mass storage class (flash drives)
- USB HID class (keyboards, mice, gamepads)

### SMP / Multi-core
- **Fix AP startup** (AP1 times out — root cause unresolved)
- Per-CPU GDT/TSS (validated with working SMP)
- Per-CPU run queues (per-core scheduling)
- Spinlock optimization (ticket locks, MCS locks)
- RCU (read-copy-update for lock-free reads)
- CPU hotplug (bring cores online/offline)

### Security
- User/group permissions (uid, gid, permission checks)
- ASLR (address space layout randomization)
- Stack canaries (buffer overflow detection)
- Sandboxing (restrict process capabilities)
- Secure boot (UEFI secure boot, signed kernels)
- Kernel module signing (only load trusted modules)

### Boot / Firmware
- UEFI boot (boot without GRUB, native UEFI)
- ACPI full support (power states, device enumeration, AML)
- Bootloader (native Fides bootloader, no GRUB dependency)
- Boot configuration (grub.cfg or custom boot menu)

### Debugging / Profiling
- Kernel debugger (breakpoints, single-step, inspect memory)
- Kernel tracing (ftrace-like function tracing)
- Performance profiler (per-function timing, flame graphs)
- Core dumps (save process state on crash)
- Kernel log / dmesg (ring buffer, log levels)
- Hardware watchdog (auto-reboot on hang)

### Userland / Shell
- Shell history (up/down arrow — done but needs verification)
- Tab completion (file paths, command names)
- Core utilities (cat, ls, cp, mv, rm, mkdir, grep, sed, awk, head, tail, wc)
- Text editor (vi/nano-like in-kernel editor)
- Package manager (install/remove software packages)
- Init system (systemd-like service management)
- cron / at (scheduled tasks)
- User login (multi-user, authentication)

### Device Drivers
- PCI driver framework (auto-load drivers for detected devices)
- Driver registration (register/unregister drivers at runtime)
- Device tree (track all devices, their drivers, status)
- Hot-plug support (detect devices added at runtime)

### Real-time / Performance
- High-resolution timers (HPET, nanosecond precision)
- Real-time scheduling (SCHED_FIFO, SCHED_RR)
- Priority inheritance (prevent priority inversion)
- Latency measurement (worst-case latency tracking)
- Workqueue / tasklet (deferred work, bottom halves)

### Compatibility / POSIX
- POSIX syscall layer (open, read, write, close, stat, fork, exec, wait)
- libc port (minimal C library for user programs)
- ELF loader (load standard ELF executables — partially done)
- Cross-compilation (build Fides programs for the OS from host)
- Linux binary compatibility (run Linux ELF — ambitious)
