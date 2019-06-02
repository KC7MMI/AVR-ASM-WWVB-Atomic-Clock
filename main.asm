; File name: TC Atomic Clock WWVB.asm
; Created  : 5/20/2019 4:12:10 PM
; Author   : Benjamin Russell KC7MMI
; MCU Trgt : Atmel AVR ATmega328P at 16MHz
; Objective: Device will take output from WWVB 60kHz receiver, decode and provide UTC time, day of year, and leap year indication

; Define bit register flags Z = ZRO; O = ONE; M = MRK; F = FRM
; 76543210
; xxxxFMOZ
.equ ZRO = 0		; Bit Value Register - Zero Flag
.equ ONE = 1		; Bit Value Register - One Flag
.equ MRK = 2		; Bit Value Register - Marker Flag
.equ FRM = 3		; Bit Value Register - Frame Flag

; WWVB goes High: Reset (clear, restart) timer
; WWVB goes Low: Check (stop, read) timer
; Timer reads <180mS: disregard
; Timer reads ~180mS: 0-bit
; Timer reads ~480mS: 1-bit
; Timer reads ~780mS: M-bit
; Timer reads >990mS: disregard
.equ PPD = 64			; Prescaler PerioD of 64uS
.equ T_ZRO = HIGH(181000/PPD)	; High byte of 181mS ($0b0c) for comparison to TC1
.equ T_ONE = HIGH(480000/PPD)	; High byte of 181mS ($1d4c) for comparison to TC1
.equ T_MRK = HIGH(780000/PPD)	; High byte of 181mS ($2f9b) for comparison to TC1
.equ T_MRKH = HIGH(990000/PPD)	; High byte of 181mS ($320c) for comparison to TC1
;.equ T_ZROH = HIGH(230000/PPD)	; High byte of 181mS ($0e09) for comparison to TC1
;.equ T_ONEH = HIGH(520000/PPD)	; High byte of 181mS ($1fbd) for comparison to TC1

; Registers r1:r0 are reserved for multiplication
.def db0 = r2		; Data Byte 0: Seconds
.def db1 = r3		; Data Byte 1: Minutes
.def db2 = r4		; Data Byte 2: Hours
.def db3 = r5		; Data Byte 3: High Nibble = Day 100s	& Low Nibble = Day 10s
.def db4 = r6		; Data Byte 4: High Nibble = Day 1s		& Low Nibble = DUT1 Sign 
.def db5 = r7		; Data Byte 5: High Nibble = DUT1 Value & Low Nibble = Year 10s
.def db6 = r8		; Data Byte 6: High Nibble = Year 1s    & Low Nibble = LY/LS/DST
.def tmp = r16		; Temp
.def bvr = r18		; Bit value register
.def bnr = r19		; Bit number in frame
.def mnr = r20		; Marker number in minute
.def dbx = r21		; Data Byte X
.def d1l = r22		; Display 1 low byte
.def d1h = r23		; Display 1 high byte
.def d2l = r24		; Display 2 low byte
.def d2h = r25		; Display 2 high byte

.cseg			; Code Segment
.org 0			; Start Program at Address 0

start:		
; Timer Setup
	ldi tmp, 0			; Load 0 in r16
	sts TCCR1A, tmp			; TC1 Control Reg A set to normal for simple counting operations
	sts TCCR1C, tmp			; TC1 Control Reg C set to normal for simple counting operations

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
	clr db0
	clr db1
	clr db2
	clr db3
	clr db4
	clr db5
	clr db6
	clr bnr
	clr bvr
	clr mnr

; Here we wait for the start of a pulse
loop:	
	sbic PINB, PINB7		; Keep looping until PINB7 is pressed, at which point skip rjmp loop
	rjmp loop			; Loop until PINB7 pressed

; WWVB Pulse Begin
	ldi tmp, 5			; Prepare to start timer
	sts TCCR1B, r16			; Start TC1 and set prescaler to 1/1024

; Increment Seconds
	ldi tmp, $59			; Prepare to load 59 into db0 IF:
	sbrc mnr, 6			; If 6th marker received
	mov db0, tmp			; Put 59 into register to trick into rolling over
	inc db0				; Increment 1s
	ldi tmp, $0f			; Setup bitmask
	and tmp, db0			; Copy only lower nibble into tmp
	cpi tmp, $0a			; Compare
	breq Sec_Clr_1s			; If $xa, rollover 1s
	rjmp Print_Time			; If not time to rollover, go print time
Sec_Clr_1s:				; Clear 1s and increment 10s
	ldi tmp, $f0			; Prepare for bitmask
	and db0, tmp			; Clear lower nibble in register
	swap db0			; Swap nibbles for easy increment
	inc db0				; Increment 10s
	swap db0			; Put 10s back in their place
	mov tmp, db0			; Copy to tmp for compare
	cpi tmp, $60			; Compare
	breq Sec_Rollover		; Reset seconds 
	rjmp Print_Time			; If not time to rollover, go print time
Sec_Rollover:
	clr db0				; Reset register to 00

; Increment Minutes
	inc db1				; Increment 1s
	ldi tmp, $0f			; Setup bitmask
	and tmp, db1			; Copy only lower nibble into tmp
	cpi tmp, $0a			; Compare
	breq Min_Clr_1s			; If $xa, rollover 1s
	rjmp Print_Time			; If not time to rollover, go print time
Min_Clr_1s:				; Clear 1s and increment 10s
	ldi tmp, $f0			; Prepare for bitmask
	and db1, tmp			; Clear lower nibble in register
	swap db1			; Swap nibbles for easy increment
	inc db1				; Increment 10s
	swap db1			; Put 10s back in their place
	mov tmp, db1			; Copy to tmp for compare
	cpi tmp, $60			; Compare
	breq Min_Rollover		; Branch to rollover minutes and continue
	rjmp Print_Time			; If not time to rollover, go print time
Min_Rollover:
	clr db1				; Reset register to 00

; Increment Hours
	inc db2				; Increment 1s
	mov tmp, db2			; Copy only lower nibble into tmp
	cpi tmp, $24			; Compare
	breq Hr_Rollover		; Branch to rollover hour and continue
	andi tmp, $0f			; Setup bitmask
	cpi tmp, $0a			; Compare
	brne Print_Time			; If not time to rollover, go print time
	ldi tmp, $f0			; Prepare for bitmask
	and db2, tmp			; Clear lower nibble in register
	swap db2			; Swap nibbles for easy increment
	inc db2				; Increment 10s
	swap db2			; Put 10s back in their place
	rjmp Print_Time			; Print time after rolling over 1s
Hr_Rollover:
	clr db2				; Reset register to 00

; Increment Days
	swap db4			; Prepare to increment 1s
	inc db4				; Increment 1s
	swap db4			; Put 1s back in their place
	mov tmp, db3			; Prepare to compare 100s & 10s
	cpi tmp, $36			; Compare 100s & 10s
	brne Compare10			; Go compare 1s & look for 0xa if not last 5 days of year
	mov tmp, db4			; Prepare to compare 1s
	andi tmp, $f0			; Bitmask 1s
	cpi tmp, $60			; Compare 1s, look for end of year
	breq Day_Rollover		; If end of year, rollover days
	rjmp Print_Time			; Print time if not end of year
Compare10:
	mov tmp, db4			; Prepare for bitmask
	andi tmp, $f0			; Apply bitmask for testing
	cpi tmp, $a0			; Compare with 10
	brne Print_Time			; Print if less than 10
	ldi tmp, $0f			; Prepare to clr high nibble
	and db4, tmp			; Clr high nibble (day 1s)
; Increment Days - 10s
	inc db3				; Increment 10s
	ldi tmp, $0f			; Setup bitmask
	and tmp, db3			; Copy only lower nibble into tmp
	cpi tmp, $0a			; Compare
	brne Print_Time			; If not time to rollover, go print time
	ldi tmp, $f0			; Prepare for bitmask
	and db3, tmp			; Clear lower nibble in register
	swap db3			; Swap nibbles for easy increment
	inc db3				; Increment 10s
	swap db3			; Put 10s back in their place
	rjmp Print_Time			; Print time
Day_Rollover:
	clr db3				; Clr 100s & 10s
	ldi tmp, $0f			; Prepare to clr 1s
	and db4, tmp			; clr 1s
	ldi tmp, $10			; Prepare to set a 1 in the 1s
	or db4, tmp			; Start 1s off with 1 (day 1 of year xx)

; Increment Years
	swap db6			; Prepare 1s for incrementing
	inc db6				; Increment 1s
	swap db6			; Put 1s back in their spot
	ldi tmp, $f0			; Setup bitmask
	and tmp, db6			; Copy only high nibble into tmp
	cpi tmp, $a0			; Compare
	breq Yr_Clr_1s			; If $ax, rollover 1s
	rjmp Print_Time			; If not time to rollover, go print time
Yr_Clr_1s:
	ldi tmp, $0f			; Prepare for bitmask
	and db6, tmp			; Clear high nibble in register
	inc db5				; Increment 10s
	ldi tmp, $0f			; Setup bitmask
	and tmp, db5			; Copy to tmp for compare
	cpi tmp, $0a			; Compare
	breq Yr_Rollover		; Reset seconds 
	rjmp Print_Time			; If not time to rollover, go print time
Yr_Rollover:
	ldi tmp, $f0			; Setup bitmask
	and db5, tmp			; Clear low nibble (10s)

; Display time
; Sets up data registers to write 4 digits at a time, 2 for left display and 2 for right (saves on SPI bytes)
; |   Display 2   |.....|   Display 1   |
; |8|7|6|5|4|3|2|1|.....|8|7|6|5|4|3|2|1|
; |B|D| |YR | DAY |.....|HH |MM |SS |DUT|

Print_Time:
; Bit Value - Display WWVB Pulse With Decimal
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $08			; Display 2, digit 8
	ldi d2l, $80			; Display 2, display '.' (decimal)
	rcall Display_Write		; Write changes to display via SPI

; Display Seconds
	ldi d1h, $03			; Display 1, digit 3
	mov d1l, db0			; Display 1, seconds 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $04			; Display 1, digit 4
	swap d1l			; Display 1, seconds 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Minutes
	ldi d1h, $05			; Display 1, digit 5
	mov d1l, db1			; Display 1, minutes 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $06			; Display 1, digit 6
	swap d1l			; Display 1, minutes 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Hours
	ldi d1h, $07			; Display 1, digit 7
	mov d1l, db2			; Display 1, hours 1s
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI
	ldi d1h, $08			; Display 1, digit 8
	swap d1l			; Display 1, hours 10s
	rcall Display_Write		; Write changes to display via SPI

; Display Days (100s & 10s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $02			; Display 2, digit 2
	mov d2l, db3			; Display 2, days 10s
	rcall Display_Write		; Write changes to display via SPI
	ldi d2h, $03			; Display 2, digit 3
	swap d2l			; Display 2, days 100s
	rcall Display_Write		; Write changes to display via SPI

; Display DUT1 Sign
	ldi d1h, $02			; Display 1, digit 2
	ldi d1l, $80			; Display 1, decimal point only
	sbrc db4, 1			; Check for minus bit
	ldi d1l, $81			; Display 1, decimal point & minus sign (segment G)
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI

; Display Days (1s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $01			; Display 2, digit 1
	mov d2l, db4			; Display 2, prepare to display days 1s
	swap d2l			; Display 2, days 1s
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
	sbrc db6, 0			; Check for DST
	sbr d1l, 1<<6			; If not clear, turn on segment A for DST
	sbrc db6, 2			; Check for LS
	sbr d1l, 1<<3			; If not clear, turn on segment D for LS
	sbrc db6, 3			; Check for LY
	sbr d1l, 1<<0			; If not clear, turn on segment G for LY
	ldi d2h, $00			; Display 2, NOP
	ldi d2l, $00			; Display 2, NOP
	rcall Display_Write		; Write changes to display via SPI

; Display Year (1s)
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $04			; Display 2, digit 4
	mov d2l, db6			; Display 2, prepare to display years 1s
	swap d2l			; Display 2, years 1s
	rcall Display_Write		; Write changes to display via SPI

; Checking for pulse lengths similar to those listed below and outputs to bit value register
; WWVB PWM Format: pulse of 200mS = 0-bit; 500mS = 1-bit; 800mS = marker bit
; Here we wait for the end of the pulse
; Only comparing high byte of timer since precision is not needed
Clock_Pulse:	
	sbis PINB, PINB7		; Keep looping until WWVB pulse ends, at which point exit loop
	rjmp Clock_Pulse		; Loop until pulse ends

; WWVB Pulse End - Check Width of Pulse
	ldi tmp, 0			; For clearing the timer registers later
	sts TCCR1B, tmp			; Stop TC1 to read values
	lds XL, TCNT1L			; Load TC1 Low value into working register
	lds XH, TCNT1H			; Load TC1 High value into working register
	sts TCNT1H, tmp			; Clear TC1 High value
	sts TCNT1L, tmp			; Clear TC1 Low value
	cpi XH, T_MRKH			; Check for too long of pulse
	brge Clr_Bit_Val		; If too long, clear the bvr
	cpi XH, T_MRK			; Check for MRK pulse
	brge Set_Mrkr_Bit		; If MRK, set MRK; also sets FRM
	cpi XH, T_ONE			; Check for ONE pulse
	brge Set_One_Bit		; If ONE, set ONE
	cpi XH, T_ZRO			; Check for ZRO pulse
	brge Set_Zero_Bit		; If ZRO, set ZRO
	brlt Clr_Bit_Val		; If too short, clear the bvr

Clr_Bit_Val:	
	clr bvr				; Clear all bits in bvr
	rjmp loop			; Start over

Set_Mrkr_Bit:	
	sbrc bvr, MRK			; Skip Set_Frame_Bit if no previous MRK
	rjmp Set_Frame_Bit		; If previous pulse, Set_Frame_Bit
	ldi bvr, 1<<MRK			; If no previous MRK, set MRK in bvr
	lsl mnr				; Shift bit left for each marker
	sbrc mnr, 1			; Skip if not #1 marker
	mov db1, dbx			; Move complete byte into register
	sbrc mnr, 2			; Skip if not #2 marker
	mov db2, dbx			; Move complete byte into register
	sbrc mnr, 3			; Skip if not #3 marker
	mov db3, dbx			; Move complete byte into register
	sbrc mnr, 4			; Skip if not #4 marker
	mov db4, dbx			; Move complete byte into register
	sbrc mnr, 5			; Skip if not #5 marker
	mov db5, dbx			; Move complete byte into register
	sbrc mnr, 6			; Skip if not #6 marker
	mov db6, dbx			; Move complete byte into register
; Bit Value - Display Marker Bit
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $08			; Display 2, digit 8
	ldi d2l, $01			; Display 2, display '-' (marker bit)
	rcall Display_Write		; Write changes to display via SPI
	rjmp loop			; Start over

Set_One_Bit:	
	ldi bvr, 1<<ONE			; Set ONE in bvr
; Bit Value - Display One Bit
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $08			; Display 2, digit 8
	ldi d2l, $30			; Display 2, display '1' (one bit)
	rcall Display_Write		; Write changes to display via SPI
	rjmp Store_Bits			; Start over

Set_Zero_Bit:	
	ldi bvr, 1<<ZRO			; Set ZRO in bvr
; Bit Value - Display Zero Bit
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $08			; Display 2, digit 8
	ldi d2l, $7d			; Display 2, display '0' (zero bit)
	rcall Display_Write		; Write changes to display via SPI
	rjmp Store_Bits			; Start over

Set_Frame_Bit:	
	ldi bvr, 1<<FRM			; Set FRM in bvr
	clr bnr				; Clear bit number register
	ldi mnr, 1			; Reset marker bit position at start of minute
; Bit Value - Display Frame Marker Bit
	ldi d1h, $00			; Display 1, NOP
	ldi d1l, $00			; Display 1, NOP
	ldi d2h, $08			; Display 2, digit 8
	ldi d2l, $87			; Display 2, display 'F' (frame marker)
	rcall Display_Write		; Write changes to display via SPI
	rjmp loop			; Start over

; The following function takes the ONEs and ZROs and arranges them in a meaningful way into registers
Store_Bits:	
	cpi bnr, 4			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	cpi bnr, 14			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	cpi bnr, 24			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	cpi bnr, 34			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	cpi bnr, 44			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	cpi bnr, 54			; Check if middle bit (unused)
	breq Do_Not_Store		; Skip if middle bit
	lsl dbx				; Prepare for incoming bit by shifting reg left
	sbrc bvr, ONE			; Check for a ONE bit and if there is a ONE bit:
	sbr dbx, ONE			; Set a 1 in the 0th bit location
Do_Not_Store:
	rjmp loop			; Start over

; Because bits are serially shifted through both displays, all 32 bits need to be sent sequentially
Display_Write:
	cbi PORTB, PORTB2		; Pull down /SS/PB2 pin to start data transfer
	nop				; Give PORTB a cycle to adjust before allowing data xfer
	sts SPDR0, d1h			; Send display 1 (right display) address bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d1l			; Send display 1 (right display) data bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d2h			; Send display 2 (left display) address bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sts SPDR0, d2l			; Send display 2 (left display) data bits
	rcall SPI_DR_Check		; Check serial transmission status before proceeding
	sbi PORTB, PORTB2		; Pull up /SS/PB2 pin to end data transfer and latch bits into displaya registers
	ret

; A basic routine for checking when the Data Register is clear and ready to accept another byte
SPI_DR_Check:	
	lds tmp, SPSR0			; Read SPI Flag Register
	sbrs tmp, SPIF			; Check status of interrupt flag
	rjmp SPI_DR_Check		; Loop until flag detected
	ret				; Return to Display_Write routine
