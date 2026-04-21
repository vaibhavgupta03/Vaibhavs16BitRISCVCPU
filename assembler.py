# assembler.py — full ISA assembler  (FIXED encoding)
#
# ══════════════════════════════════════════════════════════════════════
# Instruction encoding (all instructions are 2 words except NOP/MOV)
#
#  R-type  word1: [15:12]=0000 [11:8]=dest [7:4]=srcA [3:0]=srcB
#          word2: [3:0]=func   (upper 12 bits unused/zero)
#     FIX: srcB register now occupies [3:0] of word1 (was aliased with func).
#          func moved to word2[3:0] so all three register fields are distinct.
#
#  I-type  word1: [15:12]=0001 [11:8]=dest [7:4]=func  [3:0]=srcA
#          word2: 16-bit immediate
#     FIX: srcA register now in [3:0] of word1 (was 0); func stays in [7:4].
#          Decoder must read srcA_addr = instr[3:0] for I-type (not instr[7:4]).
#
#  LD      word1: [15:12]=0010 [11:8]=dest [7:4]=srcA  [3:0]=0
#          word2: offset (unchanged)
#
#  ST      word1: [15:12]=0011 [11:8]=rs   [7:4]=rb    [3:0]=0
#          word2: offset (unchanged)
#     NOTE: rs (data source) lives in [11:8]; CPU MEMORY stage must use
#           bank[d_dest] (not regB_data) as the value written to RAM.
#
#  BRANCH  word1: [15:12]=0100 [11:8]=cond [7:4]=srcA  [3:0]=srcB
#          word2: signed offset
#     FIX: cond field is no longer shifted left by 1.
#          Decoder reads branch_type = instr[10:8].
#
#  J       word1: [15:12]=0101 [11:0]=0
#          word2: signed offset  (unchanged)
#
#  JAL     word1: [15:12]=0110 [11:8]=dest [7:0]=0
#          word2: signed offset  (unchanged)
#
#  LUI     word1: [15:12]=0111 [11:8]=dest [7:0]=0
#          word2: 16-bit immediate  (unchanged)
#
#  NOP     single word: 0x0000
# ══════════════════════════════════════════════════════════════════════

REGS = {f'R{i}': i for i in range(16)}
REGS.update({'ZERO':0,'RA':1,'SP':2,'GP':3,'T0':4,'T1':5,
             'T2':6,'S0':7,'S1':8,'A0':9,'A1':10,
             'A2':11,'A3':12,'S2':13,'S3':14,'S4':15})

GRP_R   = 0b0000
GRP_I   = 0b0001
GRP_LD  = 0b0010
GRP_ST  = 0b0011
GRP_BR  = 0b0100
GRP_J   = 0b0101
GRP_JAL = 0b0110
GRP_LUI = 0b0111

R_FUNC = {
    'ADD':0,'SUB':1,'AND':2,'OR':3,'XOR':4,
    'SLL':5,'SRL':6,'SRA':7,'SLT':8,'SLTU':9,
    'MUL':10,'NOR':12,'XNOR':13,'MIN':14,'MAX':15
}
I_FUNC = {
    'ADDI':0,'SUBI':1,'ANDI':2,'ORI':3,'XORI':4,
    'SLLI':5,'SRLI':6,'SRAI':7,'SLTI':8,'SLTIU':9
}
BRANCH_COND = {
    'BEQ':0,'BNE':1,'BLT':2,'BGE':3,'BLTU':4,'BGEU':5
}

def reg(s):
    s = s.strip().rstrip(',').upper()
    if s not in REGS:
        raise ValueError(f"Unknown register: {s}")
    return REGS[s]

def imm(s):
    s = s.strip()
    return int(s, 0)

def instr_words(mnem):
    """Return how many 16-bit words this mnemonic generates."""
    if mnem == 'NOP':
        return 1
    return 2   # every other instruction (including R-type) is now 2 words

def assemble(src):
    # ── First pass: collect labels ──────────────────────────────────────
    labels = {}
    word_addr = 0
    for raw in src.splitlines():
        line = raw.split('#')[0].split(';')[0].strip()
        if not line:
            continue
        if line.endswith(':'):
            labels[line[:-1].upper()] = word_addr
            continue
        mnem = line.split()[0].upper()
        word_addr += instr_words(mnem)

    # ── Second pass: generate words ─────────────────────────────────────
    words = []
    word_addr = 0
    for lineno, raw in enumerate(src.splitlines(), 1):
        line = raw.split('#')[0].split(';')[0].strip()
        if not line or line.endswith(':'):
            continue
        parts = line.split()
        mnem  = parts[0].upper()

        # ── NOP ──────────────────────────────────────────────────────────
        if mnem == 'NOP':
            words.append(0x0000)
            word_addr += 1

        # ── MOV Rd, Rs  →  R-type ADD Rd, R0, Rs ────────────────────────
        elif mnem == 'MOV':
            rd = reg(parts[1])
            rs = reg(parts[2])
            words.append((GRP_R << 12) | (rd << 8) | (0 << 4) | rs)
            words.append(0x0000)   # func = ADD = 0
            word_addr += 2

        # ── R-type: ADD Rd, Rs1, Rs2 ─────────────────────────────────────
        elif mnem in R_FUNC:
            rd   = reg(parts[1])
            rs1  = reg(parts[2])
            rs2  = reg(parts[3])
            func = R_FUNC[mnem]
            # word1: dest | srcA | srcB  (all three regs fit, no func clash)
            words.append((GRP_R << 12) | (rd << 8) | (rs1 << 4) | rs2)
            # word2: func in lower nibble
            words.append(func & 0x000F)
            word_addr += 2

        # ── I-type: ADDI Rd, Rs1, imm ────────────────────────────────────
        elif mnem in I_FUNC:
            rd   = reg(parts[1])
            rs1  = reg(parts[2])
            immv = imm(parts[3]) & 0xFFFF
            func = I_FUNC[mnem]
            # word1: dest | func | srcA  (srcA in [3:0], not 0)
            words.append((GRP_I << 12) | (rd << 8) | (func << 4) | rs1)
            words.append(immv)
            word_addr += 2

        # ── LW Rd, Rs1, offset  OR  LW Rd, offset(Rs1) ──────────────────
        elif mnem == 'LW':
            rd = reg(parts[1])
            if '(' in parts[2]:
                off_str, base_str = parts[2].split('(')
                rs1  = reg(base_str.rstrip(')'))
                immv = imm(off_str) & 0xFFFF
            else:
                rs1  = reg(parts[2])
                immv = imm(parts[3]) & 0xFFFF
            words.append((GRP_LD << 12) | (rd << 8) | (rs1 << 4) | 0)
            words.append(immv)
            word_addr += 2

        # ── SW Rs, Rb, offset  OR  SW Rs, offset(Rb) ─────────────────────
        elif mnem == 'SW':
            rs = reg(parts[1])      # data source in [11:8]
            if '(' in parts[2]:
                off_str, base_str = parts[2].split('(')
                rb   = reg(base_str.rstrip(')'))
                immv = imm(off_str) & 0xFFFF
            else:
                rb   = reg(parts[2])
                immv = imm(parts[3]) & 0xFFFF
            words.append((GRP_ST << 12) | (rs << 8) | (rb << 4) | 0)
            words.append(immv)
            word_addr += 2

        # ── BRANCH: BEQ Rs1, Rs2, label_or_offset ────────────────────────
        elif mnem in BRANCH_COND:
            rs1    = reg(parts[1])
            rs2    = reg(parts[2])
            cond   = BRANCH_COND[mnem]
            target = parts[3].strip()
            if target.upper() in labels:
                # offset must be relative to PC *after* both words are fetched
                # i.e. relative to (word_addr + 2), not word_addr
                offset = labels[target.upper()] - (word_addr + 2)
            else:
                offset = imm(target)
            # cond goes directly into [11:8], NOT shifted by 1
            words.append((GRP_BR << 12) | (cond << 8) | (rs1 << 4) | rs2)
            words.append(offset & 0xFFFF)
            word_addr += 2

        # ── J label_or_offset ─────────────────────────────────────────────
        elif mnem == 'J':
            target = parts[1].strip()
            if target.upper() in labels:
                offset = labels[target.upper()] - (word_addr + 2)
            else:
                offset = imm(target)
            words.append((GRP_J << 12) | 0)
            words.append(offset & 0xFFFF)
            word_addr += 2

        # ── JAL Rd, label_or_offset ───────────────────────────────────────
        elif mnem == 'JAL':
            rd     = reg(parts[1])
            target = parts[2].strip()
            if target.upper() in labels:
                offset = labels[target.upper()] - (word_addr + 2)
            else:
                offset = imm(target)
            words.append((GRP_JAL << 12) | (rd << 8))
            words.append(offset & 0xFFFF)
            word_addr += 2

        # ── LUI Rd, imm ───────────────────────────────────────────────────
        elif mnem == 'LUI':
            rd   = reg(parts[1])
            immv = imm(parts[2]) & 0xFFFF
            words.append((GRP_LUI << 12) | (rd << 8))
            words.append(immv)
            word_addr += 2

        else:
            raise ValueError(f"Line {lineno}: unknown mnemonic '{mnem}'")

    return words


def main():
    import sys
    src_file = sys.argv[1] if len(sys.argv) > 1 else 'prog.asm'
    hex_file = src_file.replace('.asm', '.hex')
    with open(src_file) as f:
        src = f.read()
    words = assemble(src)
    # Pad to 64 words
    while len(words) < 64:
        words.append(0x0000)
    with open(hex_file, 'w') as f:
        for w in words:
            f.write(f'{w:04X}\n')
    print(f"Assembled {len(words)} words → {hex_file}")
    for i, w in enumerate(words[:48]):
        print(f"  [{i:02d}]  {w:016b}  0x{w:04X}")


if __name__ == '__main__':
    main()