org 100h
jmp start

pcb: times 32*16 dw 0
current: dw 0		;index of current process which is zero by defualt
stack: times 512*16 dw 0
nextpcb: dw 1		; index of next free pcb
axsave equ 00
bxsave equ 02
cxsave equ 04
dxsave equ 06
sisave equ 08
disave equ 10
bpsave equ 12
spsave equ 14
ipsave equ 16
cssave equ 18
dssave equ 20
sssave equ 22
essave equ 24
flagsave equ 26
nextsave equ 28
prevsave equ 29
dummy equ 30	;it would be used for suspend and resume threads. 0000 means task to resume. 000F means task to suspend




; timer interrupt service routine
isr08: 
push ds
push bx
push cs
pop ds 		; initialize ds to data segment so that we get same cs in ds
mov bx, [current] 
shl bx, 5 
mov [pcb+bx+axsave], ax ; save ax 
mov [pcb+bx+cxsave], cx ; save cx 
mov [pcb+bx+dxsave], dx ; save dx 
mov [pcb+bx+sisave], si ; save si 
mov [pcb+bx+disave], di ; save di 
mov [pcb+bx+bpsave], bp ; save bp 
mov [pcb+bx+essave], es ; save es

pop ax ; read original bx from stack
mov [pcb+bx+bxsave], ax ; save bx in current pcb
pop ax ; read original ds from stack
mov [pcb+bx+dssave], ax ; save ds in current pcb
pop ax ; read original ip from stack
mov [pcb+bx+ipsave], ax ; save ip in current pcb
pop ax ; read original cs from stack
mov [pcb+bx+cssave], ax ; save cs in current pcb
pop ax ; read original flags from stack
mov [pcb+bx+flagsave], ax ; save flags in current pcb

mov [pcb+bx+sssave], ss 
mov [pcb+bx+spsave], sp ; save sp in current pcb which is before this subroutine was called

next:
mov bl, [pcb+bx+nextsave] ; read next pcb of this pcb
xor bh,bh
mov [current], bx ; update current to new pcb
shl bx, 5 
cmp word[pcb+bx+dummy],0x000F
je next

restore:
;to restore state
mov cx, [cs:pcb+bx+cxsave] 
mov dx, [cs:pcb+bx+dxsave] 
mov si, [cs:pcb+bx+sisave] 
mov di, [cs:pcb+bx+disave] 
mov bp, [cs:pcb+bx+bpsave] 
mov es, [cs:pcb+bx+essave] 
mov ss, [cs:pcb+bx+sssave] 
mov sp, [cs:pcb+bx+spsave] 

push word [cs:pcb+bx+flagsave] 
push word [cs:pcb+bx+cssave] 
push word [cs:pcb+bx+ipsave] 
push word [cs:pcb+bx+dssave] 

;;;;;;;;;;;;;;;;;;;;;;;;;;
mov al, 0x20
out 0x20, al 
;part of restore state. so that it doesn't get changed 
mov ax, [cs:pcb+bx+axsave] ; read ax of new process
mov bx, [cs:pcb+bx+bxsave] ; read bx of new process
pop ds ; read ds of new process as there is only one parameter on stack above ret address
iret

kill_thread:
;push bx

mov bx,[cs:current]
shl bx,5
mov ah,[cs:pcb+bx+prevsave]	;save previous 
mov al,[cs:pcb+bx+nextsave]	;save next
mov bl,ah	;store previous in bl
xor bh, bh
shl bx, 5
mov byte[cs:pcb+bx+nextsave],al		;point to new previous
mov bl,al 	;store next of current
xor bh,bh
shl bx,5
mov byte[cs:pcb+bx+prevsave],ah	;point to the new next
;mov ax,[nextpcb]
mov byte[cs:current],al
mov bx,[cs:current]
shl bx,5
jmp restore


resume:
push bx
shl bx,5
mov word[cs:pcb+bx+dummy],0x0000
pop bx
iret


suspend:
push bx
shl bx,5
mov word[cs:pcb+bx+dummy],0x000F
pop bx
iret

initpcb: 
push ax
push bx
push cx
push di
mov bx, [cs:nextpcb] ; read next available pcb index
cmp bx, 32 ; check if all pcbs are used or not
je exit ; if all used then simply exit

shl bx, 5 
mov ax, [si+0] ; read code segment parameter CS
mov [cs:pcb+bx+cssave], ax 
mov ax, [si+2] ; read offset parameter IP
mov [cs:pcb+bx+ipsave], ax 
mov ax, [si+4] ; read data segment parameter DS
mov [cs:pcb+bx+dssave], ax 
mov ax, [si+6] ; read extra segment parameter ES
mov [cs:pcb+bx+essave], ax 
mov [cs:pcb+bx+sssave], cs 
mov di, [cs:nextpcb] ; read this pcb index

shl di, 9 ; multiply by 512
add di, 512+stack ; end of stack for this thread

mov ax, [si+8] ; read parameter for subroutine
sub di, 2 ; decrement thread stack pointer
mov [cs:di], ax ; pushing parameter on thread stack
;sub di, 4 ; space for far return address

mov [cs:pcb+bx+spsave], di ; save di in pcb space for sp
mov word[cs:pcb+bx+flagsave], 0x0200 ; initialize flags so that interrupt routine doesn't get stuck on 0

mov al, [cs:pcb+nextsave] ; read next of 0th thread in al
mov byte[cs:pcb+bx+nextsave], al ; set as next of new thread

mov byte[cs:pcb+bx+prevsave],0
mov al, [cs:nextpcb] ; read new thread index

mov [cs:pcb+nextsave], al
mov al, [cs:pcb+bx+nextsave]
xor bx,bx
mov bl,al
shl bx,5

mov ah,[cs:nextpcb]	;read previous
mov byte[cs:pcb+bx+prevsave],ah
inc word[cs:nextpcb] ; this pcb is now used


exit: 
pop di
pop cx
pop bx
pop ax
iret





start:
xor ax, ax
mov es, ax ; point es to IVT base
mov word [es:0x80*4], initpcb
mov [es:0x80*4+2], cs ; hook software int 80


mov word[es:0x81*4],suspend
mov [es:0x81*4+2],cs


mov word[es:0x82*4],resume
mov [es:0x82*4+2],cs

mov word[es:0x83*4],kill_thread
mov [es:0x83*4+2],cs

cli
mov word [es:0x08*4], isr08
mov [es:0x08*4+2], cs ; hook timer interrupt
sti
mov dx, start
add dx, 15
shr dx, 4
mov ax, 0x3100 ; terminate and stay resident
int 0x21