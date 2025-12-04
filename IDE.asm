; =======================================================
; UltimateOS IDE Driver - Fast Multi-Sector Streaming (use32, no .bss)
; =======================================================

use32

IDE_DATA        equ 0x1F0
IDE_ERROR       equ 0x1F1
IDE_FEATURES    equ 0x1F1
IDE_SECCOUNT    equ 0x1F2
IDE_LBA_LOW     equ 0x1F3
IDE_LBA_MID     equ 0x1F4
IDE_LBA_HIGH    equ 0x1F5
IDE_DRIVE       equ 0x1F6
IDE_STATUS      equ 0x1F7
IDE_COMMAND     equ 0x1F7
IDE_ALTSTATUS   equ 0x3F6
IDE_CONTROL     equ 0x3F6

BSY equ 0x80
RDY equ 0x40
DRQ equ 0x08
ERR equ 0x01

CMD_READ_STREAM_EXT   equ 0x2F
CMD_WRITE_STREAM_EXT  equ 0xCF



; -----------------------
; Wait for BSY=0 and DRQ=1
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
; IDE Ultra-Fast Multi-Sector Dispatcher
; Input:
;   AH = 0 -> write
;   AH = 1 -> read
;   EBX = starting LBA
;   ECX = total sectors
;   ESI = pointer to buffer
; Output:
;   buffer contains read sectors / writes buffer
; =======================================================
ide_multi_sector:
    push ebp
    mov ebp, esp

.next_chunk:
    ; calculate sectors for this chunk (max 32 for example)
    mov edx, ecx
    cmp edx, 32
    jle .chunk_ready
    mov edx, 32
.chunk_ready:
    sub ecx, edx

    xor al, al
    out IDE_FEATURES, al

    ; sector count
    mov al, dl
    out IDE_SECCOUNT, al
    xor al, al
    out IDE_SECCOUNT+1, al

    ; LBA split
    mov eax, ebx
    mov al, al
    out IDE_LBA_LOW, al
    mov al, ah
    out IDE_LBA_LOW+1, al
    shr ebx, 16
    mov al, bl
    out IDE_LBA_MID, al
    mov al, bh
    out IDE_LBA_MID+1, al
    shr ebx, 16
    mov al, bl
    out IDE_LBA_HIGH, al
    mov al, bh
    out IDE_LBA_HIGH+1, al

    mov al, 0x40
    out IDE_DRIVE, al

    ; Command
    cmp ah, 0
    je .write_cmd
    cmp ah, 1
    je .read_cmd
    jmp .halt
.read_cmd:
    mov al, CMD_READ_STREAM_EXT
    out IDE_COMMAND, al
    jmp .transfer_loop
.write_cmd:
    mov al, CMD_WRITE_STREAM_EXT
    out IDE_COMMAND, al

.transfer_loop:
    mov ecx, edx
    mov edi, esi
.loop_sectors:
    call wait_ready
    mov ebp, 256
.word_loop:
    cmp ah, 1
    je .read_word
    mov ax, [edi]
    out IDE_DATA, ax
    jmp .next_word
.read_word:
    in ax, IDE_DATA
    mov [edi], ax
.next_word:
    add edi, 2
    dec ebp
    jnz .word_loop
    dec ecx
    jnz .loop_sectors

    lea esi, [esi + edx*512]
    add ebx, edx

    cmp ecx, 0
    jne .next_chunk

    pop ebp
    ret

.halt:
    ret
