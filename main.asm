; File name: TC Atomic Clock WWVB.asm
; Created  : 5/20/2019 4:12:10 PM
; Author   : Benjamin Russell KC7MMI
; MCU Trgt : Atmel AVR ATmega328P at 16MHz
; Objective: Device will take output from WWVB 60kHz receiver, decode and provide UTC time, day of year, and leap year indication

; WWVB goes High: Reset (clear, restart) timer
; WWVB goes Low: Check (stop, read) timer
; Timer reads <150mS: disregard
; Timer reads 180-220mS: 0-bit
; Timer reads 480-520mS: 1-bit
; Timer reads 780-820mS: M-bit

; Define bit register flags Z = ZRO; O = ONE; M = MRK; F = FRM
; 76543210
; xxxxFMOZ
.equ ZRO = 0		; Bit Value Register - Zero Flag
.equ ONE = 1		; Bit Value Register - One Flag
.equ MRK = 2		; Bit Value Register - Marker Flag
.equ FRM = 3		; Bit Value Register - Frame Flag

.equ PPD = 64
.equ VZRO = HIGH(181000/PPD)	; High byte of 181mS ($0b0c) for comparison to TC1
.equ VONE = HIGH(480000/PPD)	; High byte of 181mS ($1d4c) for comparison to TC1
.equ VMRK = HIGH(780000/PPD)	; High byte of 181mS ($2f9b) for comparison to TC1
.equ VMRKH = HIGH(990000/PPD)	; High byte of 181mS ($320c) for comparison to TC1
;.equ VZROH = HIGH(230000/PPD)	; High byte of 181mS ($0e09) for comparison to TC1
;.equ VONEH = HIGH(520000/PPD)	; High byte of 181mS ($1fbd) for comparison to TC1

; Registers r1:r0 are reserved for multiplication
.def db0 = r2		; Data Byte 0
.def db1 = r3		; Data Byte 1
.def db2 = r4		; Data Byte 2
.def db3 = r5		; Data Byte 3
.def db4 = r6		; Data Byte 4
.def db5 = r7		; Data Byte 5
.def tmp = r16		; Temp
.def dbx = r17		; Data Byte X
.def tcl = r18		; Timer Counter value (low byte)
.def tch = r19		; Timer Counter value (high byte)
.def bvr = r20		; Bit value register
.def bnr = r21		; Bit number in frame
.def mnr = r22		; Marker number in minute

.cseg				; Code Segment
.org 0				; Start Program at Address 0

start:	clr r10				; Put 0 in r0 
		ldi tmp, 5			; Load 5 in tmp
		mov r11, tmp			; Put 5 in r1
		sts TCCR1A, tmp		; TC1 Control Reg A set to normal for simple counting operations
		sts TCCR1C, tmp		; TC1 Control Reg C set to normal for simple counting operations
		clr bnr
		clr bvr
		clr mnr

; Here we wait for the start of a pulse
loop:	sbic PINB, PINB7	; Keep looping until PINB7 is pressed, at which point skip rjmp loop
		rjmp loop			; Loop until PINB7 pressed
		sts TCCR1B, r1		; Start TC1 and set prescaler to 1/1024

; Checking for pulse lengths similar to those listed below and outputs to bit value register
; WWVB PWM Format: pulse of 200mS = 0-bit; 500mS = 1-bit; 800mS = marker bit
; Here we wait for the end of the pulse
; Only comparing high byte of timer since precision is not needed
pulse:	sbis PINB, PINB7	; Keep looping until PINB7 is released, at which point exit loop
		rjmp pulse			; Loop utnil key released
		sts TCCR1B, r0		; Stop TC1 to read values
		lds tcl, TCNT1L		; Load TC1 Low value into working register
		lds tch, TCNT1H		; Load TC1 High value into working register
		sts TCNT1H, r0		; Clear TC1 High value
		sts TCNT1L, r0		; Clear TC1 Low value
		cpi tch, VMRKH		; Check for too long of pulse
		brge CLRBVR			; If too long, clear the bvr
		cpi tch, VMRK		; Check for MRK pulse
		brge SETMRK			; If MRK, set MRK; also sets FRM
		cpi tch, VONE		; Check for ONE pulse
		brge SETONE			; If ONE, set ONE
		cpi tch, VZRO		; Check for ZRO pulse
		brge SETZRO			; If ZRO, set ZRO
		brlt CLRBVR			; If too short, clear the bvr
SETMRK:	sbrc bvr, MRK		; Skip SETFRM if no previous MRK
		rjmp SETFRM			; If previous pulse, SETFRM
		ldi bvr, 1<<MRK		; If no previous MRK, set MRK in bvr
		rjmp loop			; Start over
SETONE:	ldi bvr, 1<<ONE		; Set ONE in bvr
		rjmp DECODE			; Start over
SETZRO:	ldi bvr, 1<<ZRO		; Set ZRO in bvr
		rjmp DECODE			; Start over
CLRBVR:	clr bvr				; Clear all bits in bvr
		rjmp loop			; Start over
SETFRM:	ldi bvr, 1<<FRM		; Set FRM in bvr
		clr bnr				; Clear bit number register
		clr mnr				; Clear marker number register at start of minute
		rjmp loop			; Start over


; The following function takes the ONEs and ZROs and arranges them in a meaningful way into registers
;  
DECODE:	cpi bnr, 4			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		cpi bnr, 14			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		cpi bnr, 24			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		cpi bnr, 34			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		cpi bnr, 44			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		cpi bnr, 54			; Check if middle bit (unused)
		breq loop			; Skip if middle bit
		lsl dbx				; Prepare for incoming bit by shifting reg left
		sbrc bvr, ONE		; Check for a ONE bit
		sbr dbx, ONE		; Set a 1 in the 0th bit location
		cpi bnr, 8			; Check if end bit
		breq DATAB0			; Move complete byte into register
		cpi bnr, 18			; Check if end bit
		breq DATAB1			; Move complete byte into register
		cpi bnr, 28			; Check if end bit
		breq DATAB2			; Move complete byte into register
		cpi bnr, 38			; Check if end bit
		breq DATAB3			; Move complete byte into register
		cpi bnr, 48			; Check if end bit
		breq DATAB4			; Move complete byte into register
		cpi bnr, 58			; Check if end bit
		breq DATAB5			; Move complete byte into register
DATAB0: mov db0, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
DATAB1: mov db1, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
DATAB2: mov db2, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
DATAB3: mov db3, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
DATAB4: mov db4, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
DATAB5: mov db5, dbx		; Move complete byte into register
		rjmp loop			; Return to start of loop
