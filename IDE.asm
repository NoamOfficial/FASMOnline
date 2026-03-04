use32

; IDE Ports
IDE_DATA        equ 0x1F0
IDE_SECCOUNT    equ 0x1F2
IDE_LBA_LOW     equ 0x1F3
IDE_LBA_MID     equ 0x1F4
IDE_LBA_HIGH    equ 0x1F5
IDE_DRIVE       equ 0x1F6
IDE_STATUS      equ 0x1F7
IDE_COMMAND     equ 0x1F7
IDE_CONTROL     equ 0x3F6

BSY equ 0x80
DRQ equ 0x08

CMD_READ_STREAM_EXT_48   equ 0x24
CMD_WRITE_STREAM_EXT_48  equ 0x34

; ------------------------------------------------------
wait_ready:
    in al, IDE_STATUS
    test al, BSY
    jnz wait_ready
    in al, IDE_STATUS
    test al, DRQ
    jz wait_ready
    ret

; ------------------------------------------------------
; IDE 48-bit LBA driver
; AH = 0 -> write, 1 -> read
; EBX:EDX = starting LBA (48-bit)
; ECX = total sectors to read/write
; ESI = buffer pointer
ide_48bit_safe:
    push ebp
    mov ebp, esp
    mov ecx_total, ecx

.next_chunk:
    ; ---- chunk size = min(ECX_total, 256) ----
    mov eax, ecx_total
    cmp eax, 256
    jle .set_chunk
    mov eax, 256
.set_chunk:
    mov esi_chunk, eax        ; save chunk size

    ; ---- sector count (2 bytes) ----
    mov al, ah
    out IDE_SECCOUNT+1, al
    mov al, al
    out IDE_SECCOUNT, al

    ; ---- 48-bit LBA: high bytes first ----
    mov al, dl
    out IDE_LBA_LOW+1, al
    mov al, dh
    out IDE_LBA_MID+1, al
    mov al, 0
    out IDE_LBA_HIGH+1, al      ; high 16 bits usually 0 for normal 48-bit

    ; ---- 48-bit LBA: low bytes second ----
    mov al, bl
    out IDE_LBA_LOW, al
    mov al, bh
    out IDE_LBA_MID, al
    mov al, 0
    out IDE_LBA_HIGH, al        ; low 16 bits

    ; ---- select drive (LBA mode) ----
    mov al, 0x40
    out IDE_DRIVE, al

    ; ---- send command ----
    cmp ah, 0
    je .write_cmd
    mov al, CMD_READ_STREAM_EXT_48
    jmp .send_cmd
.write_cmd:
    mov al, CMD_WRITE_STREAM_EXT_48
.send_cmd:
    out IDE_COMMAND, al

; ---- transfer data ----
    mov edi, esi
    mov ecx, esi_chunk        ; sectors in chunk
.next_sector:
    call wait_ready
    mov edx, 256              ; 256 words per sector
.next_word:
    cmp ah, 1
    je .do_read
    mov ax, [edi]
    out IDE_DATA, ax
    jmp .nw_continue
.do_read:
    in ax, IDE_DATA
    mov [edi], ax
.nw_continue:
    add edi, 2
    dec edx
    jnz .next_word

    dec ecx
    jnz .next_sector

; ---- increment buffer and LBA ----
    shl esi_chunk, 9          ; multiply by 512 bytes
    add esi, esi_chunk

    add ebx, esi_chunk        ; low 32 bits LBA
    adc edx, 0                ; high 16 bits carry

; ---- subtract chunk from total ----
    sub ecx_total, esi_chunk
    cmp ecx_total, 0
    jne .next_chunk

    pop ebp
    ret

; ---- data section ----
section .bss
esi_chunk    resd 1
ecx_total    resd 1
