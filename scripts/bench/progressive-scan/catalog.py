#!/usr/bin/env python3
"""Bounded Darwin catalog probe, no private fsgetpath dependency.

Returns volume records keyed by (parentID,name), preserving hardlink aliases.
Does NOT promise a folder's recursive size, an atomic snapshot, or GUI results.
"""
import ctypes as C
import errno
import os
import struct
import time


class Attr(C.Structure):
    _fields_ = [("count", C.c_uint16), ("reserved", C.c_uint16)] + [
        (key, C.c_uint32) for key in ("common", "vol", "directory", "file", "fork")]


class Timeval(C.Structure):
    _fields_ = [("seconds", C.c_long), ("microseconds", C.c_int)]


class Search(C.Structure):
    _fields_ = [("attrs", C.POINTER(Attr)), ("buffer", C.c_void_p),
                ("buffer_size", C.c_size_t), ("max_matches", C.c_ulong),
                ("limit", Timeval), ("lower", C.c_void_p), ("lower_size", C.c_size_t),
                ("upper", C.c_void_p), ("upper_size", C.c_size_t), ("criteria", Attr)]


class CatalogFailure(RuntimeError):
    pass


def scan(volume, timeout=15.0, max_entries=2_000_000):
    """Full volume only. Fail explicitly on catalog mutation; caller decides retry."""
    lib = C.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    lib.searchfs.argtypes = [C.c_char_p, C.POINTER(Search), C.POINTER(C.c_ulong),
                            C.c_uint, C.c_uint, C.c_void_p]
    lib.searchfs.restype = C.c_int
    lib.getattrlist.argtypes = [C.c_char_p, C.POINTER(Attr), C.c_void_p, C.c_size_t, C.c_uint]
    attrs = Attr(5, 0, 0, 0x80020000, 0, 0, 0)
    cap = C.create_string_buffer(128)
    if lib.getattrlist(os.fsencode(volume), C.byref(attrs), cap, len(cap), 0):
        raise CatalogFailure(f"capability errno={C.get_errno()}")
    values = struct.unpack_from("=8I", cap.raw, 4)
    if not (values[5] & values[1] & 1):
        raise CatalogFailure("searchfs unsupported")
    # name, device, type, flags, fileID, parentID; physical allocation and data length.
    attrs = Attr(5, 0, 1 | 2 | 8 | 0x40000 | 0x02000000 | 0x04000000, 0, 0, 4 | 0x200, 0)
    buffer = C.create_string_buffer(256 * 1024)
    lower = C.create_string_buffer(struct.pack("=IiI", 9, 8, 1) + b"\0")
    upper = C.create_string_buffer(struct.pack("=IiI", 8, 8, 0))
    block = Search(C.pointer(attrs), C.addressof(buffer), len(buffer), 2048,
                   Timeval(0, 50000), C.addressof(lower), 13, C.addressof(upper), 12,
                   Attr(5, 0, 1, 0, 0, 0, 0))
    state = C.create_string_buffer(556)
    start = time.monotonic()
    records, samples = {}, []
    calls = 0
    options = 15 # START | PARTIAL_NAME | FILES | DIRS
    while True:
        if time.monotonic() - start > timeout:
            raise CatalogFailure(f"timeout after {calls} calls, {len(records)} records")
        count = C.c_ulong()
        C.set_errno(0)
        status = lib.searchfs(os.fsencode(volume), C.byref(block), C.byref(count), 0, options, state)
        error = C.get_errno() if status else 0
        calls += 1
        if error not in (0, errno.EAGAIN):
            raise CatalogFailure(f"searchfs errno={error}, calls={calls}, records={len(records)}")
        raw, offset = buffer.raw, 0
        for _ in range(count.value):
            if offset + 40 > len(raw):
                raise CatalogFailure("short record")
            length, name_offset, name_length, device, kind, flags, inode, parent = struct.unpack_from("=IiIiIIQQ", raw, offset)
            if length < 40 or length > len(raw) - offset:
                raise CatalogFailure("invalid record length")
            begin = offset + 4 + name_offset
            end = begin + name_length
            fixed = 56 if kind == 1 else 40
            if name_length < 2 or begin < offset + fixed or end > offset + length or raw[end-1] != 0:
                raise CatalogFailure("invalid name reference")
            name = raw[begin:end-1].decode("utf-8", errors="strict")
            if "/" in name or "\0" in name:
                raise CatalogFailure("invalid name")
            allocated, logical = struct.unpack_from("=qq", raw, offset+40) if kind == 1 else (0, 0)
            if allocated < 0 or logical < 0:
                raise CatalogFailure("negative size")
            key = (parent, name)
            record = dict(name=name, device=device, kind=kind, flags=flags, inode=inode,
                          parent=parent, allocated=allocated, logical=logical)
            if key in records:
                previous = records[key]
                raise CatalogFailure(f"duplicate catalog alias: same_inode={previous['inode']==inode}, "
                                     f"same_record={previous==record}, records={len(records)}, calls={calls}")
            records[key] = record
            offset += length
        samples.append(dict(elapsed_ms=(time.monotonic()-start)*1000, records=len(records)))
        if len(records) > max_entries:
            raise CatalogFailure("entry memory budget exceeded")
        if status == 0:
            break
        options &= ~1
    return dict(scan_complete_ms=(time.monotonic()-start)*1000, calls=calls,
                records=list(records.values()), samples=samples)


if __name__ == "__main__":
    import argparse
    import json
    parser = argparse.ArgumentParser()
    parser.add_argument("volume")
    parser.add_argument("--timeout", type=float, default=15)
    args = parser.parse_args()
    try:
        result = scan(args.volume, args.timeout)
        result["record_count"] = len(result.pop("records"))
        print(json.dumps(result))
    except CatalogFailure as exc:
        print(json.dumps(dict(error=str(exc))))
        raise SystemExit(2)
