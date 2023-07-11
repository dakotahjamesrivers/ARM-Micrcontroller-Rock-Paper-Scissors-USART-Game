Dako
;***********************************************************
;*
;*  	Lab 8: Rock Paper Scissors
;*
;***********************************************************
;*
;*	 Author: Elijah Cirioli And Dakotah Rivers
;*	   Date: 11/21/2022
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16               ; Multi-Purpose Register
.def	mpr2 = r23				; A second Multi-Purpose Register
.def	state = r28				; The current screen the game is in
.def	selection = r18			; This player's selection (0=None, 1=Rock, 2=Paper, 3=Scissors)
.def	opponentSelection = r29	; The other player's selection (0=None, 1=Rock, 2=Paper, 3=Scissors, ReadyMessage=Ready)
.def	ilcnt = r24				; Inner Loop Counter
.def	olcnt = r25				; Outer Loop Counter

.equ    ReadyMessage = $FF		; The message indicating a player is ready

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
	rjmp    INIT				; Reset interrupt

.org	$0032					; Receive complete interrupt
	rcall	USART_RECEIVE
	reti

.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
	; Initialize stack pointer
	ldi		mpr, low(RAMEND)
	out		SPL, mpr		; Load SPL with low byte of RAMEND
	ldi		mpr, high(RAMEND)
	out		SPH, mpr		; Load SPH with high byte of RAMEND

	; Port D
	ldi		mpr, 0b00001000 ; Set pin 3 (Tx) for output
	out		DDRD, mpr

	ldi		mpr, 0b11110111 ; Enable pull-up resistors
	out		PORTD, mpr

	; Port B
	ldi		mpr, $FF
	out		DDRB, mpr

	; USART1	
	ldi		mpr, 0b00100000	; 8 data bits, clear UDRE1 bit
	sts		UCSR1A, mpr

	ldi		mpr, 0b10011000	; Receive enabled, transmitter enabled, receive complete interrupt enabled
	sts		UCSR1B, mpr	

	ldi		mpr, 0b00001110	; Asynchronous mode, 8 data bits, 2 stop bits, no parity bit
	sts		UCSR1C, mpr		
	
	; Set baud rate to 2400 bps
	ldi		mpr, 0		
	sts		UBRR1H, mpr
	ldi		mpr, 207					
	sts		UBRR1L, mpr

	;Enable receiver and transmitter
	;Set frame format: 8 data bits, 2 stop bits

	; TIMER/COUNTER1
	ldi		mpr, 0
	sts		TCCR1A, mpr			; Normal mode
	ldi		mpr, 0b00000100		; 256 prescale
	sts		TCCR1B, mpr

	; Clear important registers
	clr		state
	clr		selection
	clr		opponentSelection
	
	; Setup LCD
	rcall	LCDInit		
	rcall	LCDBacklightOn
	rcall	LCDClr

	; Enable interrupts globally
	sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
	; State 0 | Welcome screen
	cpi		state, 0
	brne	ELIF_STATE_1
	rcall	DISPLAY_WELCOME					; Display the welcome message
	in		mpr, PIND						; Read in button inputs from port D
	andi	mpr, 0b10000000					; Isolate PD7
	brne	MAIN							; Loop if it isn't pressed
	ldi		state, 1						; Move into state 1
	rcall	USART_SEND_READY				; Send the ready message to the other player
	rcall	BUSY_WAIT						; Busy wait for switch debouncing
	cpi		opponentSelection, ReadyMessage	; See if the opponent is already ready
	brne	MAIN							
	ldi		state, 2						; If they are then skip straight to state 2
	clr		selection						
	clr		opponentSelection
	rcall	START_6_SECOND_TIMER			; Start the 6 second countdown
	rjmp	MAIN

ELIF_STATE_1:
	; State 1 | Waiting for opponent screen
	cpi		state, 1
	brne	ELIF_STATE_2
	rcall	DISPLAY_READY					; Display the waiting message
	rjmp	MAIN

ELIF_STATE_2:
	; State 2 | Choosing rock/paper/scissors screen
	cpi		state, 2
	brne	ELIF_STATE_3	
	rcall	DISPLAY_SELECTION				; Display the current selection
	rcall	UPDATE_TIMER_LEDS				; Decrement the timer LEDs if necessary
	in		mpr, PIND						; Read in button inputs from port D
	andi	mpr, 0b00010000					; Isolate PD4
	brne	MAIN							; Loop if it isn't pressed
	rcall	CHANGE_SELECTION				; Change between rock, paper, and scissors
	rcall	BUSY_WAIT						; Busy wait for switch debouncing
	rjmp	MAIN

ELIF_STATE_3:
	; State 3 | Displaying opponents selection screen
	cpi		state, 3
	brne	ELIF_STATE_4
	rcall	DISPLAY_SELECTION				; Display the user's selection
	rcall	DISPLAY_OPPONENT_SELECTION		; Display the selection from the other board
	rcall	UPDATE_TIMER_LEDS				; Decrement the timer LEDs if necessary
	rjmp	MAIN

ELIF_STATE_4:
	; State 4 | Displaying whether you won or lost
	cpi		state, 4
	brne	MAIN
	rcall	DISPLAY_RESULT					; Display whether the user won or last
	rcall	DISPLAY_SELECTION				; Display the user's selection
	rcall	UPDATE_TIMER_LEDS				; Decrement the timer LEDs if necessary
	rjmp	MAIN


;***********************************************************
;*	Functions and Subroutines
;***********************************************************

;----------------------------------------------------------------
; Sub:	WRITE_CHARACTERS
; Desc:	Copies a set amount of characters from program memory 
;		to data memory
;----------------------------------------------------------------
WRITE_CHARACTERS:
	lpm		mpr2, Z+						; Load a character from program memory into mpr2
	st		X+, mpr2						; Store that character into SRAM and increment X
	dec		mpr								; Repeat until mpr is 0
	brne	WRITE_CHARACTERS
	ret


;----------------------------------------------------------------
; Sub:	DISPLAY_WELCOME
; Desc:	Displays the welcome screen message on the LCD
;----------------------------------------------------------------
DISPLAY_WELCOME:
	push	mpr			; Save mpr register
	push	mpr2		; Save mpr2 register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state

	; Set Z to start of WELCOME_STRING
	ldi		ZH, high(WELCOME_STRING << 1)
	ldi		ZL, low(WELCOME_STRING << 1)

	; Set X to start of LCD
	ldi		XH, $01
	ldi		XL, $00

	; Copy one byte at a time
	ldi		mpr, 32
	rcall	WRITE_CHARACTERS
	rcall	LCDWrite

	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr2		; Restore mpr2
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	DISPLAY_READY
; Desc:	Displays the waiting screen message on the LCD
;----------------------------------------------------------------
DISPLAY_READY:
	push	mpr			; Save mpr register
	push	mpr2		; Save mpr2 register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state

	; Set Z to start of READY_STRING
	ldi		ZH, high(READY_STRING << 1)
	ldi		ZL, low(READY_STRING << 1)

	; Set X to start of LCD
	ldi		XH, $01
	ldi		XL, $00

	; Copy one byte at a time
	ldi		mpr, 32
	rcall	WRITE_CHARACTERS
	rcall	LCDWrite

	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr2		; Restore mpr2
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	CHANGE_SELECTION
; Desc:	Cycles the current selection through rock, paper, and scissors
;----------------------------------------------------------------
CHANGE_SELECTION:
	push	mpr							; Save mpr register
	in		mpr, SREG					; Load program state to mpr
	push	mpr							; Save program state

	inc		selection					; Increment the current selection
	cpi		selection, 4				; If selection is 4, wrap it to 1 (rock)
	brne	CHANGE_SELECTION_END
	ldi		selection, 1

CHANGE_SELECTION_END:
	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	DISPLAY_SELECTION
; Desc:	Displays the current selection on the LCD
;----------------------------------------------------------------
DISPLAY_SELECTION:
	push	mpr			; Save mpr register
	push	mpr2		; Save mpr2 register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state

	; Set X to start of LCD
	ldi		XH, $01
	ldi		XL, $00
	
	; If we are in state 2 then don't write anything on the first line
	cpi		state, 2
	brne	DISPLAY_SELECTION_SECOND_LINE

	; Set Z to start of START_STRING
	ldi		ZH, high(START_STRING << 1)
	ldi		ZL, low(START_STRING << 1)

	; Copy one byte at a time
	ldi		mpr, 16
	rcall	WRITE_CHARACTERS
	rcall	LCDWrLn1

DISPLAY_SELECTION_SECOND_LINE:
	; If selection is 0 then display a blank line
	cpi		selection, 0
	breq	DISPLAY_SELECTION_NONE
	
	; If selection is 1 then display "Rock"
	cpi		selection, 1
	brne	DISPLAY_SELECTION_PAPER
	ldi		ZH, high(ROCK_STRING << 1)
	ldi		ZL, low(ROCK_STRING << 1)
	rjmp	DISPLAY_SELECTION_WRITE

DISPLAY_SELECTION_PAPER:
	; If selection is 2 then display "Paper"
	cpi		selection, 2
	brne	DISPLAY_SELECTION_SCISSORS
	ldi		ZH, high(PAPER_STRING << 1)
	ldi		ZL, low(PAPER_STRING << 1)
	rjmp	DISPLAY_SELECTION_WRITE

DISPLAY_SELECTION_SCISSORS:
	; If selection is 3 then display "Scissors"
	ldi		ZH, high(SCISSORS_STRING << 1)
	ldi		ZL, low(SCISSORS_STRING << 1)
	rjmp	DISPLAY_SELECTION_WRITE

DISPLAY_SELECTION_WRITE:
	; Copy one character at a time to data memory
	ldi		mpr, 16
	ldi		XL, $10
	rcall	WRITE_CHARACTERS
	rcall	LCDWrLn2
	rjmp	DISPLAY_SELECTION_END

DISPLAY_SELECTION_NONE:
	; Clear the second line
	rcall	LCDClrLn2

DISPLAY_SELECTION_END:
	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr2		; Restore mpr2
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	DISPLAY_OPPONENT_SELECTION
; Desc:	Displays the opponent's selection on the LCD
;----------------------------------------------------------------
DISPLAY_OPPONENT_SELECTION:
	push	mpr			; Save mpr register
	push	mpr2		; Save mpr2 register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state

	cpi		opponentSelection, 0				; Check if opponentSelection us 0
	brne	DISPLAY_OPPONENT_SELECTION_ROCK
	rcall	LCDClrLn1							; If it is then display a blank line
	rjmp	DISPLAY_OPPONENT_SELECTION_END

DISPLAY_OPPONENT_SELECTION_ROCK:
	; If opponentSelection is 1 then display "Rock"
	cpi		opponentSelection, 1
	brne	DISPLAY_OPPONENT_SELECTION_PAPER
	ldi		ZH, high(ROCK_STRING << 1)
	ldi		ZL, low(ROCK_STRING << 1)
	rjmp	DISPLAY_OPPONENT_SELECTION_WRITE

DISPLAY_OPPONENT_SELECTION_PAPER:
	; If opponentSelection is 2 then display "Paper"
	cpi		opponentSelection, 2
	brne	DISPLAY_OPPONENT_SELECTION_SCISSORS
	ldi		ZH, high(PAPER_STRING << 1)
	ldi		ZL, low(PAPER_STRING << 1)
	rjmp	DISPLAY_OPPONENT_SELECTION_WRITE

DISPLAY_OPPONENT_SELECTION_SCISSORS:
	; If opponentSelection is 3 then display "Scissors"
	ldi		ZH, high(SCISSORS_STRING << 1)
	ldi		ZL, low(SCISSORS_STRING << 1)
	rjmp	DISPLAY_OPPONENT_SELECTION_WRITE

DISPLAY_OPPONENT_SELECTION_WRITE:
	; Set X to start of LCD
	ldi		XH, $01
	ldi		XL, $00
	
	; Copy one character at a time
	ldi		mpr, 16
	rcall	WRITE_CHARACTERS
	rcall	LCDWrLn1							; Update the first line

DISPLAY_OPPONENT_SELECTION_END:
	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr2		; Restore mpr2
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	DISPLAY_RESULT
; Desc:	Displays whether the user won or lost on the LCD
;----------------------------------------------------------------
DISPLAY_RESULT:
	push	mpr			; Save mpr register
	push	mpr2		; Save mpr2 register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state

	; Check for a draw
	cp		selection, opponentSelection
	brne	DISPLAY_RESULT_ELIF_1			; selection = opponentSelection -> draw
	ldi		ZH, high(DRAW_STRING << 1)
	ldi		ZL, low(DRAW_STRING << 1)
	rjmp	DISPLAY_RESULT_END

DISPLAY_RESULT_ELIF_1:
	; Check for a specific win condition (rock and scissors)
	cpi		selection, 1
	brne	DISPLAY_RESULT_ELIF_2
	cpi		opponentSelection, 3
	breq	DISPLAY_RESULT_ELSE				; selection = 1 && opponentSelection = 3 -> win

DISPLAY_RESULT_ELIF_2:
	; Check for two lose conditions
	cp		selection, opponentSelection
	brge	DISPLAY_RESULT_ELIF_3			; selection < opponentSelection -> lose
	ldi		ZH, high(LOST_STRING << 1)
	ldi		ZL, low(LOST_STRING << 1)
	rjmp	DISPLAY_RESULT_END

DISPLAY_RESULT_ELIF_3:
	; Check for a specific lose condition (scissors and rock)
	cpi		selection, 3
	brne	DISPLAY_RESULT_ELSE
	cpi		opponentSelection, 1
	brne	DISPLAY_RESULT_ELSE				; selection = 3 && opponentSelection = 1 -> lose
	ldi		ZH, high(LOST_STRING << 1)
	ldi		ZL, low(LOST_STRING << 1)
	rjmp	DISPLAY_RESULT_END

DISPLAY_RESULT_ELSE:
	; At this point this must be a win
	ldi		ZH, high(WON_STRING << 1)
	ldi		ZL, low(WON_STRING << 1)

DISPLAY_RESULT_END:
	; Set X to start of LCD
	ldi		XH, $01
	ldi		XL, $00

	; Copy one character at a time
	ldi		mpr, 16
	rcall	WRITE_CHARACTERS
	rcall	LCDWrLn1

	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr2		; Restore mpr2
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	BUSY_WAIT
; Desc:	Busy waits 150 ms for switch debouncing purposes
;----------------------------------------------------------------
BUSY_WAIT:
	push	mpr2			; Save wait register
	push	ilcnt			; Save ilcnt register
	push	olcnt			; Save olcnt register
	ldi		mpr2, 15		; 150 ms
Loop:	
	ldi		olcnt, 224		; load olcnt register
OLoop:	
	ldi		ilcnt, 237		; load ilcnt register
ILoop:	
	dec		ilcnt			; decrement ilcnt
	brne	ILoop			; Continue Inner Loop
	dec		olcnt			; decrement olcnt
	brne	OLoop			; Continue Outer Loop
	dec		mpr2			; Decrement wait
	brne	Loop			; Continue Wait loop

	pop		olcnt			; Restore olcnt register
	pop		ilcnt			; Restore ilcnt register
	pop		mpr2			; Restore wait register

	ret						; Return from subroutine


;----------------------------------------------------------------
; Sub:	START_6_SECOND_TIMER
; Desc:	Starts the LED countdown timer
;----------------------------------------------------------------
START_6_SECOND_TIMER:
	push	mpr			; Save mpr register
	in		mpr, SREG	; Load program state to mpr
	push	mpr			; Save program state
	
	; Turn on the upper 4 LEDs
	sbi		PORTB, 4
	sbi		PORTB, 5
	sbi		PORTB, 6
	sbi		PORTB, 7

	; Set timer 1 to wait 1.5 seconds
	ldi		mpr, high(18661)
	sts		TCNT1H, mpr
	ldi		mpr, low(18661)
	sts		TCNT1L, mpr

	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr			; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	UPDATE_TIMER_LEDS
; Desc:	Turns off LEDs as timer1 counts down
;----------------------------------------------------------------
UPDATE_TIMER_LEDS:
	push	mpr						; Save mpr register
	push	mpr2					; Save mpr2 register
	in		mpr, SREG				; Load program state to mpr
	push	mpr						; Save program state

	sbis	TIFR1, TOV1				; If the overflow flag is not 
	rjmp	UPDATE_TIMER_LEDS_END	; set then just return

	in		mpr, PORTB				; Read in the current values of port B
	lsr		mpr						; Shift all the bits to the right
	andi	mpr, $F0				; Mask out just the upper 4 bits
	ori		mpr, $0F				; Set the bottom 4 bits high
	in		mpr2, PORTB				; Read in the current values again
	and		mpr2, mpr				; Update just the upper bits
	out		PORTB, mpr2				; Write back out to port B

	cpi		mpr, $0F				; If the LEDs are all off then the timer is done
	breq	UPDATE_TIMER_LEDS_COUNTDOWN_DONE

	; Set timer 1 to wait 1.5 seconds
	ldi		mpr, high(18661)
	sts		TCNT1H, mpr
	ldi		mpr, low(18661)
	sts		TCNT1L, mpr

	rjmp	UPDATE_TIMER_LEDS_CLEAR_FLAG

UPDATE_TIMER_LEDS_COUNTDOWN_DONE:
	; State 2 -> state 3
	cpi		state, 2
	brne	UPDATE_TIMER_LEDS_COUNTDOWN_DONE_ELIF_STATE_3
	cpi		selection, 0
	breq	UPDATE_TIMER_LEDS_ABORT			; If they didn't select anything then just reset
	ldi		state, 3						; Move to state 3
	rcall	USART_SEND_SELECTION			; Send the current selection to the other board
	rcall	START_6_SECOND_TIMER			; Start a new timer
	rjmp	UPDATE_TIMER_LEDS_CLEAR_FLAG

UPDATE_TIMER_LEDS_COUNTDOWN_DONE_ELIF_STATE_3:
	; State 3 -> state 4
	cpi		state, 3
	brne	UPDATE_TIMER_LEDS_COUNTDOWN_DONE_ELIF_STATE_4
	cpi		opponentSelection, 0			; If the opponent never sent a selection then just reset
	breq	UPDATE_TIMER_LEDS_ABORT
	ldi		state, 4						; Move to state 4
	rcall	START_6_SECOND_TIMER			; Start a new timer
	rjmp	UPDATE_TIMER_LEDS_CLEAR_FLAG

UPDATE_TIMER_LEDS_COUNTDOWN_DONE_ELIF_STATE_4:
	; State 4 -> state 0
	cpi		state, 4
	brne	UPDATE_TIMER_LEDS_CLEAR_FLAG
	clr		state							; Move to state 0
	clr		opponentSelection				; Reset opponentSelection register
	clr		selection						; Reset selection register
	rjmp	UPDATE_TIMER_LEDS_CLEAR_FLAG

UPDATE_TIMER_LEDS_ABORT:
	ldi		state, 0			; Go back to state 0

UPDATE_TIMER_LEDS_CLEAR_FLAG:
	; Clear the TOV1 flag in TIFR
	ldi		mpr, 1
	out		TIFR1, mpr

UPDATE_TIMER_LEDS_END:
	; Restore variables by popping stack
	pop		mpr					; Restore program state
	out		SREG, mpr
	pop		mpr2				; Restore mpr2
	pop		mpr					; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	USART_SEND_READY
; Desc:	Send a message over USART that this board is ready
;----------------------------------------------------------------
USART_SEND_READY:
	push	mpr					; Save mpr register
	in		mpr, SREG			; Load program state to mpr
	push	mpr					; Save program state

	lds		mpr, UCSR1A			; Wait until the USART data register is empty
	sbrs	mpr, UDRE1
	rjmp	USART_SEND_READY
	ldi		mpr, ReadyMessage	; Move the ready message to the USART data register
	sts		UDR1, mpr

	; Restore variables by popping stack
	pop		mpr					; Restore program state
	out		SREG, mpr
	pop		mpr					; Restore mpr

	ret					; Return


;----------------------------------------------------------------
; Sub:	USART_SEND_SELECTION
; Desc:	Send the user's selection over USART
;----------------------------------------------------------------
USART_SEND_SELECTION:
	push	mpr						; Save mpr register
	in		mpr, SREG				; Load program state to mpr
	push	mpr						; Save program state

	lds		mpr, UCSR1A				; Wait until the USART data register is empty
	sbrs	mpr, UDRE1
	rjmp	USART_SEND_SELECTION
	sts		UDR1, selection			; Move the selection to the USART data register

	; Restore variables by popping stack
	pop		mpr						; Restore program state
	out		SREG, mpr
	pop		mpr						; Restore mpr

	ret								; Return


;----------------------------------------------------------------
; Sub:	USART_RECEIVE
; Desc: Receive messages from the other board
;----------------------------------------------------------------
USART_RECEIVE:
	push	mpr							; Save mpr register
	in		mpr, SREG					; Load program state to mpr
	push	mpr							; Save program state

	lds		mpr, UDR1					; Read in the message from UDR1
	cpi		mpr, ReadyMessage			; Check if this is the ready message
	brne	USART_RECEIVE_ELIF_STATE_2
	cpi		state, 0					; Check if we're in state 0
	brne	USART_RECEIVE_ELIF_STATE_1
	mov		opponentSelection, mpr		; Save the ready message in opponentSelection
	rjmp	USART_RECEIVE_END

USART_RECEIVE_ELIF_STATE_1:
	cpi		state, 1					; Check if we're in state 1
	brne	USART_RECEIVE_ELIF_STATE_2
	ldi		state, 2					; Move to state 2
	clr		selection					; Clear the current selection
	clr		opponentSelection			; Clear the opponentSelection
	rcall	START_6_SECOND_TIMER		; Start the 6 second timer
	rjmp	USART_RECEIVE_END

USART_RECEIVE_ELIF_STATE_2:
	cpi		opponentSelection, 0		; Check if we've received an opponentSelection already
	brne	USART_RECEIVE_END
	cpi		state, 2					; Check if we're in state 2
	brne	USART_RECEIVE_ELIF_STATE_3
	mov		opponentSelection, mpr		; Save the message into opponentSelection
	rjmp	USART_RECEIVE_END

USART_RECEIVE_ELIF_STATE_3:
	cpi		state, 3					; Check if we're in state 3
	brne	USART_RECEIVE_END
	mov		opponentSelection, mpr		; Save the message into opponentSelection

USART_RECEIVE_END:
	; Restore variables by popping stack
	pop		mpr			; Restore program state
	out		SREG, mpr
	pop		mpr			; Restore mpr

	ret					; Return


;***********************************************************
;*	Stored Program Data
;***********************************************************
WELCOME_STRING:
    .db		"Welcome!        Please press PD7"
READY_STRING:
	.db		"Ready. Waiting  for the opponent"
START_STRING:
	.db		"Game start      "
ROCK_STRING:
	.db		"Rock            "
PAPER_STRING:
	.db		"Paper           "
SCISSORS_STRING:
	.db		"Scissors        "
LOST_STRING:
	.db		"You lost        "
WON_STRING:
	.db		"You won!        "
DRAW_STRING:
	.db		"It's a draw     "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"		; Include the LCD Driver
