    lda #1
    sta 128
    sta 129
loop:
    lda 128
    adc 129
    sta 130

    lda 129
    sta 128

    lda 130
    sta 129
    jmp loop
