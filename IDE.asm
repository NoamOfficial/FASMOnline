use32

; IDE Ports
IDE_DATA        equ 0x1F0
IDE_SECCOUNT    equ 0x1F2
IDE_LBA_LOW     equ 0x1F3
IDE_LBA_LOW_HI  equ 0x1F4
IDE_LBA_MID     equ 0x1F4
IDE_LBA_MID_HI  equ 0x1F5
IDE_LBA_HIGH    equ 0x1F5
IDE_LBA_HIGH_HI equ 0x1F6
IDE_DRIVE       equ 0x1F6
IDE_STATUS      equ 0x1F7
IDE_COMMAND     equ 0x1F7
IDE_CONTROL     equ 0x3F6

BSY equ 0x80
DRQ equ 0x08

CMD_READ_STREAM_EXT_48   equ 0x24F
CMD_WRITE_STREAM_EXT_48  equ 0x2CF

; -----------------------
wait_ready:
    in al, IDE_STATUS
    test al, BSY
    jnz wait_ready
    in al, IDE_STATUS
    test al, DRQ
    jz wait_ready
    ret

; =======================================================
; IDE driver for 48-bit LBA, huge buffers
; Inputs:
;   AH = 0 -> write, 1 -> read
;   EBX:EDX = starting LBA (lower 48 bits)
;   ECX = sectors count
;   ESI = buffer pointer
; =======================================================
ide_48bit_safe:
    push ebp
    mov ebp, esp

.next_chunk:
    ; calculate chunk size (max 256 sectors per command)
    mov eax, ecx
    cmp eax, 256
    jle .set_chunk
    mov eax, 256
.set_chunk:
    mov al, al
    out IDE_SECCOUNT, al
    xor al, al
    out IDE_SECCOUNT+1, al

    ; 48-bit LBA split (all outputs use AL)
    mov al, bl
    out IDE_LBA_LOW, al
    mov al, bh
    out IDE_LBA_LOW_HI, al
    mov al, dl
    out IDE_LBA_MID, al
    mov al, dh
    out IDE_LBA_MID_HI, al
    ; high 16 bits if needed can be set similarly

    mov al, 0x40
    out IDE_DRIVE, al

    ; command
    cmp ah, 0
    je .write
    cmp ah, 1
    je .read
.read:
    mov al, CMD_READ_STREAM_EXT_48
    out IDE_COMMAND, al
    jmp .transfer
.write:
    mov al, CMD_WRITE_STREAM_EXT_48
    out IDE_COMMAND, al

.transfer:
    mov ecx, eax      ; sectors in this chunk
    mov edi, esi
.next_sector:
    call wait_ready
    mov ebp, 256
.next_word:
    cmp ah, 1
    je .rd
    mov ax, [edi]
    out IDE_DATA, ax
    jmp .nw
.rd:
    in ax, IDE_DATA
    mov [edi], ax
.nw:
    add edi, 2
    dec ebp
    jnz .next_word
    dec ecx
    jnz .next_sector

    ; safe buffer pointer increment
    mov ecx, eax
    shl ecx, 9      ; multiply by 512 bytes
    add esi, ecx
    ; advance LBA
    add ebx, eax

    ; subtract chunk from total sectors
    sub ecx, eax
    cmp ecx, 0
    jne .next_chunk

    pop ebp
    ret
