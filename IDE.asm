

; =======================================================
; UltimateOS IDE Driver - Ultra-Fast Multi-Sector Streaming
; =======================================================

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
; Reserved memory
; -----------------------
align 4
IDE_buffer      rb 16384       ; 16KB buffer for multi-sector transfers

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
;   EBX = starting LBA (low 32 bits)
;   ECX = total number of sectors to transfer
; Notes:
;   - Transfers up to 32 sectors at a time (buffer = 16KB)
;   - Automatically loops for large transfers
; =======================================================
ide_multi_sector:
    push ebp
    mov ebp, esp

    mov esi, IDE_buffer       ; buffer pointer
.next_chunk:
    cmp ecx, 32
    jle .last_chunk
    mov edx, 32               ; transfer 32 sectors this chunk
    sub ecx, 32
    jmp .do_transfer
.last_chunk:
    mov edx, ecx
    xor ecx, ecx
.do_transfer:
    ; Set features = 0
    xor al, al
    out IDE_FEATURES, al

    ; Set sector count (lower and upper)
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

    ; Drive select
    mov al, 0x40             ; master LBA
    out IDE_DRIVE, al

    ; Send command based on AH
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
    mov ecx, edx              ; number of sectors in this chunk
    mov edi, esi              ; buffer pointer
.loop_sectors:
    call wait_ready
    mov ebp, 256              ; words per sector
.word_loop:
    cmp ah, 1                 ; read?
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

    add esi, edx*512          ; move buffer pointer for next chunk
    add ebx, edx              ; next LBA
    cmp ecx, 0
    je .done_chunk
    jmp .next_chunk
.done_chunk:
    pop ebp
    ret

.halt:
    hlt
    jmp .halt

; =======================================================
; Example usage: read 64 sectors starting at LBA 0
; =======================================================
start_driver:
    mov ebx, 0          ; LBA 0
    mov ecx, 64         ; total sectors
    mov ah, 1           ; 1 = read
    call ide_multi_sector

    mov ebx, 0
    mov ecx, 64
    mov ah, 0           ; 0 = write
    call ide_multi_sector

.halt_loop:
    hlt
    jmp .halt_loop
