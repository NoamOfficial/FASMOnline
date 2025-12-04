cmp al, "S"
je shutdown
cmp al, "R"
je Restart
shutdown: 
mov 0x4002, 2000
restart:
xor al, al
xor al, 1
out 0x92, al
hlt
