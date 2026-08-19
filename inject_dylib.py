#!/usr/bin/env python3
"""
inject_dylib.py
向 Mach-O 64位可执行文件注入 LC_LOAD_DYLIB 命令

用法:
    python inject_dylib.py <binary_path> <dylib_name>

例如:
    python inject_dylib.py ./Chagee crack.dylib

原理:
    1. 解析 Mach-O header 和 load commands
    2. 移除 LC_CODE_SIGNATURE 命令
    3. 在 load commands 末尾添加 LC_LOAD_DYLIB
    4. 修正所有 segment 的 fileoff
    5. 修正 LC_SYMTAB / LC_DYSYMTAB 的偏移量
    6. 跳过代码签名数据本身
"""

import struct
import sys
import os

# Mach-O 常量
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_CODE_SIGNATURE = 0x1D
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B

def log(msg):
    print(f"[INJECT] {msg}")

def err(msg):
    print(f"[ERROR] {msg}")
    sys.exit(1)

def patch_macho(data, dylib_install_name):
    """向 Mach-O 注入 LC_LOAD_DYLIB，移除代码签名"""

    # 读取 header
    if len(data) < 32:
        err("File too small")
    magic = struct.unpack('<I', data[0:4])[0]
    if magic != MH_MAGIC_64:
        err(f"Not Mach-O 64 (magic=0x{magic:08X})")

    ncmds = struct.unpack('<I', data[16:20])[0]
    sizeofcmds = struct.unpack('<I', data[20:24])[0]
    header_size = 32

    log(f"ncmds={ncmds}, sizeofcmds={sizeofcmds}")

    # 解析 load commands
    cmds = []
    offset = header_size
    for i in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd = struct.unpack('<I', data[offset:offset+4])[0]
        cmdsize = struct.unpack('<I', data[offset+4:offset+8])[0]
        cmds.append({
            'cmd': cmd,
            'cmdsize': cmdsize,
            'offset': offset,
            'data': data[offset:offset+cmdsize]
        })
        offset += cmdsize

    old_cmds_end = header_size + sizeofcmds

    # 找 code signature
    cs_cmd = None
    for c in cmds:
        if c['cmd'] == LC_CODE_SIGNATURE:
            cs_cmd = c
            break

    cs_data_offset = 0
    cs_data_size = 0
    if cs_cmd:
        cs_data_offset = struct.unpack('<I', cs_cmd['data'][8:12])[0]
        cs_data_size = struct.unpack('<I', cs_cmd['data'][12:16])[0]
        log(f"Code signature: offset=0x{cs_data_offset:X}, size=0x{cs_data_size:X}")

    # 构造 LC_LOAD_DYLIB
    name_bytes = dylib_install_name.encode('ascii') + b'\x00'
    while len(name_bytes) % 8 != 0:
        name_bytes += b'\x00'
    dylib_cmd_size = 24 + len(name_bytes)
    new_cmd = struct.pack('<II', LC_LOAD_DYLIB, dylib_cmd_size)
    new_cmd += struct.pack('<IIII', 24, 2, 0x10000, 0x10000)
    new_cmd += name_bytes
    log(f"LC_LOAD_DYLIB: name='{dylib_install_name}', cmdsize={dylib_cmd_size}")

    # 构建 new_cmds_list：保留除 code signature 外的所有命令 + 新命令
    new_cmds_list = []
    for c in cmds:
        if c['cmd'] == LC_CODE_SIGNATURE:
            log(f"Removing LC_CODE_SIGNATURE (offset=0x{c['offset']:X}, size={c['cmdsize']})")
            continue
        new_cmds_list.append(c['data'])
    new_cmds_list.append(new_cmd)

    new_sizeofcmds = sum(len(c) for c in new_cmds_list)
    new_ncmds = len(new_cmds_list)
    cmds_growth = (header_size + new_sizeofcmds) - old_cmds_end
    log(f"New ncmds={new_ncmds}, sizeofcmds={new_sizeofcmds}, growth={cmds_growth}")

    # 构建新 header
    new_header = bytearray(data[0:32])
    struct.pack_into('<I', new_header, 16, new_ncmds)
    struct.pack_into('<I', new_header, 20, new_sizeofcmds)

    # 构建新 load commands
    new_cmds_data = bytearray()
    for c in new_cmds_list:
        new_cmds_data.extend(c)

    # 构建新 Mach-O
    new_macho = bytearray()
    new_macho.extend(new_header)
    new_macho.extend(new_cmds_data)

    # 复制中间数据和尾部数据（跳过 code signature 数据）
    if cs_data_offset > 0:
        new_macho.extend(data[old_cmds_end:cs_data_offset])
        cs_end = cs_data_offset + cs_data_size
        if cs_end < len(data):
            new_macho.extend(data[cs_end:])
    else:
        new_macho.extend(data[old_cmds_end:])

    # 修正 segment fileoff
    log("Patching segment offsets...")
    cmd_offset = header_size
    for c_data in new_cmds_list:
        if struct.unpack('<I', c_data[0:4])[0] == LC_SEGMENT_64:
            segname = c_data[8:24].rstrip(b'\x00').decode('ascii', errors='ignore')
            old_fileoff = struct.unpack('<Q', c_data[40:48])[0]
            old_filesize = struct.unpack('<Q', c_data[48:56])[0]

            if old_fileoff > 0:
                new_fileoff = old_fileoff + cmds_growth
                struct.pack_into('<Q', new_macho, cmd_offset + 40, new_fileoff)
            else:
                new_fileoff = old_fileoff
                if cmds_growth != 0:
                    new_filesize = old_filesize + cmds_growth
                    struct.pack_into('<Q', new_macho, cmd_offset + 48, new_filesize)
                    log(f"  {segname}: filesize 0x{old_filesize:X} -> 0x{new_filesize:X}")

            if segname == '__LINKEDIT' and cs_data_size > 0:
                new_filesize = old_filesize - cs_data_size
                struct.pack_into('<Q', new_macho, cmd_offset + 48, new_filesize)
                log(f"  {segname}: fileoff 0x{old_fileoff:X} -> 0x{new_fileoff:X}, filesize 0x{old_filesize:X} -> 0x{new_filesize:X}")
            else:
                log(f"  {segname}: fileoff 0x{old_fileoff:X} -> 0x{new_fileoff:X}")

        cmd_offset += len(c_data)

    # 修正 LC_SYMTAB / LC_DYSYMTAB
    cmd_offset = header_size
    for c_data in new_cmds_list:
        cmd_type = struct.unpack('<I', c_data[0:4])[0]
        if cmd_type == LC_SYMTAB:
            old_symoff = struct.unpack('<I', c_data[8:12])[0]
            old_stroff = struct.unpack('<I', c_data[16:20])[0]
            struct.pack_into('<I', new_macho, cmd_offset + 8, old_symoff + cmds_growth)
            struct.pack_into('<I', new_macho, cmd_offset + 16, old_stroff + cmds_growth)
            log(f"  LC_SYMTAB: symoff 0x{old_symoff:X} -> 0x{old_symoff + cmds_growth:X}")
        elif cmd_type == LC_DYSYMTAB:
            for off, name in [(56,'tocoff'),(64,'modtaboff'),(72,'extrefsymoff'),(80,'indirectsymoff'),(96,'extreloff'),(104,'locreloff')]:
                if off + 4 <= len(c_data):
                    val = struct.unpack('<I', c_data[off:off+4])[0]
                    if val > 0:
                        struct.pack_into('<I', new_macho, cmd_offset + off, val + cmds_growth)
        cmd_offset += len(c_data)

    log(f"Patched: {len(data)} -> {len(new_macho)} bytes")
    return bytes(new_macho)


def main():
    if len(sys.argv) < 3:
        print("Usage: python inject_dylib.py <binary> <dylib_name>")
        print("Example: python inject_dylib.py ./Chagee crack.dylib")
        sys.exit(1)

    binary_path = sys.argv[1]
    dylib_name = sys.argv[2]
    dylib_install_name = f"@executable_path/{dylib_name}"

    with open(binary_path, 'rb') as f:
        data = f.read()

    patched = patch_macho(data, dylib_install_name)

    with open(binary_path, 'wb') as f:
        f.write(patched)

    log(f"Done: {binary_path}")


if __name__ == '__main__':
    main()
