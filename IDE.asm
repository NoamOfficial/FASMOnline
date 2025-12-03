; ============================================
; UltimateOS IDE PIO Stream Driver (FASM)
; ============================================

format ELF32      ; 32-bit code
bits 32

section '.bss' align 4
RAX         rb 8*1          ; 64-bit LBA storage
RXX         rb 8*1          ; temporary 64-bit
Buffer      rw 2048          ; 2048 words = 4096 bytes
SectorCount rb 1
Operation   rb 1             ; 0=WRITE, 1=READ

section '.text' align 4
global IDE_PIO_STREAM_FINAL

IDE_PIO_STREAM_FINAL:

    cmp [Operation], 0
    je write_stream
    cmp [Operation], 1
    je read_stream
    ret

; ================= WRITE STREAM ==================
write_stream:
    call setup_LBA48
    mov dx, 0x1F7
    mov al, 0xEA           ; WRITE STREAM EXT
    out dx, al

    mov esi, Buffer
    mov cl, [SectorCount]

write_sector_loop:
    call wait_DRQ
    mov dx, 0x1F0
    mov bx, 256             ; words per sector

write_word_loop:
    lodsw                   ; load word from DS:SI -> AX
    out dx, ax
    dec bx
    jnz write_word_loop

    dec cl
    jnz write_sector_loop
    ret

; ================= READ STREAM ===================
read_stream:
    call setup_LBA48
    mov dx, 0x1F7
    mov al, 0x25           ; READ STREAM EXT
    out dx, al

    mov edi, Buffer
    mov cl, [SectorCount]

read_sector_loop:
    call wait_DRQ
    mov dx, 0x1F0
    mov bx, 256

read_word_loop:
    in ax, dx
    stosw                   ; store AX -> ES:DI
    dec bx
    jnz read_word_loop

    dec cl
    jnz read_sector_loop
    ret

; ================= 48-BIT LBA ===================
setup_LBA48:
    mov eax, dword [RAX]        ; low 32 bits
    mov edx, dword [RAX+4]      ; high 32 bits

    ; sector count
    mov dx, 0x1F2
    mov al, [SectorCount]
    out dx, al

    ; LBA low/mid/high
    mov dx, 0x1F3
    mov al, al
    out dx, al
    mov dx, 0x1F4
    mov al, ah
    out dx, al
    mov dx, 0x1F5
    mov al, dl
    out dx, al

    ; LBA high/mid/high (next 24 bits)
    mov dx, 0x1F2
    mov al, dh
    out dx, al
    shr edx, 8
    mov dx, 0x1F3
    mov al, dh
    out dx, al
    shr edx, 8
    mov dx, 0x1F4
    mov al, dh
    out dx, al
    shr edx, 8
    mov dx, 0x1F5
    mov al, dh
    out dx, al

    ; master + LBA mode
    mov dx, 0x1F6
    mov al, 0x40
    out dx, al
    ret

; ================= STATUS WAIT ===================
wait_DRQ:
    mov dx, 0x1F7

.wait_bsy:
    in al, dx
    call wait_420ns
    test al, 0x80          ; BSY
    jnz .wait_bsy

.wait_drq:
    in al, dx
    call wait_420ns
    test al, 0x08          ; DRQ
    jnz .ready
    test al, 0x01          ; ERR
    jnz .error
    jmp .wait_drq

.ready:
    ret
.error:
    ret

; ================= 420ns DELAY ===================
wait_420ns:
    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    ret
