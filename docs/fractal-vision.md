# Fides OS — Fractal Kernel Vision

> A kernel where the same patterns repeat at every scale. Zoom in, zoom out —
> the structure is self-similar. A process is a kernel. A kernel is a process.

## Status

**Phase 1 (Capability system): IN PROGRESS**
- `kernel/cap.fd` — capability table with create/check/grant/revoke
- Root capabilities created at boot: console, disk, network MMIO, keyboard, memory heap
- `caps` shell command lists all capabilities
- Next: convert subsystems to use capabilities instead of hardcoded addresses

**Phase 2 (Message passing): IN PROGRESS**
- `kernel/msg.fd` — message endpoints with send/recv (ring buffer)
- `msg` shell command tests message passing
- Next: convert filesystem to message-based interface as proof of concept

**Phases 3-5: BLOCKED** by PE backend interrupt handler bug

## What is a Fractal Kernel?

A fractal kernel has **self-similarity at every level of scale**. The same
architectural patterns, interfaces, and security model apply whether you're
looking at the whole OS, a single subsystem, or a single process.

Like a mathematical fractal: zoom in or out, the structure looks the same.

## The Five Principles

### 1. Self-Similarity

The kernel, a subsystem, and a process all follow the same structure:
- A **capability space** — what they're allowed to access
- A **scheduler** — how they manage time
- A **memory manager** — how they manage space
- A **message interface** — how they communicate

A process can host its own "kernel" for its children. The same syscall
interface the kernel exposes to processes, a process can expose to its
children. Nest as deep as you want.

```
Kernel (root capability domain)
  ├── Process A (has capabilities: console, network)
  │     ├── Child A1 (has capabilities: console only)
  │     └── Child A2 (has capabilities: network only)
  ├── Process B (has capabilities: disk, filesystem)
  │     └── Child B1 (has capabilities: disk sector 0-100)
  └── Driver: E1000 (has capabilities: MMIO 0xFEB80000, IRQ)
```

### 2. Capability-Based Security

No ambient authority. No hardcoded addresses. A module or process can only
access what it was explicitly given.

- The E1000 driver gets a capability to MMIO range 0xFEB80000
- The filesystem gets a capability to disk sectors 0-1000
- The shell gets a capability to the console
- A process gets capabilities from its parent at fork time

**No global state.** The current 80+ hardcoded addresses in the architecture
doc are the anti-pattern. Each capability domain manages its own resources.

### 3. Uniform Message Passing

The same protocol for communication at every level:
- Kernel ↔ driver
- Driver ↔ driver
- Process ↔ process
- Process ↔ kernel
- Parent process ↔ child process

Not direct function calls. A message has: sender capability, receiver
capability, operation, payload. The protocol doesn't change with scale —
that's what makes it fractal.

### 4. Recursive Composability

A process can be a "kernel" for its children:
- It can schedule them (cooperative or preemptive)
- It can give them capabilities (subset of its own)
- It can isolate them (separate address space or capability-restricted)
- It can receive their messages and route them

The syscall interface is the same at every level:
```
fork()      → create child capability domain
exec()      → load code into a domain
send()      → send a message to a capability
recv()      → receive a message on a capability
map()       → map memory within your domain
unmap()     → unmap memory within your domain
```

### 5. No Global State

Every level manages its own resources:
- Each capability domain has its own heap (not a global heap at 0x300000)
- Each process has its own page tables (not identity-mapped shared space)
- Each subsystem has its own state (not hardcoded at 0x160000, 0x190000, etc.)

The kernel bootstraps the root capability domain. Everything else is spawned
from it, with explicit capabilities passed down.

## Current Architecture vs. Fractal Ideal

| Principle | Current State | Gap |
|-----------|--------------|-----|
| Self-similarity | Flat modules with `use` imports — one level, no nesting | No recursive structure — can't host a kernel inside a process |
| Capability-based | 80+ hardcoded addresses — any module reads/writes any memory | No capability system — everything is ambient authority |
| Uniform messaging | Direct function calls (`con_putc`, `e1000_send_frame`) | No message-passing protocol — modules are statically linked |
| Recursive composability | `fork()` shares the same address space | No process can be a kernel for its children |
| No global state | Every address is hardcoded in architecture.md | The entire memory layout is global state |

## What the Current Architecture Actually Is

A **modular monolithic kernel** — modular in source (30+ `.fd` files),
monolithic in runtime (one address space, one binary, direct calls).

This is a legitimate design (Linux is this), but it's not fractal. The
modularity is a source-code organization, not a runtime architecture.

## Path to Fractal (Incremental)

This is a fundamental redesign, not a refactor. But it can be done
incrementally:

### Phase 1: Capability System (foundation)
- Define a capability type: `(resource_id, permissions)`
- Replace hardcoded addresses with capability lookups
- Start with the most exposed subsystems: network (E1000 MMIO), disk (ATA ports)
- A capability table per process, passed at fork time

### Phase 2: Message Passing (one subsystem as proof)
- Define a message protocol: `(sender_cap, receiver_cap, op, payload)`
- Convert ONE subsystem to message-passing (e.g., the filesystem)
- The shell sends a message to the FS capability instead of calling `vfs_open()` directly
- Prove the pattern works, then expand to other subsystems

### Phase 3: Per-Process Page Tables (isolation)
- Each process gets its own PML4 (not shared identity-mapped)
- `fork()` copies page tables (or creates new ones)
- The kernel maps itself into every process's address space (or uses separate ranges)
- Requires the PE backend interrupt handler bug to be fixed (for page fault handling)

### Phase 4: Recursive Processes (the fractal moment)
- A process can call `fork()` to create children
- Children get a subset of the parent's capabilities
- Children can call `fork()` to create grandchildren
- The syscall interface is the same at every level
- This is where it becomes fractal — the pattern repeats

### Phase 5: Driver Isolation (fully fractal)
- Drivers run in their own capability domains (not kernel space)
- Drivers communicate via message passing
- A crashed driver doesn't take down the kernel
- This is the microkernel end-state, but reached incrementally

## Blockers

1. **PE backend interrupt handler bug** — blocks preemptive scheduling and
   page fault handling, both required for per-process isolation
2. **Single address space** — everything is identity-mapped; per-process
   page tables require a fundamental memory model change
3. **No capability primitives in the language** — Fides would need capability
   types and message-passing primitives (or these are built in the kernel
   using existing i64 + memory primitives)

## Non-Goals

- **Not a microkernel** (initially) — microkernels put everything in user
  space. Fractal kernels can start monolithic and decompose incrementally.
- **Not a unikernel** — unikernels compile everything into one binary with
  no protection. Fractal kernels have isolation at every level.
- **Not an exokernel** — exokernels expose hardware directly. Fractal kernels
  abstract at every level, but the abstraction is the same at every scale.

## References

- **seL4** — capability-based microkernel with formal verification
- **Fuchsia/Zircon** — capability-based, message-passing kernel
- **Barrelfish** — multikernel (per-core kernels, message passing)
- **HelenOS** — capability-based, microkernel, hierarchical
