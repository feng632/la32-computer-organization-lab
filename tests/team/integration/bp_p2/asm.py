#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LA32R 微型汇编器（仅覆盖分支预测定向测试所需指令）

用途：本机没有交叉工具链，无法用 .S 生成 inst_ram.coe。
      本脚本把极小的汇编子集直接编码成 32 位机器字，供行为级指令 ROM 使用。

编码来源：全部从 func/obj/test.s 的真实反汇编样本逐位反推，并用 --selftest
          对样本做重新编码比对，不允许凭记忆填写 opcode。

用法：
    python asm.py --selftest              # 用课程反汇编样本自检编码
    python asm.py prog.s -o prog.hex      # 汇编成 $readmemh 可读的十六进制文件

汇编语法（每行一条，支持行尾 ; 注释）：
    label:
        addi.w rd, rj, imm12
        add.w  rd, rj, rk
        lu12i.w rd, imm20
        ori    rd, rj, imm12
        ld.w   rd, rj, imm12
        st.w   rd, rj, imm12
        beq    rj, rd, label          # 相等跳转
        bne    rj, rd, label
        b      label
        bl     label
        jirl   rd, rj, imm16
        csrrd  rd, csr
        csrwr  rd, csr
        csrxchg rd, rj, csr
        syscall [code]
        ertn
        li     rd, imm32      # 伪指令，展开为 lu12i.w + ori（能放下 12 位时只一条）
"""

import sys
import re

REG = {f"r{i}": i for i in range(32)}
REG.update({f"$r{i}": i for i in range(32)})

CSR = {
    "crmd": 0x00, "prmd": 0x01, "ecfg": 0x04, "estat": 0x05,
    "era": 0x06, "badv": 0x07, "eentry": 0x0c, "tid": 0x40,
    "tcfg": 0x41, "tval": 0x42, "ticlr": 0x44,
    "save0": 0x30, "save1": 0x31, "save2": 0x32, "save3": 0x33,
}


def r(tok):
    tok = tok.strip()
    if tok in REG:
        return REG[tok]
    raise ValueError(f"未知寄存器: {tok}")


def csr(tok):
    tok = tok.strip().lower()
    if tok in CSR:
        return CSR[tok]
    return int(tok, 0)


def s(imm, bits, what):
    v = int(imm, 0) if isinstance(imm, str) else int(imm)
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not (lo <= v <= hi):
        raise ValueError(f"{what} 越界: {v} 不在 [{lo},{hi}]")
    return v & ((1 << bits) - 1)


def enc_addi_w(rd, rj, imm):
    return (0x0A << 22) | (s(imm, 12, "addi.w imm") << 10) | (rj << 5) | rd


def enc_add_w(rd, rj, rk):
    return (0x20 << 15) | (rk << 10) | (rj << 5) | rd


def enc_lu12i_w(rd, imm):
    v = int(imm, 0) if isinstance(imm, str) else int(imm)
    if not (-(1 << 19) <= v <= (1 << 20) - 1):
        raise ValueError(f"lu12i.w imm20 越界: {v}")
    return (0x0A << 25) | ((v & 0xFFFFF) << 5) | rd


def enc_ori(rd, rj, imm):
    v = (int(imm, 0) if isinstance(imm, str) else int(imm)) & 0xFFF
    return (0x0E << 22) | (v << 10) | (rj << 5) | rd


def enc_ld_w(rd, rj, imm):
    return (0x0A2 << 22) | (s(imm, 12, "ld.w imm") << 10) | (rj << 5) | rd


def enc_st_w(rd, rj, imm):
    return (0x0A6 << 22) | (s(imm, 12, "st.w imm") << 10) | (rj << 5) | rd


def enc_beq(rj, rd, off):
    return (0x16 << 26) | (s(off, 16, "beq off") << 10) | (rj << 5) | rd


def enc_bne(rj, rd, off):
    return (0x17 << 26) | (s(off, 16, "bne off") << 10) | (rj << 5) | rd


def enc_b(off):
    return (0x14 << 26) | (s(off, 16, "b off") << 10)


def enc_bl(off):
    return (0x15 << 26) | (s(off, 16, "bl off") << 10)


def enc_jirl(rd, rj, off):
    return (0x13 << 26) | (s(off, 16, "jirl off") << 10) | (rj << 5) | rd


def enc_csr(rd, csr_num, rj):
    return (0x04 << 24) | ((csr_num & 0x3FFF) << 10) | (rj << 5) | rd


def enc_syscall(code=0):
    return (0x56 << 15) | (int(code, 0) & 0x7FFF)


def enc_ertn():
    return 0x06483800


def split_ops(text):
    return [p.strip() for p in text.split(",") if p.strip()]


BASE = 0x1C000000       # 课程程序起始地址
NOP = 0x02800000        # addi.w r0, r0, 0


def _org_index(tok):
    """把 .org 的绝对地址换算成指令序号"""
    v = int(tok, 0)
    if v < BASE or (v - BASE) % 4 != 0:
        raise ValueError(f".org 地址必须是 {BASE:#x} 起、4 字节对齐: {v:#x}")
    return (v - BASE) // 4


def assemble(text):
    """两遍：先定地址，再编码。返回 word 列表。"""
    lines = []
    for raw in text.splitlines():
        line = raw.split(";")[0].rstrip()
        if not line.strip():
            continue
        lines.append(line)

    labels = {}
    pc = 0
    for line in lines:
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*:\s*(.*)$", line)
        if m:
            labels[m.group(1)] = pc
            if not m.group(2).strip():
                continue
            line = "    " + m.group(2)
        st = line.strip()
        if st.startswith(".org"):
            pc = _org_index(st.split(None, 1)[1])
            continue
        mn = st.split()[0].lower()
        if mn == "li":
            pc += 2 if _li_needs_two(st) else 1
        elif mn == "la":
            pc += 2        # 绝对地址一定是 0x1cxxxxxx，必占两条
        else:
            pc += 1

    out = []
    pc = 0
    for line in lines:
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*:\s*(.*)$", line)
        if m:
            if not m.group(2).strip():
                continue
            line = "    " + m.group(2)
        st = line.strip()
        if st.startswith(".org"):
            tgt = _org_index(st.split(None, 1)[1])
            while pc < tgt:
                out.append(NOP)
                pc += 1
            continue
        parts = st.split(None, 1)
        mn = parts[0].lower()
        ops = split_ops(parts[1]) if len(parts) > 1 else []

        if mn in ("li", "la"):
            rd = r(ops[0])
            imm = BASE + _target(ops[1], labels) * 4 if mn == "la" else int(ops[1], 0)
            if 0 <= imm <= 0xFFF:
                out.append(enc_ori(rd, 0, imm)); pc += 1
            elif -(1 << 11) <= imm <= (1 << 11) - 1:
                out.append(enc_addi_w(rd, 0, imm)); pc += 1
            else:
                out.append(enc_lu12i_w(rd, (imm >> 12) & 0xFFFFF))
                out.append(enc_ori(rd, rd, imm & 0xFFF)); pc += 2
            continue

        # 带标签偏移的分支
        if mn in ("beq", "bne"):
            rj, rd = r(ops[0]), r(ops[1])
            tgt = _target(ops[2], labels)
            off = tgt - pc
            out.append(enc_beq(rj, rd, off) if mn == "beq" else enc_bne(rj, rd, off))
        elif mn == "b":
            out.append(enc_b(_target(ops[0], labels) - pc))
        elif mn == "bl":
            out.append(enc_bl(_target(ops[0], labels) - pc))
        elif mn == "jirl":
            out.append(enc_jirl(r(ops[0]), r(ops[1]), s(ops[2], 16, "jirl off")))
        elif mn == "addi.w":
            out.append(enc_addi_w(r(ops[0]), r(ops[1]), ops[2]))
        elif mn == "add.w":
            out.append(enc_add_w(r(ops[0]), r(ops[1]), r(ops[2])))
        elif mn == "lu12i.w":
            out.append(enc_lu12i_w(r(ops[0]), ops[1]))
        elif mn == "ori":
            out.append(enc_ori(r(ops[0]), r(ops[1]), ops[2]))
        elif mn == "ld.w":
            out.append(enc_ld_w(r(ops[0]), r(ops[1]), ops[2]))
        elif mn == "st.w":
            out.append(enc_st_w(r(ops[0]), r(ops[1]), ops[2]))
        elif mn == "csrrd":
            out.append(enc_csr(r(ops[0]), csr(ops[1]), 0))
        elif mn == "csrwr":
            out.append(enc_csr(r(ops[0]), csr(ops[1]), 1))
        elif mn == "csrxchg":
            out.append(enc_csr(r(ops[0]), csr(ops[2]), r(ops[1])))
        elif mn == "syscall":
            out.append(enc_syscall(ops[0] if ops else 0))
        elif mn == "ertn":
            out.append(enc_ertn())
        else:
            raise ValueError(f"不支持的指令: {mn}")
        pc += 1
    return out


def _target(tok, labels):
    tok = tok.strip()
    if tok in labels:
        return labels[tok]
    return int(tok, 0)


def _li_needs_two(line):
    ops = split_ops(line.strip().split(None, 1)[1])
    v = int(ops[1], 0)
    return not (-(1 << 11) <= v <= 0xFFF)


# ------------------------------------------------------------------ 自检
# 取自 func/obj/test.s 的真实反汇编样本：(hex, 汇编源)
SAMPLES = [
    ("02bffc0c", "addi.w r12, r0, -1"),
    ("028005ad", "addi.w r13, r13, 1"),
    ("02800000", "addi.w r0, r0, 0"),
    ("00104a2f", "add.w r15, r17, r18"),
    ("1500000c", "lu12i.w r12, 0x80000"),
    ("157f600e", "lu12i.w r14, 0xbfb00"),
    ("0380040c", "ori r12, r0, 0x1"),
    ("28800190", "ld.w r16, r12, 0"),
    ("298001c0", "st.w r0, r14, 0"),
    ("4c000020", "jirl r0, r1, 0"),
    ("0400180c", "csrrd r12, era"),
    ("0401102d", "csrwr r13, ticlr"),
    ("002b0000", "syscall 0"),
    ("06483800", "ertn"),
]


def selftest():
    bad = 0
    for hexs, src in SAMPLES:
        got = assemble(src)
        if len(got) != 1:
            print(f"  [FAIL] {src}: 展开成了 {len(got)} 条")
            bad += 1
            continue
        e = int(hexs, 16)
        if got[0] != e:
            print(f"  [FAIL] {src}: got {got[0]:08x} want {e:08x}")
            bad += 1
        else:
            print(f"  [PASS] {src:28s} = {e:08x}")
    # 分支用绝对地址核对：test.s 中 beq/bne/b 的样本
    print()
    tests = [
        (0x580079ac, "beq r13, r12, {t}", 0x1c00800c, 0x1c008084),
        (0x5c6fd36c, "bne r27, r12, {t}", 0x1c00808c, 0x1c00f05c),
        (0x50000400, "b {t}", 0x1c00f058, 0x1c00f05c),
        (0x54000400, "bl {t}", 0x1c02e714, 0x1c02e718),
    ]
    for want, tpl, pc, tgt in tests:
        src = tpl.format(t=hex(tgt))
        # 直接按绝对地址编码，模拟两遍汇编里的偏移计算
        mn = src.split()[0]
        if mn in ("beq", "bne"):
            ops = split_ops(src.split(None, 1)[1])
            off = (tgt - pc) // 4
            got = enc_beq(r(ops[0]), r(ops[1]), off) if mn == "beq" else enc_bne(r(ops[0]), r(ops[1]), off)
        elif mn == "b":
            got = enc_b((tgt - pc) // 4)
        else:
            got = enc_bl((tgt - pc) // 4)
        if got != want:
            print(f"  [FAIL] {mn} pc={pc:08x} -> {got:08x} want {want:08x}")
            bad += 1
        else:
            print(f"  [PASS] {mn:4s} pc={pc:08x} tgt={tgt:08x} off={(tgt-pc)//4:5d} = {want:08x}")
    print()
    print(f"自检结果: {'全部通过' if bad == 0 else f'{bad} 项失败'}")
    return 0 if bad == 0 else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_path = sys.argv[1]
    out_path = None
    if "-o" in sys.argv:
        out_path = sys.argv[sys.argv.index("-o") + 1]
    text = open(src_path, encoding="utf-8").read()
    words = assemble(text)
    lines = [f"{w:08x}" for w in words]
    if out_path:
        with open(out_path, "w", encoding="ascii", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print(f"已生成 {out_path}：{len(words)} 条指令")
    else:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
