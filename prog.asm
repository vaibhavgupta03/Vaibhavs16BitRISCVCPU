# Sum of first 10 natural numbers (1+2+...+10 = 55 = 0x0037)
# Register usage:
#   R1 = counter (1 to 10)
#   R2 = sum accumulator
#   R3 = limit (10)

# R1 = 1  (counter start)
ADDI R1, R0, 1

# R2 = 0  (sum = 0)
ADDI R2, R0, 0

# R3 = 10 (loop limit)
ADDI R3, R0, 10

# LOOP: sum += counter
# ADD R2, R2, R1   → R2 = R2 + R1
ADD R2, R2, R1

# ADDI R1, R1, 1   → R1 = R1 + 1
ADDI R1, R1, 1

# BNE R1, R3, -2   → if R1 != R3, jump back to ADD
BNE R1, R3, -2

# Done: R2 = 55 (0x37)
# Infinite loop to hold result
J 0