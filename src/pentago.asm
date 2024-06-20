includelib kernel32.lib
includelib user32.lib
IFDEF _DEBUG
includelib libcmtd.lib
ENDIF

extern GetModuleHandleA:PROC
extern GetStdHandle:PROC
extern SetConsoleMode:PROC
extern GetConsoleScreenBufferInfo:PROC
extern ScrollConsoleScreenBufferA:PROC
extern FillConsoleOutputCharacterA:PROC
extern FillConsoleOutputAttribute:PROC
extern SetConsoleTextAttribute:PROC
extern SetConsoleCursorPosition:PROC
extern GetConsoleCursorInfo:PROC
extern SetConsoleCursorInfo:PROC
extern ReadConsoleInputA:PROC
extern WriteConsoleA:PROC
extern ExitProcess:PROC

extern GetConsoleWindow:PROC
extern GetWindowLongPtrA:PROC
extern SetWindowLongPtrA:PROC
extern LoadIconA:PROC

.DATA
SHADOW_SPACE = 32

GWL_STYLE		= -16
WS_MAXIMIZEBOX	= 10000h
WS_SIZEBOX		= 40000h

STD_INPUT_HANDLE	= -10
STD_OUTPUT_HANDLE	= -11

FOREGROUND_BLUE			= 1
FOREGROUND_GREEN		= 2
FOREGROUND_RED			= 4
FOREGROUND_INTENSITY	= 8
FOREGROUND_BOARD		= FOREGROUND_RED + FOREGROUND_GREEN + FOREGROUND_BLUE + FOREGROUND_INTENSITY
FOREGROUND_CURSOR		= FOREGROUND_RED + FOREGROUND_INTENSITY
FOREGROUND_CROSS		= FOREGROUND_GREEN + FOREGROUND_INTENSITY
FOREGROUND_CIRCLE		= FOREGROUND_BLUE + FOREGROUND_INTENSITY

SPACES		= 5
BOARD_ROWS	= 6
BOARD_COLS	= (6 + SPACES)

CONSOLE_SCREEN_BUFFER_INFO db 22 dup(?)
CONSOLE_CURSOR_INFO db 8 dup(?)
CHAR_INFO db 4 dup(?)
INPUT_RECORD db 20 dup(?)
SMALL_RECT db 8 dup(?)

input dq ?
output dq ?
initialAttributes dw ?

board db (BOARD_ROWS * (BOARD_COLS - SPACES)) dup(?)
boardLength = ($ - board)
winners db 6 dup(?)
winnersLength = ($ - winners)

xCursor	db ?
yCursor	db ?

turn	db ?
space   db 32
draw	db 68
circle	db 79
cross	db 88

newline db 13,10 	; \r\n
newlinelen = $ - newline

cls	db 27,'[3J' ; Clear scrollback buffer
clslen = $ - cls

.CODE
IFDEF _DEBUG
main PROC
ELSE
mainCRTStartup PROC
ENDIF
	sub rsp, (8 + SHADOW_SPACE) + 32
	
	mov rcx, STD_OUTPUT_HANDLE
	call [GetStdHandle]
	mov [output], rax
	
	mov rcx, STD_INPUT_HANDLE
	call [GetStdHandle]
	mov [input], rax
	
	mov rdi, 1	; ENABLE_PROCESSED_OUTPUT 
	or rdi, 4	; ENABLE_VIRTUAL_TERMINAL_PROCESSING
	or rdi, 8	; ENABLE_WINDOW_INPUT
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleMode]
	
	; Load icon
	
	mov rcx, 0
	call [GetModuleHandleA]
	
	mov rcx, rax
	mov rdx, 1
	call [LoadIconA]
	
	; Hide cursor
	
	mov rcx, [output]
	lea rdx, [CONSOLE_CURSOR_INFO]
	call [GetConsoleCursorInfo]
	
	mov DWORD PTR [CONSOLE_CURSOR_INFO + 4], 0
	
	mov rcx, [output]
	lea rdx, [CONSOLE_CURSOR_INFO]
	call [SetConsoleCursorInfo]
	
	; Disable window resizing (currently, only works in the old Windows Console Host)
	; https://github.com/microsoft/terminal/issues/12464
	
	call [GetConsoleWindow]
	mov rdi, rax
	
	mov rcx, rdi
	mov rdx, GWL_STYLE
	call [GetWindowLongPtrA]
	mov rsi, rax
	
	mov r8, WS_MAXIMIZEBOX
	not r8
	and rsi, r8
	mov r8, WS_SIZEBOX
	not r8
	and rsi, r8
	
	mov rcx, rdi
	mov rdx, GWL_STYLE
	mov r8, rsi
	call [SetWindowLongPtrA]
	
	; Save the initial text attributes the console window had before starting this program
	
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	movzx rdi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 8]
	mov WORD PTR [initialAttributes], di
	
new_game:
	lea rax, ['*']
	mov rcx, boardLength
	lea rdi, [board]
	rep stosb
	
	mov BYTE PTR [turn], 0
	mov BYTE PTR [xCursor], 0
	mov BYTE PTR [yCursor], 0
	
	call [ClearScreen]
	
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr di, 1
	sub di, (BOARD_ROWS / 2)
	
	shl edi, 16
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr di, 1
	sub di, (BOARD_COLS / 2)
	
	mov rcx, [output]
	movsxd rdx, edi
	call [SetConsoleCursorPosition]
	
	lea rcx, [board]
	call PrintBoard
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rcx, [board]
	mov rdx, 1
	call Print
	
game_loop:
	mov rcx, [input]
	lea rdx, [INPUT_RECORD]
	mov r8, 1
	mov r9, rsp
	call [ReadConsoleInputA]
	
	movzx rax, WORD PTR [INPUT_RECORD]
	cmp rax, 1 ; KEY_EVENT
	jne game_loop
	
	movsxd rax, DWORD PTR [INPUT_RECORD + 4]
	test rax, rax
	jz game_loop
	
	movzx rax, [INPUT_RECORD + 10]
	cmp rax, 26h ; VK_UP
	je up_arrow
	cmp rax, 28h ; VK_DOWN
	je down_arrow
	cmp rax, 25h ; VK_LEFT
	je left_arrow
	cmp rax, 27h ; VK_RIGHT
	je right_arrow
	cmp rax, 20h ; VK_SPACE
	je check_mark
	cmp rax, 1bh ; VK_ESCAPE
	je exit
	jmp game_loop
	
up_arrow:
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], '*'
	mov rsi, FOREGROUND_BOARD
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [yCursor]
	mov rsi, BOARD_ROWS
	
	cmp rdi, 0
	cmove rdi, rsi
	dec rdi
	
	mov BYTE PTR [yCursor], dil
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr si, 1
	sub si, (BOARD_ROWS / 2)
	movzx di, [yCursor]
	add si, di
	
	shl esi, 16
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr si, 1
	sub si, (BOARD_COLS / 2)
	movzx di, [xCursor]
	shl di, 1
	add si, di
	
	mov rcx, [output]
	movsxd rdx, esi
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	mov rcx, [output]
	mov rdx, FOREGROUND_BOARD
	call [SetConsoleTextAttribute]
	
	jmp game_loop
	
down_arrow:
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], '*'
	mov rsi, FOREGROUND_BOARD
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [yCursor]
	mov rsi, 0
	
	inc rdi
	cmp rdi, BOARD_ROWS
	cmovge rdi, rsi
	
	mov BYTE PTR [yCursor], dil
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr si, 1
	sub si, (BOARD_ROWS / 2)
	movzx di, [yCursor]
	add si, di
	
	shl esi, 16
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr si, 1
	sub si, (BOARD_COLS / 2)
	movzx di, [xCursor]
	shl di, 1
	add si, di
	
	mov rcx, [output]
	movsxd rdx, esi
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	mov rcx, [output]
	mov rdx, FOREGROUND_BOARD
	call [SetConsoleTextAttribute]
	
	jmp game_loop
	
left_arrow:
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], '*'
	mov rsi, FOREGROUND_BOARD
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [xCursor]
	mov rsi, (BOARD_COLS - SPACES)
	
	cmp rdi, 0
	cmove rdi, rsi
	dec rdi
	
	mov BYTE PTR [xCursor], dil
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr si, 1
	sub si, (BOARD_ROWS / 2)
	movzx di, [yCursor]
	add si, di
	
	shl esi, 16
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr si, 1
	sub si, (BOARD_COLS / 2)
	movzx di, [xCursor]
	shl di, 1
	add si, di
	
	mov rcx, [output]
	movsxd rdx, esi
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	mov rcx, [output]
	mov rdx, FOREGROUND_BOARD
	call [SetConsoleTextAttribute]
	
	jmp game_loop
	
right_arrow:
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], '*'
	mov rsi, FOREGROUND_BOARD
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [xCursor]
	mov rsi, 0
	
	inc rdi
	cmp rdi, (BOARD_COLS - SPACES)
	cmovge rdi, rsi
	
	mov BYTE PTR [xCursor], dil
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr si, 1
	sub si, (BOARD_ROWS / 2)
	movzx di, [yCursor]
	add si, di
	
	shl esi, 16
	
	mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr si, 1
	sub si, (BOARD_COLS / 2)
	movzx di, [xCursor]
	shl di, 1
	add si, di
	
	mov rcx, [output]
	movsxd rdx, esi
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	mov rcx, [output]
	mov rdx, FOREGROUND_BOARD
	call [SetConsoleTextAttribute]
	
	jmp game_loop
	
check_mark:
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	imul rdi, (BOARD_COLS - SPACES)
	
	lea rbx, [board]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], '*'
	je place_mark
	jmp game_loop
	
place_mark:
	xor [turn], 1
	
	cmp [turn], 0
	movzx rax, [cross]
	movzx rbx, [circle]
	cmove rax, rbx
	
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	imul rdi, (BOARD_COLS - SPACES)
	
	lea rbx, [board]
	add rbx, rdi
	add rbx, rsi
	mov BYTE PTR [rbx], al
	
	cmp rax, 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp rax, 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	cmp [turn], 0
	lea rax, [cross]
	lea rbx, [circle]
	cmove rax, rbx
	
	lea rcx, [rax]
	mov rdx, 1
	call Print
	
	movzx rcx, [yCursor]
	movzx rdx, [xCursor]
	call CheckWin
	cmp rax, 1
	je new_game
	
	@@:
		mov rcx, [input]
		lea rdx, [INPUT_RECORD]
		mov r8, 1
		mov r9, rsp
		call [ReadConsoleInputA]
		
		movzx rax, WORD PTR [INPUT_RECORD]
		cmp rax, 1 ; KEY_EVENT
		jne @b
		
		movsxd rax, DWORD PTR [INPUT_RECORD + 4]
		test rax, rax
		jz @b
		
		movzx rax, [INPUT_RECORD + 10]
		cmp rax, 25h ; VK_LEFT
		je rotate_left
		cmp rax, 27h ; VK_RIGHT
		je rotate_right
		cmp rax, 1bh ; VK_ESCAPE
		je exit
		jmp @b
		
rotate_left:
	movzx rcx, [yCursor]
	movzx rdx, [xCursor]
	call Transpose
	
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	
	mov r8, (BOARD_ROWS / 2)
	mov r9, ((BOARD_COLS - SPACES) / 2)
	xor r10, r10
	xor r11, r11
	
	cmp rdi, r8
	cmovge r10, r8
	cmp rsi, r9
	cmovge r11, r9
	
	xor rdi, rdi
	xor rsi, rsi
	
	swap_columns:
		mov r8, rdi
		add r8, r10
		imul r8, (BOARD_COLS - SPACES)
		lea rbx, [board]
		add rbx, r8
		add rbx, rsi
		add rbx, r11
		
		lea r9, [rbx]
		
		lea rbx, [board]
		add rbx, r8
		add rbx, (((BOARD_COLS - SPACES) / 2) - 1)
		sub rbx, rsi
		add rbx, r11
		
		mov r8, [r9]
		mov r12, [rbx]
		
		mov BYTE PTR [r9], r12b
		mov BYTE PTR [rbx], r8b
		
		inc rdi
		cmp rdi, (BOARD_ROWS / 2)
		jne swap_columns
		
		xor rdi, rdi
		
		inc rsi
		cmp rsi, ((BOARD_COLS - SPACES) / 4)
		jne swap_columns
		
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr di, 1
	sub di, (BOARD_ROWS / 2)
	
	shl edi, 16
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr di, 1
	sub di, (BOARD_COLS / 2)
	
	mov rcx, [output]
	movsxd rdx, edi
	call [SetConsoleCursorPosition]
	
	lea rcx, [board]
	call PrintBoard
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	
	mov r8, (BOARD_ROWS / 2)
	mov r9, ((BOARD_COLS - SPACES) / 2)
	xor r10, r10
	xor r11, r11
	
	cmp rdi, r8
	cmovge r10, r8
	cmp rsi, r9
	cmovge r11, r9
	
	mov rdi, r10
	mov rsi, r11
	add r8, r10
	add r9, r11
	
	@@:
		mov [rsp + 8 + SHADOW_SPACE], rdi
		mov [rsp + 8 + SHADOW_SPACE + 8], rsi
		mov [rsp + 8 + SHADOW_SPACE + 16], r8
		mov [rsp + 8 + SHADOW_SPACE+ 24], r9
		
		mov rcx, rdi
		mov rdx, rsi
		call CheckWin
		cmp rax, 1
		je new_game
		
		mov r8, (BOARD_ROWS / 2)
		mov r9, ((BOARD_COLS - SPACES) / 2)
		xor r10, r10
		xor r11, r11
		
		mov rdi, [rsp + 8 + SHADOW_SPACE]
		mov rsi, [rsp + 8 + SHADOW_SPACE + 8]
		mov r8, [rsp + 8 + SHADOW_SPACE + 16]
		mov r9, [rsp + 8 + SHADOW_SPACE + 24]
		
		inc rsi
		cmp rsi, r9
		jne @b
		
		xor rsi, rsi
		
		inc rdi
		cmp rdi, r8
		jne @b
		
	call CheckDraw
	cmp rax, 1
	je new_game
	
	jmp game_loop
	
rotate_right:
	movzx rcx, [yCursor]
	movzx rdx, [xCursor]
	call Transpose
	
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	
	mov r8, (BOARD_ROWS / 2)
	mov r9, ((BOARD_COLS - SPACES) / 2)
	xor r10, r10
	xor r11, r11
	
	cmp rdi, r8
	cmovge r10, r8
	cmp rsi, r9
	cmovge r11, r9
	
	xor rdi, rdi
	xor rsi, rsi
	
	swap_rows:
		mov r8, rdi
		add r8, r10
		imul r8, (BOARD_COLS - SPACES)
		lea rbx, [board]
		add rbx, r8
		add rbx, rsi
		add rbx, r11
		
		lea r9, [rbx]
		
		lea rbx, [board]
		mov r8, (((BOARD_COLS - SPACES) / 2) - 1)
		sub r8, rdi
		add r8, r10
		imul r8, (BOARD_COLS - SPACES)
		add rbx, r8
		add rbx, rsi
		add rbx, r11
		
		mov r8, [r9]
		mov r12, [rbx]
		
		mov BYTE PTR [r9], r12b
		mov BYTE PTR [rbx], r8b
		
		inc rsi
		cmp rsi, ((BOARD_COLS - SPACES) / 2)
		jne swap_rows
		
		xor rsi, rsi
		
		inc rdi
		cmp rdi, (BOARD_ROWS / 4)
		jne swap_rows
		
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	shr di, 1
	sub di, (BOARD_ROWS / 2)
	
	shl edi, 16
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	shr di, 1
	sub di, (BOARD_COLS / 2)
	
	mov rcx, [output]
	movsxd rdx, edi
	call [SetConsoleCursorPosition]
	
	lea rcx, [board]
	call PrintBoard
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	movzx rdi, [yCursor]
	movzx rsi, [xCursor]
	
	mov r8, (BOARD_ROWS / 2)
	mov r9, ((BOARD_COLS - SPACES) / 2)
	xor r10, r10
	xor r11, r11
	
	cmp rdi, r8
	cmovge r10, r8
	cmp rsi, r9
	cmovge r11, r9
	
	mov rdi, r10
	mov rsi, r11
	add r8, r10
	add r9, r11
	
	@@:
		mov [rsp + 8 + SHADOW_SPACE], rdi
		mov [rsp + 8 + SHADOW_SPACE + 8], rsi
		mov [rsp + 8 + SHADOW_SPACE + 16], r8
		mov [rsp + 8 + SHADOW_SPACE+ 24], r9
		
		mov rcx, rdi
		mov rdx, rsi
		call CheckWin
		cmp rax, 1
		je new_game
		
		mov r8, (BOARD_ROWS / 2)
		mov r9, ((BOARD_COLS - SPACES) / 2)
		xor r10, r10
		xor r11, r11
		
		mov rdi, [rsp + 8 + SHADOW_SPACE]
		mov rsi, [rsp + 8 + SHADOW_SPACE + 8]
		mov r8, [rsp + 8 + SHADOW_SPACE + 16]
		mov r9, [rsp + 8 + SHADOW_SPACE + 24]
		
		inc rsi
		cmp rsi, r9
		jne @b
		
		xor rsi, rsi
		
		inc rdi
		cmp rdi, r8
		jne @b
		
	call CheckDraw
	cmp rax, 1
	je new_game
	
	jmp game_loop
	
exit:
	; Enable window resizing
	
	call [GetConsoleWindow]
	mov rdi, rax
	
	mov rcx, rdi
	mov rdx, GWL_STYLE
	call [GetWindowLongPtrA]
	mov rsi, rax
	
	mov r8, WS_MAXIMIZEBOX
	or rsi, r8
	mov r8, WS_SIZEBOX
	or rsi, r8
	
	mov rcx, rdi
	mov rdx, GWL_STYLE
	mov r8, rsi
	call [SetWindowLongPtrA]
	
	; Show cursor
	
	mov rcx, [output]
	lea rdx, [CONSOLE_CURSOR_INFO]
	call [GetConsoleCursorInfo]
	
	mov DWORD PTR [CONSOLE_CURSOR_INFO + 4], 1
	
	mov rcx, [output]
	lea rdx, [CONSOLE_CURSOR_INFO]
	call [SetConsoleCursorInfo]
	
	; Restore the initial text attributes the console window had before starting this program
	
	mov rcx, [output]
	movzx rdx, [initialAttributes]
	call [SetConsoleTextAttribute]
	
	call [ClearScreen]
	
	xor rcx, rcx
	call [ExitProcess]
	
IFDEF _DEBUG
main ENDP
ELSE
mainCRTStartup ENDP
ENDIF

Transpose PROC
	sub rsp, (8 + SHADOW_SPACE)
	
	mov rdi, rcx
	mov rsi, rdx
	
	mov r8, (BOARD_ROWS / 2)
	mov r9, ((BOARD_COLS - SPACES) / 2)
	xor r10, r10
	xor r11, r11
	
	cmp rdi, r8
	cmovge r10, r8
	cmp rsi, r9
	cmovge r11, r9
	
	xor r12, r12
	xor rdi, rdi
	xor rsi, rsi
	
	transpose_loop:
		add rsi, r12
		
		@@:
			mov r8, rdi
			add r8, r10
			imul r8, (BOARD_COLS - SPACES)
			lea rbx, [board]
			add rbx, r8
			add rbx, rsi
			add rbx, r11
			
			lea r8, [rbx]
			
			mov r9, rsi
			add r9, r10
			imul r9, (BOARD_COLS - SPACES)
			lea rbx, [board]
			add rbx, rdi
			add rbx, r9
			add rbx, r11
			
			mov r9, [r8]
			mov r13, [rbx]
			
			mov BYTE PTR [r8], r13b
			mov BYTE PTR [rbx], r9b
			
			inc rsi
			cmp rsi, ((BOARD_COLS - SPACES) / 2)
			jne @b
			
			inc r12
			xor rsi, rsi
			
			inc rdi
			cmp rdi, (BOARD_ROWS / 2)
			jne transpose_loop
			
	add rsp, (8 + SHADOW_SPACE)
	ret	
Transpose ENDP

CheckDraw PROC
	sub rsp, (8 + SHADOW_SPACE)
	
	xor rdi, rdi
	
	@@:
		lea rbx, [board]
		add rbx, rdi
		
		cmp BYTE PTR [rbx], '*'
		je return_check_draw
		
		inc rdi
		cmp rdi, boardLength
		jne @b
		
	lea rbx, [board]
	movzx rdi, [yCursor]
	imul rdi, (BOARD_COLS - SPACES)
	movzx rsi, [xCursor]
	add rbx, rdi
	add rbx, rsi
	cmp BYTE PTR [rbx], 'X'
	mov rsi, FOREGROUND_CROSS
	cmove rdi, rsi
	cmp BYTE PTR [rbx], 'O'
	mov rsi, FOREGROUND_CIRCLE
	cmove rdi, rsi
	
	mov rcx, [output]
	mov rdx, rdi
	call [SetConsoleTextAttribute]
	
	lea rcx, [rbx]
	mov rdx, 1
	call Print
	
	mov rcx, [output]
	mov rdx, 0
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	mov rdx, FOREGROUND_CURSOR
	call [SetConsoleTextAttribute]
	
	lea rcx, [draw]
	mov rdx, 1
	call Print
	
	@@:
		mov rcx, [input]
		lea rdx, [INPUT_RECORD]
		mov r8, 1
		mov r9, rsp
		call [ReadConsoleInputA]
		
		movzx rax, WORD PTR [INPUT_RECORD]
		cmp rax, 1 ; KEY_EVENT
		jne @b
		
		movsxd rax, DWORD PTR [INPUT_RECORD + 4]
		test rax, rax
		jz @b
		
		mov rax, 1
		
	return_check_draw:
		add rsp, (8 + SHADOW_SPACE)
		ret	
CheckDraw ENDP

CheckWin PROC
	sub rsp, (8 + SHADOW_SPACE) + 16
	
	vertical_check:
		mov rdi, 0
		mov rsi, rdx
		xor r8, r8
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je vertical_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je vertical_check_loop
		
		add rdi, (BOARD_COLS - SPACES)
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je vertical_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		jne horizontal_check
		
		vertical_check_loop:
			lea rbx, [winners]
			add rbx, r8
			mov BYTE PTR [rbx + 1], dil
			add BYTE PTR [rbx + 1], sil
			
			inc r8
			cmp r8, 5
			je winner
			
			add rdi, (BOARD_COLS - SPACES)
			
			lea rbx, [board]
			add rbx, rdi
			add rbx, rsi
			
			cmp BYTE PTR [rbx], al
			jne horizontal_check
			jmp vertical_check_loop
			
	horizontal_check:
		mov rdi, rcx
		mov rsi, 0
		xor r8, r8
		
		imul rdi, (BOARD_COLS-SPACES)
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je horizontal_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je horizontal_check_loop
		
		inc rsi
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je horizontal_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		jne diagonal1_check
		
		horizontal_check_loop:
			lea rbx, [winners]
			add rbx, r8
			mov BYTE PTR [rbx + 1], dil
			add BYTE PTR [rbx + 1], sil
			
			inc r8
			cmp r8, 5
			je winner
			
			inc rsi
			
			lea rbx, [board]
			add rbx, rdi
			add rbx, rsi
			
			cmp BYTE PTR [rbx], al
			jne diagonal1_check
			jmp horizontal_check_loop
			
	diagonal1_check:
		mov rdi, rcx
		mov rsi, rdx
		
		mov r8, rdi
		sub r8, rsi
		mov r9, r8
		neg r8
		cmovl r8, r9
		
		cmp r8, 1
		jg diagonal2_check
		
		xor r9, r9
		
		cmp rdi, rsi
		cmovg rdi, r8
		cmovg rsi, r9
		cmovl rdi, r9
		cmovl rsi, r8
		cmove rdi, r9
		cmove rsi, r9
		
		xor r8, r8
		
		imul rdi, (BOARD_COLS - SPACES)
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal1_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal1_check_loop
		
		add rdi, (BOARD_COLS - SPACES)
		inc rsi
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal1_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		jne diagonal2_check
		
		diagonal1_check_loop:
			lea rbx, [winners]
			add rbx, r8
			mov BYTE PTR [rbx + 1], dil
			add BYTE PTR [rbx + 1], sil
			
			inc r8
			cmp r8, 5
			je winner
			
			add rdi, (BOARD_COLS - SPACES)
			inc rsi
			
			lea rbx, [board]
			add rbx, rdi
			add rbx, rsi
			
			cmp BYTE PTR [rbx], al
			jne diagonal2_check
			jmp diagonal1_check_loop
			
	diagonal2_check:
		mov rdi, rcx
		mov rsi, rdx
		mov r8, rdi
		
		mov r8, rdi
		mov r9, (BOARD_COLS - SPACES - 1)
		sub r9, rsi
		sub r8, r9
		mov r9, r8
		neg r8
		cmovl r8, r9
		
		cmp r8, 1
		jg return_check_winner
		
		mov r9, (BOARD_COLS - SPACES - 1)
		sub r9, rsi
		mov rsi, r9
		mov r9, (BOARD_COLS - SPACES - 1)
		mov r10, r9
		sub r10, r8
		
		cmp rdi, rsi
		cmovg rdi, r8
		cmovg rsi, r9
		mov r8, 0
		cmovl rdi, r8
		cmovl rsi, r10
		cmove rdi, r8
		cmove rsi, r9
		
		xor r8, r8
		
		imul rdi, (BOARD_COLS - SPACES)
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal2_check_loop
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal2_check_loop
		
		add rdi, (BOARD_COLS - SPACES)
		dec rsi
		
		lea rbx, [board]
		add rbx, rdi
		add rbx, rsi
		
		movzx rax, [cross]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		je diagonal2_check_loop
		
		movzx rax, [circle]
		cmp BYTE PTR [rbx], al
		mov BYTE PTR [winners], al
		jne return_check_winner
		
		diagonal2_check_loop:
			lea rbx, [winners]
			add rbx, r8
			mov BYTE PTR [rbx + 1], dil
			add BYTE PTR [rbx + 1], sil
			
			inc r8
			cmp r8, 5
			je winner
			
			add rdi, (BOARD_COLS - SPACES)
			dec rsi
			
			lea rbx, [board]
			add rbx, rdi
			add rbx, rsi
			
			cmp BYTE PTR [rbx], al
			jne return_check_winner
			jmp diagonal2_check_loop
			
	winner:
		lea rbx, [board]
		movzx rdi, [yCursor]
		imul rdi, (BOARD_COLS - SPACES)
		movzx rsi, [xCursor]
		add rbx, rdi
		add rbx, rsi
		cmp BYTE PTR [rbx], '*'
		mov rsi, FOREGROUND_BOARD
		cmove rdi, rsi
		cmp BYTE PTR [rbx], 'X'
		mov rsi, FOREGROUND_CROSS
		cmove rdi, rsi
		cmp BYTE PTR [rbx], 'O'
		mov rsi, FOREGROUND_CIRCLE
		cmove rdi, rsi
		
		mov rcx, [output]
		mov rdx, rdi
		call [SetConsoleTextAttribute]
		
		lea rcx, [rbx]
		mov rdx, 1
		call Print
		
		xor r8, r8
		
		draw_winners:
			lea rbx, [winners]
			add rbx, r8
			movzx rdi, BYTE PTR [rbx + 1]
			
			mov [rsp + 8 + SHADOW_SPACE], r8
			
			mov rcx, [output]
			lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
			call [GetConsoleScreenBufferInfo]
			
			mov rax, rdi
			xor rdx, rdx
			mov rsi, (BOARD_COLS - SPACES)
			div rsi
			shl dx, 1
			
			mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
			shr si, 1
			sub si, (BOARD_ROWS / 2)
			add si, ax
			
			shl esi, 16
			
			mov si, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
			shr si, 1
			sub si, (BOARD_COLS / 2)
			add si, dx
			
			mov rcx, [output]
			movsxd rdx, esi
			call [SetConsoleCursorPosition]
			
			mov rcx, [output]
			mov rdx, FOREGROUND_CURSOR
			call [SetConsoleTextAttribute]
			
			lea rcx, [winners]
			mov rdx, 1
			call Print
			
			mov r8, [rsp + 8 + SHADOW_SPACE]
			
			inc r8
			cmp r8, (winnersLength - 1)
			jne draw_winners
			
		mov rcx, [output]
		mov rdx, 0
		call [SetConsoleCursorPosition]
		
		movzx rax, [winners]
		
		cmp rax, 'X'
		mov rsi, FOREGROUND_CROSS
		cmove rdi, rsi
		cmp rax, 'O'
		mov rsi, FOREGROUND_CIRCLE
		cmove rdi, rsi
		
		mov rcx, [output]
		mov rdx, rdi
		call [SetConsoleTextAttribute]
		
		lea rcx, [winners]
		mov rdx, 1
		call Print
		
	@@:
		mov rcx, [input]
		lea rdx, [INPUT_RECORD]
		mov r8, 1
		mov r9, rsp
		call [ReadConsoleInputA]
		
		movzx rax, WORD PTR [INPUT_RECORD]
		cmp rax, 1 ; KEY_EVENT
		jne @b
		
		movsxd rax, DWORD PTR [INPUT_RECORD + 4]
		test rax, rax
		jz @b
		
		mov rax, 1
		
	return_check_winner:
		add rsp, (8 + SHADOW_SPACE) + 16
		ret	
CheckWin EndP

Print PROC
	mov [rsp + 16], rdx
	mov [rsp + 8], rcx
	sub rsp, (8 + SHADOW_SPACE)
	
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	mov rcx, [output]
	mov rdx, [rsp + 8 + SHADOW_SPACE + 8]
	mov r8, [rsp + 8 + SHADOW_SPACE + 16]
	lea r9, [rsp + SHADOW_SPACE]
	mov QWORD PTR [rsp + SHADOW_SPACE], 0
	call [WriteConsoleA]
	
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 6]
	shl edi, 16
	mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 4]
	
	mov rcx, [output]
	movsxd rdx, edi
	call [SetConsoleCursorPosition]
	
	add rsp, (8 + SHADOW_SPACE)
	ret	
Print ENDP

PrintBoard PROC
	mov [rsp + 8], rcx
	sub rsp, (8 + SHADOW_SPACE)
	xor rsi, rsi
	
	print_loop:
		mov rcx, [rsp + 8 + SHADOW_SPACE + 8]
		
		lea rbx, [rcx + rsi]
		cmp BYTE PTR [rbx], '*'
		mov r9, FOREGROUND_BOARD
		cmove r8, r9
		cmp BYTE PTR [rbx], 'X'
		mov r9, FOREGROUND_CROSS
		cmove r8, r9
		cmp BYTE PTR [rbx], 'O'
		mov r9, FOREGROUND_CIRCLE
		cmove r8, r9
		
		mov rcx, [output]
		mov rdx, r8
		call [SetConsoleTextAttribute]
		
		lea rcx, [rbx]
		mov rdx, 1
		call Print
		
		inc rsi
		
		mov rax, rsi
		xor rdx, rdx
		mov rcx, (BOARD_COLS - SPACES)
		div rcx
		cmp rdx, 0
		je adjust_cursor
		
		mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 6]
		shl edi, 16
		mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 4]
		inc di
		
		mov rcx, [output]
		movsxd rdx, edi
		call [SetConsoleCursorPosition]
		
		lea rcx, [space]
		mov rdx, 1
		call Print
		
		mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 6]
		shl edi, 16
		mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 4]
		inc di
		
		mov rcx, [output]
		movsxd rdx, edi
		call [SetConsoleCursorPosition]
		
		jmp print_loop
		
		adjust_cursor:
			mov rcx, [output]
			lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
			call [GetConsoleScreenBufferInfo]
			
			mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 6]
			add di, 1
			shl edi, 16
			mov di, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
			shr di, 1
			sub di, (BOARD_COLS / 2)
			
			mov rcx, [output]
			movsxd rdx, edi
			call [SetConsoleCursorPosition]
			
			cmp rsi, boardLength
			jl print_loop
			
			mov rcx, [output]
			lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
			call [GetConsoleScreenBufferInfo]
			
			movzx di, [CONSOLE_SCREEN_BUFFER_INFO + 16]
			shr di, 1
			sub di, (BOARD_ROWS / 2)
			movzx si, [yCursor]
			add di, si
			
			shl edi, 16
			
			movzx di, [CONSOLE_SCREEN_BUFFER_INFO + 14]
			shr di, 1
			sub di, (BOARD_COLS / 2)
			movzx si, [xCursor]
			shl si, 1
			add di, si
			
			mov rcx, [output]
			mov rdx, rdi
			call [SetConsoleCursorPosition]
			
	add rsp, (8 + SHADOW_SPACE)
	ret
PrintBoard ENDP

ClearScreen PROC
	sub rsp, (8 + SHADOW_SPACE)
	
	mov rcx, [output]
	mov rdx, 0
	call [SetConsoleCursorPosition]
	
	mov rcx, [output]
	lea rdx, [CONSOLE_SCREEN_BUFFER_INFO]
	call [GetConsoleScreenBufferInfo]
	
	movzx rdi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	movzx rsi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	
	mov WORD PTR [SMALL_RECT], 0
	mov WORD PTR [SMALL_RECT + 2], 0
	mov WORD PTR [SMALL_RECT + 4], si
	mov WORD PTR [SMALL_RECT + 6], di
	
	movzx rsi, [space]
	mov WORD PTR [CHAR_INFO], si
	
	movzx rsi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 8]
	mov WORD PTR [CHAR_INFO + 2], si
	
	lea rsi, [CHAR_INFO]
	
	mov rcx, [output]
	lea rdx, [SMALL_RECT]
	mov r8, 0
	movsxd r9, edi
	lea r9, [CHAR_INFO]
	mov [rsp + SHADOW_SPACE], rsi
	call [ScrollConsoleScreenBufferA]
	
	movzx rdi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 16]
	movzx rsi, WORD PTR [CONSOLE_SCREEN_BUFFER_INFO + 14]
	imul rdi, rsi
	
	mov rcx, [output]
	movzx rdx, [space]
	mov r8, rdi
	mov r9, 0
	mov [rsp + SHADOW_SPACE], rsp
	call [FillConsoleOutputCharacterA]
	
	lea rcx, [cls]
	mov rdx, clslen
	call Print
	
	add rsp, (8 + SHADOW_SPACE)
	ret
ClearScreen ENDP

END
