import sys

src = None
with open(sys.argv[1]) as f:
    src = f.read()

binary = bytearray()
labels = {}     # name, addr
label_refs = {} # addr, name

instructions = {
    "lda_i": 0,
    "lda_a": 1,
    "sta_a": 2,
    "adc_i": 3,
    "jmp_a": 4,
    "bcs_a": 5,
}

def parse_instruction(src):
    split = src.split()

    is_immediate = "#" in src
    opcode = instructions[split[0] + ("_i" if is_immediate else "_a")]
    
    result = opcode.to_bytes(1, "little")
    if len(split) == 2:
        operand = split[1].replace("#", "")

        if operand.isdigit():
            operand = int(operand)
            result += operand.to_bytes(1, "little")
        else: #label
            label_refs[len(binary) + 1] = operand
            result += (255).to_bytes(1, "little") # tmp

    return result

for line in src.splitlines():
    line = line.split(";")[0]
    instr = line
    colon_split = line.split(":")

    if len(colon_split) == 2:
        instr = colon_split[1]
        label = colon_split[0]

        labels[label] = len(binary)

    instr = " ".join(instr.split())
    if instr == "":
        continue

    binary += parse_instruction(instr)

# replace labels with addresses
for addr, lab in label_refs.items():
    binary[addr] = labels[lab]

with open(sys.argv[1].replace(".asm", ".bin"), "wb") as f:
    f.write(binary)
