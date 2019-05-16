; File name: Atomic Clock WWVB.asm
; Created  : 5/15/2019 4:12:10 PM
; Author   : Benjamin Russell KC7MMI
; Objective: Device will take output from WWVB 60kHz receiver, decode and provide UTC time, day of year, and leap year indication
;
; PORTB 7:0 - LED segments
; PORTC 6:0 - PORTC6 = Input for WWVB PWM / PORTC5:0 = Outputs 
; PORTD 7:0 - Outputs


/*** CONSTANTS ***/
; PINS
.equ WWVB  = 1<<6	; Bit 6 of Port C is WWVB Input

; PULSE VALUES
.equ ZERO  = $00	; 0-bit
.equ ONE   = $01	; 1-bit
.equ MARK  = $02	; Marker bit

; MAX VALS
.equ HMAX  = 24		; 24 Hours
.equ MMAX  = 60		; 60 Minutes
.equ SMAX  = 60		; 60 Seconds
.equ LMAX  = 61		; 60 Seconds + 1 Leap Second

; TIMER CONFIG
.equ PRESC = $9c40	; Prescaler value for 10mS resolution (0.0025 / (1/16000000))
.equ TIMER = 35		; 350mS Timer - Check for 1-BIT then double-up to check for FRAME

; LPD Register (r5) Flags for Leap Year, Leap Second and Daylight Savings
.equ LPY = 2		; Leap Year Flag
.equ LPS = 1		; Leap Second Flag
.equ DST = 0		; Daylight Savings Flag (1 = DST / 0 = Standard Time)

; General Purpose Register Definitions
.def ss  = r0		; Seconds
.def mm  = r1		; Minutes
.def hh  = r2		; Hours
.def d_h = r3		; Day of Year (high)
.def d_l = r4		; Day of Year (low)
.def yr  = r5		; Year (2-digit)
.def lpd = r6		; Leap Year, Leap Second, DST
.def fnr = r7		; Frame Number
.def sel = r8		; LED display select register

.def pbv = r15		; Pulse Bit Value (00000000 = 0, 00000001 = 1, 11111111 = MARKER)
.def tmp = r16		; Temp
.def seg = r17		; LED segment driver register
.def ctr = r18		; Counter

.def p_h = r25		; 16-bit Prescaler
.def p_l = r24		; 16-bit Prescaler

.cseg				; Code Segment
.org 0				; Start Program at Address 0


start:	clr ss			; Clear Register
		clr mm			; Clear Register
		clr hh			; Clear Register
		clr d_h			; Clear Register
		clr d_l			; Clear Register
		clr yr			; Clear Register
		clr lpd			; Clear Register
		clr fnr			; Clear Register
		clr sel			; Clear Register
		clr pbv			; Clear Register
		clr tmp			; Clear Register
		clr seg			; Clear Register
		clr ctr			; Clear Register
		clr p_h			; Clear Register
		clr p_l			; Clear Register
		ldi tmp, $ff	; Setup PORTB & PORTD as outputs
		out DDRB, tmp	; Setup PORTB
		out DDRD, tmp	; Setup PORTD
		ldi tmp, $3f	; Setup PORTC with 6 as input and 5:0 as output
		out DDRC, tmp	; Setup PORTC
wwvbin: in tmp, DDRC	; Read PORTC for WWVB pulse
		andi tmp, WWVB	; Filter PORTC to WWVB input only
		cpi tmp, WWVB	; Check to see if input is high for WWVB pulse
		brne wwvbin		; If not high, loop and check again
		rcall pulses	; Relative Call to pulses subroutine
		clr pbv			; Clear pulse bit value register
		rcall pvalue	; Relative Call to ptimer (pulse timer to determine 0-bit or 1-bit)
		//we have value of pulse...now what???

/*** SUBROUTINES ***/
/* Realtime updating of seconds, minutes, and hours with seconds rollover */
pulses:	inc ss			; Increment seconds
		ldi tmp, SMAX	; Prepare to check seconds
		cp ss, tmp		; Check to see if seconds = 60 
		brne subend		; Return from subroutine if not at max
		clr ss			; Reset seconds to 0
		inc mm			; Increment minutes
		ldi tmp, MMAX	; Prepare to check minutes
		cp mm, tmp		; Check to see if minutes = 60
		brne subend		; Return from subroutine if not at max
		clr mm			; Reset minutes to 0
		inc hh			; Increment hours
		ldi tmp, HMAX	; Prepare to check minutes
		cp hh, tmp		; Check to see if minutes = 60
		brne subend		; Return from subroutine if not at max
		clr hh			; Reset minutes to 0
subend: ret				; Return from subroutine
/* END OF pulses SUBROUTINE */

/* Provides value of pulse and outputs to pbv register */
/* WWVB PWM Format: pulse of 200mS = 0-bit, 500mS = 1-bit, 800mS = marker bit */
/* This subroutine checks pulse at 350mS after start of pulse and again at 700mS after start of pulse */
pvalue:	ldi ctr, TIMER			; Load timer value into register
delay:	ldi p_h, HIGH(PRESC)	; Load prescaler values into registers
		ldi p_l, LOW(PRESC)		; Load prescaler values into registers
prscl:	sbiw p_h:p_l,1			; Decrement prescaler
		brne prscl				; Loop decrement as long as prescaler is not 0
		dec ctr					; Decrement counter when prescaler hits 0
		brne delay				; Redo until counter is 0
		ldi tmp, ONE			; Prepare to check pbv
		cp pbv, tmp				; Checking value of pbv to determine how to proceed
		breq marker				; Goto marker if pbv equals ONE
		sbis PINC, PINC6		; Skip next instruction if WWVB high
		ret						; Return from subroutine (0 bit)
		inc pbv					; Increment pulse bit value (1 bit or marker bit)
		rjmp pvalue				; Now to check for a marker bit
marker:	sbis PINC, PINC6		; Skip next instruction if WWVB high
		ret						; Return from subroutine (1 bit)
		inc pbv					; Increment pulse bit value (marker bit)
		ret						; Return from subroutine (marker bit)
/* END OF pvalue SUBROUTINE */
