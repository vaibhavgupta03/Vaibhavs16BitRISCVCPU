; ── Basic ALU ──────────────────────────────────────────
        ADDI  R1, R0, 5       ; R1 = 5
        ADDI  R2, R0, 3       ; R2 = 3
        ADD   R3, R1, R2      ; R3 = 8
        SUB   R4, R1, R2      ; R4 = 2
        AND   R5, R1, R2      ; R5 = 1
        OR    R6, R1, R2      ; R6 = 7
        XOR   R7, R1, R2      ; R7 = 6
        SLT   R8, R2, R1      ; R8 = 1  (3 < 5)
        MUL   R9, R1, R2      ; R9 = 15

; ── Shift operations ────────────────────────────────────
        SLLI  R10, R1, 2      ; R10 = 20  (5 << 2)
        SRLI  R11, R10, 1     ; R11 = 10  (20 >> 1)

; ── Load/Store ──────────────────────────────────────────
        SW    R3, R0, 0       ; mem[0] = 8  (store R3 at addr 0)
        SW    R4, R0, 1       ; mem[1] = 2  (store R4 at addr 1)
        LW    R12, R0, 0      ; R12 = mem[0] = 8
        LW    R13, R0, 1      ; R13 = mem[1] = 2

; ── Branch ──────────────────────────────────────────────
        BEQ   R12, R3, SKIP   ; branch if R12==R3 (8==8) → taken
        ADDI  R14, R0, 99     ; should be SKIPPED
SKIP:
        ADDI  R14, R0, 42     ; R14 = 42  (this runs)

; ── Jump ────────────────────────────────────────────────
        JAL   R15, FUNC       ; call FUNC, R15 = return address
        ADDI  R1, R0, 77      ; runs after return
        J     END             ; jump to end

; ── Function ────────────────────────────────────────────
FUNC:
        ADDI  R2, R0, 100     ; R2 = 100 inside function
        NOP
        ; return: J 0(R15) — not implemented yet, just fall through

END:
        NOP
        NOP