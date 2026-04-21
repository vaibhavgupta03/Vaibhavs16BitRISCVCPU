# 16-bit RISC-V CPU Core Design & Documentation

## 📖 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [ISA Specification](#isa-specification)
- [Pipeline Flow](#pipeline-flow)
- [Module Documentation](#modules)
- [Assembler Workflow](#assembler)
- [Verification & Testbench](#verification)
- [Usage](#usage)
- [Performance](#performance)
- [Block Diagram](#diagram)
- [Status & Next Steps](#status)

## 🔭 Overview
This project implements a **compact 16-bit RISC-V inspired CPU** with a **5-stage pipeline**:

```
FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK
```

**Key Specs**:
- **Word Size**: 16-bit (instructions & data)
- **Registers**: 16 × 16-bit (R0 always 0)
- **Memory**: 64 × 16-bit instrROM + dataRAM
- **ALU**: 16 ops (ADD/SUB/LOGIC/SHIFT/SLT/MUL/MIN/MAX)
- **Pipeline**: 6 cycles/instruction (SIM_MODE=1 bypasses clkdiv)
- **Verification**: `testbench.v` runs 16 checks → **ALL PASS**

**Board Mapping** (`top.v`):
- `btn0`: Reset
- `btn1`: Single-step
- `btn2`: Run/halt toggle
- `btn3`: Mode (0=ALU leds, 1=reg[sw] leds)
- `sw[3:0]`: Register index
- `led[3:0]`: Output

## 🏗️ Architecture
![Pipeline](https://via.placeholder.com/800x200/007ACC/white?text=Pipeline:+Fetch-Decode-Execute-Memory-Writeback)

```
instrROM[PC] ─→ IR ─→ decoder ─→ control signals ─→ ALU/registers/RAM
PC update ─← branches/JAL (EX/MEM)
```
- **No forwarding** (data hazards stall)
- **SIM_MODE**: 1=fast sim (testbench), 0=slow board (~1Hz)

## 📊 ISA Specification

| Group | Hex | Mnemonics | Format | Encoding | Notes |
|-------|-----|-----------|--------|----------|-------|
| **R** | `0xxx` | `ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU/MUL/NOR/XNOR/MIN/MAX` | `rd, rs1, rs2` | `[15:12]=0 [11:8]=rd [7:4]=rs1 [3:0]=rs2`<br>`imm_word[3:0]=func` | func table below |
| **I** | `1xxx` | `ADDI/SUBI/ANDI/ORI/XORI/SLLI/SRLI/SRAI/SLTI/SLTIU` | `rd, rs, imm16` | `[15:12]=1 [11:8]=rd [7:4]=func [3:0]=rs`<br>`imm_word=imm16` | ALU imm |
| **LW** | `2xxx` | `LW rd, off(rs)` | 2 words | `[15:12]=2 [11:8]=rd [7:4]=rs [3:0]=0`<br>`imm_word=off` | `rd <= mem[rs+off]` |
| **SW** | `3xxx` | `SW rs, off(rb)` | 2 words | `[15:12]=3 [11:8]=rs [7:4]=rb [3:0]=0`<br>`imm_word=off` | `mem[rb+off] <= rs` |
| **BR** | `4xxx` | `BEQ/BNE/BLT/BGE/BLTU/BGEU rs1, rs2, off` | 2 words | `[15:12]=4 [11:8]=cond [7:4]=rs1 [3:0]=rs2`<br>`imm_word=off` | PC += off if cond |
| **J**  | `5xxx` | `J off` | 2 words | `[15:12]=5 [11:0]=0`<br>`imm_word=off[15:0]` | PC += off[5:0] |
| **JAL**| `6xxx` | `JAL rd, off` | 2 words | `[15:12]=6 [11:8]=rd [7:0]=0`<br>`imm_word=off` | `rd <= PC; PC += off` |
| **LUI**| `7xxx` | `LUI rd, imm` | 2 words | `[15:12]=7 [11:8]=rd [7:0]=0`<br>`imm_word=imm` | `rd <= imm` |

**ALU Func Table** (`alu.v`):
| Func | Op | Flags |
|------|----|-------|
| 0 | ADD | NZCV |
| 1 | SUB | NZCV |
| 2 | AND | NZ-- |
| 3 | OR  | NZ-- |
| 4 | XOR | NZ-- |
| 5 | SLL A<<B[3:0] | NZ-- |
| 6 | SRL A>>B[3:0] | NZ-- |
| 7 | SRA $signed(A)>>>B[3:0] | NZ-- |
| 8 | SLT signed | NZ-- |
| 9 | SLTU unsigned | NZ-- |
| 10 | MUL A[7:0]*B[7:0] | NZ-- |
| 11 | PASS B | NZ-- |
| 12 | NOR ~(A\|B) | NZ-- |
| 13 | XNOR ~(A^B) | NZ-- |
| 14 | MIN signed | NZ-- |
| 15 | MAX signed | NZ-- |

## 📈 Pipeline Workflow

```
Cycle 1: FETCH  | IR <= rom[PC]; PC <= PC+1
Cycle 2: FETCH2 | if needs_imm: IMM_WORD <= rom[PC]; PC++; 
Cycle 3: DECODE | latch d_grp,d_dest,d_alu_op,d_imm,...
Cycle 4: EXECUTE| ex_result <= ALU; ex_flags <= flags
Cycle 5: MEMORY | mem_wr? RAM<=store_data; branch? PC+=off
Cycle 6: WB     | regs[d_dest] <= ex_result; PC update complete
```

**JAL Example**:
```
PC=30 (JAL instr): FETCH word1 → FETCH2 word2 → DECODE → EXECUTE
EXECUTE: wb_data <= PC=32; PC += off → PC=38; state=WB
WB: R15 <= 32; FETCH at 38
```

## 🧩 Module Details

### 1. **`cpu.v`** (Pipeline Controller)
- **5 Stages**: FETCH/FETCH2/DECODE/EXECUTE/MEMORY/WB
- **PC Logic**: Branch/JAL in EXEC/MEM; halt PC>=62
- **Store Fix**: `store_data <= RF.bank[d_dest]` in EX (ST d_dest=[11:8])
- **ALU B Mux**: imm for I/LUI/LW/SW; regB_data otherwise

### 2. **`decoder.v`** (Control Unit)
- **Field Extract**: grp=15:12, dest=11:8, srcA=7:4 or 3:0, srcB=3:0
- **needs_imm**: R/I/L/S/B/J/JAL/LUI (R-type 2nd word has func)
- **alu_op**: R=imm_word[3:0], I=instr[7:4], etc.
- **branch_type**: instr[10:8] (cond field)

### 3. **`alu.v`** (Arithmetic Logic Unit)
- **Ops**: See table above
- **Flags**: N=result[15], Z=result==0, C=carry, V=overflow
- **MUL**: 8×8→16 lower bits
- **Shifts**: B[3:0] amount (0-15)

### 4. **`register.v`** (Register File)
```
reg [15:0] bank [15:0];
assign regA = bank[srcA_addr];
always @(posedge clk) if (wr_en && wr_addr != 0) bank[wr_addr] <= wr_data;
```
- **Dual-port read**, single-port write
- **R0 hardwired 0**
- **Debug**: `modeRead` → leds=bank[valin]

### 5. **`dataRAM.v`** / **`instrROM.v`**
- **64×16**: async read, sync write (RAM only)
- **instrROM**: `$readmemh("prog.hex", mem)`

### 6. **`assembler.py`** (prog.asm → prog.hex)
- **Passes**: Labels, then emit 2-word instrs
- **R-type**: word1=grp|rd|rs1|rs2, word2=func
- **I-type**: word1=grp|rd|func|rs1, word2=imm
- **Pad 64 words**, hex dump first 48

### 7. **`clkDivider.v`**
```
SIM_MODE=1: pass-through (testbench)
SIM_MODE=0: 100MHz → 1Hz (board LEDs)
```

### 8. **`top.v`** (Board Wrapper)
Board I/O to CPU pins.

### 9. **`testbench.v`** (Verification)
- **16 Checks**: ALU, shifts, mem, branch, JAL ret addr
- **Pass**: ALL 16 ✅ (after fixes)
- `$dumpvars` → GTKWave

## 🧪 Usage Workflow

```
1. Edit prog.asm
2. python assembler.py prog.asm     # → prog.hex
3. vvp riscoutput                  # Tests: PASSED 16/16
4. gtkwave tb_cpu_test_all.vcd     # Waveforms
5. Vivado → top.v (SIM_MODE=0)
```

**Sample Output**:
```
========== Register File Checks ==========
PASS  R1  = 16'h0005  | ADDI R1=5
...
========== Summary ==========
PASSED: 16 FAILED: 0 TOTAL: 16
ALL TESTS PASSED
```

## 🎛️ Controls (Board)
- **btn0**: Reset
- **btn1**: Single step
- **btn2**: Run/Stop
- **btn3**: Mode switch (ALU vs Reg leds)
- **sw[3:0]**: Reg index to read
- **led[3:0]**: ALU low bits or reg[sw]

## 📊 Performance Metrics
| Metric | Value |
|--------|-------|
| Instr Width | 16-bit |
| Regs | 16 |
| Mem | 64 words |
| CPI | ~1.0 (no stalls) |
| Freq | 100MHz sim, 1Hz board |
| Tests | 16/16 PASS |

## 🔧 Design Decisions & Fixes
- **2-word R/I**: Solves func/rs field overlap
- **Store Data**: `store_data <= RF.bank[d_dest]` (ST rs=[11:8])
- **ALU Func R-type**: imm_word[3:0]
- **JAL PC**: Exact return (PC post-FETCH2)
- **No Forwarding**: Simple but correct

## 🚀 Future Work
- [ ] Data forwarding
- [ ] JR (jump register)
- [ ] Interrupts
- [ ] Full Vivado board demo



**Run Tests**: `vvp riscoutput`

## 📂 File Structure
```.
├── assembler.py       # Assembler script
├── cpu.v             # Main CPU module (pipeline controller)
├── decoder.v         # Instruction decoder (control unit)
├── alu.v             # ALU implementation
├── register.v        # Register file
├── dataRAM.v         # Data memory module
├── instrROM.v        # Instruction memory module
├── clkDivider.v      # Clock divider for board timing
├── top.v             # Top-level module for board integration
├── testbench.v       # Testbench for verification
├── prog.asm          # Sample assembly program
├── prog.hex          # Assembled program (generated by assembler.py)
├── README.md         # Project documentation
```

## 🏁 Status & Next Steps
- **Status**: All tests pass, basic CPU functional
- **Next Steps**: Add forwarding, JR, interrupts, and board demo

## References
- RISC-V Spec: https://riscv.org/specifications/
- Verilog Tutorials: https://www.verilogpro.com/
- Vivado Docs: https://www.xilinx.com/support/documentation/sw_manuals/xilinx_vivado_design_suite.html
- Book: "CDigital Design and Computer Architecture" by Harris & Harris
- RISC-V Assembly: https://riscv.org/learning/assembly/

## 📞 Contact
For questions or contributions, please reach out to Vaibhav at [vaibhav_g2@ee.iitr.ac.in](mailto:vaibhav_g2@ee.iitr.ac.in) or open an issue on GitHub.