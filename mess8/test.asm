    lda #0
loop:
    adc #32
    bcs halt
    jmp loop
halt:
    jmp halt
