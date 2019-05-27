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
.def db0 = r2		; Data Byte 0: Seconds
.def db1 = r3		; Data Byte 1: Minutes
.def db2 = r4		; Data Byte 2: Hours
.def db3 = r5		; Data Byte 3: High Nibble = Day 100s	& Low Nibble = Day 10s
.def db4 = r6		; Data Byte 4: High Nibble = Day 1s		& Low Nibble = DUT1 Sign 
.def db5 = r7		; Data Byte 5: High Nibble = DUT1 Value & Low Nibble = Year 10s
.def db6 = r8		; Data Byte 6: High Nibble = Year 1s    & Low Nibble = LY/LS/DST
.def tmp = r16		; Temp
.def dgt = r17		; Digit register
.def bvr = r18		; Bit value register
.def bnr = r19		; Bit number in frame
.def mnr = r20		; Marker number in minute
.def dbx = r21		; Data Byte X
.def d1l = r22		; Display 1 low byte
.def d1h = r23		; Display 1 high byte
.def d2l = r24		; Display 2 low byte
.def d2h = r25		; Display 2 high byte

.cseg				; Code Segment
.org 0				; Start Program at Address 0
	rjmp start

start:		
; Timer Setup
	ldi tmp, 0			; Load 5 in r16
	sts TCCR1A, tmp		; TC1 Control Reg A set to normal for simple counting operations
	sts TCCR1C, tmp		; TC1 Control Reg C set to normal for simple counting operations

; SPI Setup
	ldi tmp, 1<<SPI2X		; Set SPI clock to fosc/2 (8MHz)
	sts SPSR0, tmp			; Set SPI Status Register (specifically SPI2X0)
	ldi tmp, (1<<SPE)+(1<<MSTR)	; Enable SPI as Master
	sts SPCR0, tmp			; Set SPI Control Register 0
	sbi DDRB, PORTB2		; Configure PORTB2 as output

; Display Setup - Decode Mode
	ldi d1h, $09			; Configure decode mode of display 1
	ldi d1l, $fd			; All but 2nd from right digit Code B decode
	ldi d2h, $09			; Configure decode mode of display 2
	ldi d2l, $7f			; All but left-most digit Code B decode
	rcall Display_Write		; Write changes to display via SPI

; Display Setup - Intensity	
	ldi d1h, $0a			; Configure intensity mode of display 1
	ldi d1l, $0f			; 31/32 duty cycle (brightest)
	ldi d2h, $0a			; Configure intensity mode of display 2
	ldi d2l, $0f			; 31/32 duty cycle (brightest)
	rcall Display_Write		; Write changes to display via SPI

; Display Setup - Scan Limit
	ldi d1h, $0b			; Configure scan limit mode of display 1
	ldi d1l, $07			; All digits displayed
	ldi d2h, $0b			; Configure scan limit mode of display 2
	ldi d2l, $07			; All digits displayed
	rcall Display_Write		; Write changes to display via SPI

; Display Setup - Shutdown Mode
	ldi d1h, $0c			; Configure shutdown mode of display 1
	ldi d1l, $0f			; Normal operation
	ldi d2h, $0c			; Configure shutdown mode of display 2
	ldi d2l, $0f			; Normal operation
	rcall Display_Write		; Write changes to display via SPI

; Display Setup - Display Test
	ldi d1h, $0f			; Configure display test mode of display 1
	ldi d1l, $00			; Normal operation
	ldi d2h, $0f			; Configure display test mode of display 2
	ldi d2l, $00			; Normal operation
	rcall Display_Write		; Write changes to display via SPI

; Clear Registers
	clr bnr
	clr bvr
	clr mnr

; Here we wait for the start of a pulse
loop:	
	sbic PINB, PINB7	; Keep looping until PINB7 is pressed, at which point skip rjmp loop
	rjmp loop			; Loop until PINB7 pressed
	ldi tmp, 5
	sts TCCR1B, r16		; Start TC1 and set prescaler to 1/1024

; !!! INSTERT CODE HERE FOR COUNTING SECONDS, MINUTES, HOURS, ETC !!!
; !!! THIS DATA WILL BE DISPLAYED AND WILL BE UPDATED BY WWVB FURTHER DOWN IN THE CODE !!!

; Display time
; Sets up data registers to write 4 digits at a time, 2 for left display and 2 for right (saves on SPI bytes)
; |   Display 2   |.....|   Display 1   |
; |8|7|6|5|4|3|2|1|.....|8|7|6|5|4|3|2|1|
; |B|D| |YR | DAY |.....|HH |MM |SS |DUT|

; Display Seconds
	ldi d1h, $03			; Display 1, digit 3
	mov d1l, db0			; Display 1, seconds 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $04			; Display 1, digit 4
	swap d1l				; Display 1, seconds 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Minutes
	ldi d1h, $05			; Display 1, digit 5
	mov d1l, db1			; Display 1, minutes 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $06			; Display 1, digit 6
	swap d1l				; Display 1, minutes 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Hours
	ldi d1h, $07			; Display 1, digit 7
	mov d1l, db2			; Display 1, hours 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $08			; Display 1, digit 8
	swap d1l				; Display 1, hours 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Days (100s & 10s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $02			; Display 2, digit 2
	mov d2l, db3			; Display 2, days 10s
	rcall Display_Write		; Write changes to display via SPI
	ldi d2h, $03			; Display 2, digit 3
	swap d2l				; Display 2, days 100s
	rcall Display_Write		; Write changes to display via SPI

; Display DUT1 Sign
	ldi d1h, $02			; Display 1, digit 2
	ldi d1l, $80			; Display 1, decimal point only
	sbrc db4, 1				; Check for minus bit
	ldi d1l, $81			; Display 1, decimal point & minus sign (segment G)
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI

; Display Days (1s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $01			; Display 2, digit 1
	mov d2l, db4			; Display 2, prepare to display days 1s
	swap d2l				; Display 2, days 1s
	rcall Display_Write		; Write changes to display via SPI

; Display Year (10s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $05			; Display 2, digit 5
	mov d2l, db5			; Display 2, years 10s
	rcall Display_Write		; Write changes to display via SPI

; Display DUT1 Value
	ldi d1h, $01			; Display 1, digit 1
	mov d1l, db5			; Display 1, DUT1 value
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI

; Display LY/LS/DST
	ldi d1h, $08			; Display 1, digit 8
	ldi d1l, $00			; Display 1, clear
	sbrc db6, 0				; Check for DST
	sbr d1l, 1<<6			; If not clear, turn on segment A for DST
	sbrc db6, 2				; Check for LS
	sbr d1l, 1<<3			; If not clear, turn on segment D for LS
	sbrc db6, 3				; Check for LY
	sbr d1l, 1<<0			; If not clear, turn on segment G for LY
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI

; Display Year (1s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $04			; Display 2, digit 4
	mov d2l, db6			; Display 2, prepare to display years 1s
	swap d2l				; Display 2, years 1s
	rcall Display_Write		; Write changes to display via SPI



; Checking for pulse lengths similar to those listed below and outputs to bit value register
; WWVB PWM Format: pulse of 200mS = 0-bit; 500mS = 1-bit; 800mS = marker bit
; Here we wait for the end of the pulse
; Only comparing high byte of timer since precision is not needed
pulse:	
	sbis PINB, PINB7	; Keep looping until PINB7 is released, at which point exit loop
	rjmp pulse			; Loop utnil key released
	ldi tmp, 0
	sts TCCR1B, tmp		; Stop TC1 to read values
	lds XL, TCNT1L		; Load TC1 Low value into working register
	lds XH, TCNT1H		; Load TC1 High value into working register
	sts TCNT1H, tmp		; Clear TC1 High value
	sts TCNT1L, tmp		; Clear TC1 Low value
	cpi XH, VMRKH		; Check for too long of pulse
	brge CLRBVR			; If too long, clear the bvr
	cpi XH, VMRK		; Check for MRK pulse
	brge SETMRK			; If MRK, set MRK; also sets FRM
	cpi XH, VONE		; Check for ONE pulse
	brge SETONE			; If ONE, set ONE
	cpi XH, VZRO		; Check for ZRO pulse
	brge SETZRO			; If ZRO, set ZRO
	brlt CLRBVR			; If too short, clear the bvr
SETMRK:	
	sbrc bvr, MRK		; Skip SETFRM if no previous MRK
	rjmp SETFRM			; If previous pulse, SETFRM
	ldi bvr, 1<<MRK		; If no previous MRK, set MRK in bvr
	inc mnr
	cpi mnr, 1
	breq datab1
	cpi mnr, 2
	breq datab2
	cpi mnr, 3
	breq datab3
	cpi mnr, 4
	breq datab4
	cpi mnr, 5
	breq datab5
	cpi mnr, 6
	breq datab6
	rjmp loop			; Start over
SETONE:	
	ldi bvr, 1<<ONE		; Set ONE in bvr
	rjmp DECODE			; Start over
SETZRO:	
	ldi bvr, 1<<ZRO		; Set ZRO in bvr
	rjmp DECODE			; Start over
CLRBVR:	
	clr bvr				; Clear all bits in bvr
	rjmp loop			; Start over
SETFRM:	
	ldi bvr, 1<<FRM		; Set FRM in bvr
	clr bnr				; Clear bit number register
	clr mnr				; Clear marker number register at start of minute
	rjmp loop			; Start over

; The following function takes the ONEs and ZROs and arranges them in a meaningful way into registers
; !!! THE FOLLOWING BRANCHES ARE OUT OF RANGE - CODE NEEDS TO BE ADJUSTED !!!
DECODE:	
	cpi bnr, 4			; Check if middle bit (unused)
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
	rjmp loop			; Start over

datab1: 
	mov db1, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop
datab2: 
	mov db2, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop
datab3: 
	mov db3, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop
datab4: 
	mov db4, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop
datab5: 
	mov db5, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop
datab6: 
	mov db6, dbx		; Move complete byte into register
	rjmp loop			; Return to start of loop

; Because bits are serially shifted through both displays, all 32 bits need to be sent sequentially
Display_Write:
	cbi PORTB, PORTB2			; Pull down /SS/PB2 pin to start data transfer
	nop						; Give PORTB a cycle to adjust before allowing data xfer
	sts SPDR0, d1h			; Send display 1 (right display) address bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d1l			; Send display 1 (right display) data bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d2h			; Send display 2 (left display) address bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d2l			; Send display 2 (left display) data bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sbi PORTB, PORTB2			; Pull up /SS/PB2 pin to end data transfer and latch bits into displaya registers
	ret

; A basic routine for checking when the Data Register is clear and ready to accept another byte
SPI_DR_Check:	
	lds tmp, SPSR0
	sbrs tmp, SPIF
	rjmp SPI_DR_Check
	ret
