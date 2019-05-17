; File name: Atomic Clock WWVB.asm
; Created  : 5/15/2019 4:12:10 PM
; Author   : Benjamin Russell KC7MMI
; Objective: Device will take output from WWVB 60kHz receiver, decode and provide UTC time, day of year, and leap year indication

; RESOURCES:
; PORTB 7:0 - LED segments
; PORTC 6:0 - PORTC6 = Input for WWVB PWM / PORTC5:0 = Outputs 
; PORTD 7:0 - Outputs

; CONSTANTS
; Pins
.equ WWVB  = 1<<6	; Bit 6 of Port C is WWVB Input

; Pulse values
.equ BIT   = 0	; 0-bit
.equ MARK  = 1	; Marker bit

; Max values
.equ HMAX  = 24		; 24 Hours
.equ MMAX  = 60		; 60 Minutes
.equ SMAX  = 60		; 60 Seconds
.equ LMAX  = 61		; 60 Seconds + 1 Leap Second

; Timer configuration
.equ PRESC = 40000	; Prescaler value for 10mS resolution (0.0025 / (1/16000000))
.equ TIMER = 35		; 350mS Timer - Check for 1-BIT then double-up to check for FRAME
;.equ PRESC = 2		; Prescaler value for 10mS resolution (0.0025 / (1/16000000))
;.equ TIMER = 2		; 350mS Timer - Check for 1-BIT then double-up to check for FRAME

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
.def sel = r8		; LED display select register

.def tmp = r16		; Temp
.def ctr = r17		; Counter
.def seg = r18		; LED segment driver register
.def pbv = r19		; Pulse Bit Value (00000000 = 0, 00000001 = 1, 11111111 = MARKER)
.def fnr = r20		; Frame Number
.def bnr = r21		; Bit Number

.def p_h = r25		; 16-bit Prescaler
.def p_l = r24		; 16-bit Prescaler

.cseg				; Code Segment
.org 0				; Start Program at Address 0

; PROGRAM INITIALIZATION AND SETUP
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
	ldi tmp, $ff		; Setup PORTB & PORTD as outputs
	out DDRB, tmp		; Setup PORTB
	out DDRD, tmp		; Setup PORTD
	ldi tmp, $3f		; Setup PORTC with 6 as input and 5:0 as output
	out DDRC, tmp		; Setup PORTC

; START OF MAIN PROGRAM LOOP
mnloop: sbis PINC, PINC6	; Skip next instruction if WWVB high
	rjmp mnloop		; If not high, loop and check again
	rcall pulses		; Relative Call to pulses subroutine to count seconds, minutes and hours
	rcall pvalue		; Relative Call to pvalue subroutine to determine 0-bit or 1-bit)
	rcall decode		;
	rjmp mnloop		; Start over

; SUBROUTINES
; Realtime updating of seconds, minutes, and hours with seconds rollover
pulses:	inc ss			; Increment seconds
	ldi tmp, SMAX		; Prepare to check seconds
	cp ss, tmp		; Check to see if seconds = 60 
	brne subend		; Return from subroutine if not at max
	clr ss			; Reset seconds to 0
	inc mm			; Increment minutes
	ldi tmp, MMAX		; Prepare to check minutes
	cp mm, tmp		; Check to see if minutes = 60
	brne subend		; Return from subroutine if not at max
	clr mm			; Reset minutes to 0
	inc hh			; Increment hours
	ldi tmp, HMAX		; Prepare to check hours
	cp hh, tmp		; Check to see if hours = 60
	brne subend		; Return from subroutine if not at max
	clr hh			; Reset hours to 0
subend: ret			; Return from subroutine

; Provides value of pulse and outputs to pbv register
; WWVB PWM Format: pulse of 200mS = 0-bit, 500mS = 1-bit, 800mS = marker bit
; This subroutine checks pulse at 350mS after start of pulse and again at 700mS after start of pulse
pvalue:	clr pbv			; Clear pulse bit value register
pvloop:	ldi ctr, TIMER		; Load timer value into register
delay:	ldi p_h, HIGH(PRESC)	; Load prescaler values into registers
	ldi p_l, LOW(PRESC)	; Load prescaler values into registers
prscl:	sbiw p_h:p_l, 1		; Decrement prescaler
	brne prscl		; Loop decrement as long as prescaler is not 0
	dec ctr			; Decrement counter when prescaler hits 0
	brne delay		; Redo until counter is 0
	sbrc pbv, BIT		; Skip if 1-bit is cleared (0-bit)
	rjmp marker		; Goto marker if pbv equals ONE
	sbis PINC, PINC6	; Skip next instruction if WWVB high
	ret			; Return from subroutine (0 bit)
	inc pbv			; Increment pulse bit value (1 bit or marker bit)
	rjmp pvloop		; Now to check for a marker bit
marker:	sbis PINC, PINC6	; Skip next instruction if WWVB high
	ret			; Return from subroutine (1 bit)
	inc fnr			; Increment frame number
	inc pbv			; Increment pulse bit value (marker bit)
	clr bnr			; Clear bit number register
	ret			; Return from subroutine (marker bit)

; Decode WWVB signal and provide an integer value for each category of data
decode:	sbrc pbv, MARK		; Skip next instruction if frame marker
	ret			; Return from subroutine if marker bit
	inc bnr			; Increment bit number
	clr tmp			; Clear tmp
	lsl tmp			; Bit shift tmp left
	inc tmp			; Add 1 to tmp
