#!/usr/bin/env python3
"""Minimal flattened device tree (DTB) writer, so that Spike runs without `dtc`.

Spike generates a DTS for its platform and pipes it through `dtc`. pipeline.py puts a
stub `dtc` first on Spike's PATH that ignores the DTS and returns this blob instead.
The blob describes one rv32 hart (hart id, ISA, PMP, MMU type) and the memory, and no
CLINT, PLIC or UART, so the test programs see no timer and no interrupt sources.

usage: mkdtb.py OUT.dtb ISA MEM_BASE MEM_SIZE
"""
import struct
import sys

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_END = 1, 2, 3, 9


def u32s(*vals):
    return b"".join(struct.pack(">I", v) for v in vals)


def string(s):
    return s.encode() + b"\0"


def build(isa, mem_base, mem_size):
    # (name, [props], [children]); prop = (name, bytes)
    tree = ("", [
        ("#address-cells", u32s(2)),
        ("#size-cells", u32s(2)),
        ("compatible", string("ucbbar,spike-bare-dev")),
        ("model", string("ucbbar,spike-bare")),
    ], [
        ("cpus", [
            ("#address-cells", u32s(1)),
            ("#size-cells", u32s(0)),
            ("timebase-frequency", u32s(10000000)),
        ], [
            ("cpu@0", [
                ("device_type", string("cpu")),
                ("reg", u32s(0)),
                ("status", string("okay")),
                ("compatible", string("riscv")),
                ("riscv,isa", string(isa)),
                ("mmu-type", string("riscv,sv32")),
                ("riscv,pmpregions", u32s(16)),
                ("riscv,pmpgranularity", u32s(4)),
                ("clock-frequency", u32s(1000000000)),
            ], [
                ("interrupt-controller", [
                    ("#address-cells", u32s(2)),
                    ("#interrupt-cells", u32s(1)),
                    ("interrupt-controller", b""),
                    ("compatible", string("riscv,cpu-intc")),
                ], []),
            ]),
        ]),
        ("memory@%x" % mem_base, [
            ("device_type", string("memory")),
            ("reg", u32s(0, mem_base, 0, mem_size)),
        ], []),
        ("htif", [("compatible", string("ucb,htif0"))], []),
    ])

    strings = bytearray()
    str_off = {}

    def stroff(name):
        if name not in str_off:
            str_off[name] = len(strings)
            strings.extend(string(name))
        return str_off[name]

    struct_blk = bytearray()

    def pad4(b):
        while len(b) % 4:
            b.append(0)

    def emit(node):
        name, props, children = node
        struct_blk.extend(u32s(FDT_BEGIN_NODE))
        struct_blk.extend(string(name))
        pad4(struct_blk)
        for pname, val in props:
            struct_blk.extend(u32s(FDT_PROP, len(val), stroff(pname)))
            struct_blk.extend(val)
            pad4(struct_blk)
        for c in children:
            emit(c)
        struct_blk.extend(u32s(FDT_END_NODE))

    emit(tree)
    struct_blk.extend(u32s(FDT_END))

    hdr_size = 40
    rsv_off = (hdr_size + 7) & ~7
    rsv = struct.pack(">QQ", 0, 0)
    struct_off = rsv_off + len(rsv)
    strings_off = struct_off + len(struct_blk)
    total = strings_off + len(strings)
    hdr = struct.pack(">10I", 0xD00DFEED, total, struct_off, strings_off, rsv_off,
                      17, 16, 0, len(strings), len(struct_blk))
    blob = bytearray(hdr)
    blob.extend(b"\0" * (rsv_off - len(blob)))
    blob.extend(rsv)
    blob.extend(struct_blk)
    blob.extend(strings)
    return bytes(blob)


if __name__ == "__main__":
    out, isa, base, size = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0)
    with open(out, "wb") as f:
        f.write(build(isa, base, size))
