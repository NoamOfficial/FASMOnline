use32

; --------------------------
section '.bss' align 4
ecx_total   resd 1
esi_chunk   resd 1
buffer      resb 512*256      ; buffer for max 256 sectors

; --------------------------
section '.text' code readable executable

IDE_DATA        equ 0x1F0
IDE_SECCOUNT    equ 0x1F2
IDE_LBA_LOW     equ 0x1F3
IDE_LBA_MID     equ 0x1F4
IDE_LBA_HIGH    equ 0x1F5
IDE_DRIVE       equ 0x1F6
IDE_STATUS      equ 0x1F7
IDE_COMMAND     equ 0x1F7

BSY equ 0x80
DRQ equ 0x08

CMD_READ_STREAM_EXT_48   equ 0x24
CMD_WRITE_STREAM_EXT_48  equ 0x34

; ---------------------------------
wait_ready:
    in al, IDE_STATUS
    test al, BSY
    jnz wait_ready
    in al, IDE_STATUS
    test al, DRQ
    jz wait_ready
    ret

; ---------------------------------
; Interrupt handler: int 0x90 for IDE
; AH = 0 -> write, 1 -> read
; EBX:EDX = starting LBA (48-bit)
; ECX = sector count
; ESI = buffer pointer
; Return: EAX=0 success, 1 error
ide_int_handler:
    pushad                     ; save all general registers
    push ebp
    mov ebp, esp

    ; save total sectors
    mov [ecx_total], ecx

.next_chunk:
    ; calculate chunk size = min(256, remaining)
    mov eax, [ecx_total]
    cmp eax, 256
    jle .set_chunk
    mov eax, 256
.set_chunk:
    mov [esi_chunk], eax

    ; sector count 48-bit
    mov al, ah
    out IDE_SECCOUNT+1, al
    mov al, al
    out IDE_SECCOUNT, al

    ; LBA high bytes first
    mov al, dl
    out IDE_LBA_LOW+1, al
    mov al, dh
    out IDE_LBA_MID+1, al
    mov al, 0
    out IDE_LBA_HIGH+1, al

    ; LBA low bytes second
    mov al, bl
    out IDE_LBA_LOW, al
    mov al, bh
    out IDE_LBA_MID, al
    mov al, 0
    out IDE_LBA_HIGH, al

    ; select drive
    mov al, 0x40
    out IDE_DRIVE, al

    ; send command
    cmp ah, 0
    je .write_cmd
    mov al, CMD_READ_STREAM_EXT_48
    jmp .send_cmd
.write_cmd:
    mov al, CMD_WRITE_STREAM_EXT_48
.send_cmd:
    out IDE_COMMAND, al

    ; transfer data per sector
    mov edi, esi
    mov ecx, [esi_chunk]
.next_sector:
    call wait_ready
    mov edx, 256
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

    ; advance buffer
    mov eax, [esi_chunk]
    shl eax, 9
    add esi, eax

    ; advance LBA
    add ebx, [esi_chunk]
    adc edx, 0

    ; subtract chunk from total
    mov eax, [ecx_total]
    sub eax, [esi_chunk]
    mov [ecx_total], eax

    cmp dword [ecx_total], 0
    jne .next_chunk

    ; success
    xor eax, eax

    pop ebp
    popad
    iret

    
