# Memory protection

- **Status:** design note only. Nothing is implemented, and a decision is open.
- **Plan item:** P6.5.

## Problem

Memory is one flat region with no protection. A guest can overwrite its own code: a stack that grows into `.text`, or a stray store, silently changes the program instead of faulting. For a sandbox this is fine, because the guest can only hurt itself. For debugging, and for consensus use where "the program crashed" should be distinguishable from "the program computed garbage", an early fault helps.

## Options

1. **W^X by region (recommended if anything is done).**
   - The host declares one executable, read-only region `[code_start, code_end)` and makes the rest data.
   - Stores into the code region fault with a new error, `WriteProtected`; fetches outside it fault with `ExecuteProtected`.
   - Cost: two range comparisons per store and per fetch. The decode cache can keep its validation as it is, because code could no longer change while protected.
   - Guest-visible: yes. It adds two fault kinds and new SEMANTICS.md rules, and digests do not change for programs that never violate the rules.
2. **A guard region below the stack.**
   - A configurable range (for example 4 KiB below the initial `sp`) faults on any access.
   - It catches stack overflow into the data and code below, at the cost of one range check per data access.
3. **Page-granular permissions** (an RWX bit per 4 KiB page, set by the host).
   - Most flexible. It costs a table lookup per access and a permission table of `mem_size / 4096` entries inside the VM state, which the state encoding would have to include.
4. **Do nothing** (the current state).
   - Document that memory is unprotected, which SEMANTICS.md now does.

## Considerations

- **Self-modifying code.** Every option has to decide what happens to it. It is legal RISC-V, and the `fence_i` compliance test exercises it. Option 1 has to make W^X opt-in, not the default.
- **Snapshots.** Any protection setting becomes part of the VM's configuration. Either it is part of the snapshot, which bumps the state encoding version, or it is a `CpuType` comptime option. A comptime option keeps snapshots unchanged but forces one setting per type.
- **Performance.** Measure with `zig build bench`: the per-store check is on the hot path.

## Recommendation

Keep the current behaviour (option 4) for 0.2.0. If protection is wanted, implement option 1 as an opt-in `CpuOptions` field: `.code_region = .{ start, end }` or `null`. That keeps the default semantics and digests unchanged.
