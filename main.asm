; File name: TC Atomic Clock WWVB.asm
; Created  : 5/20/2019 4:12:10 PM
; Author   : Benjamin Russell KC7MMI
; MCU Trgt : Atmel AVR ATmega328P/Arduino Uno at 16MHz
; Objective: Device will take output from WWVB 60kHz receiver, decode and provide UTC time, day of year, and leap year indication

; Define bit register flags Z = ZRO; O = ONE; M = MRK; F = FRM
; 76543210
; xxxxFMOZ
.equ ZRO = 0		; Bit Value Register - Zero Flag
.equ ONE = 1		; Bit Value Register - One Flag
.equ MRK = 2		; Bit Value Register - Marker Flag
.equ FRM = 3		; Bit Value Register - Frame Flag

; Configuration of MAX7219 Display Driver
.equ D_NOP = $00	; No-op
.equ D_DIG1 = $01	; Digit 1 (datasheet says 0)
.equ D_DIG2 = $02	; Digit 2
.equ D_DIG3 = $03	; Digit 3
.equ D_DIG4 = $04	; Digit 4
.equ D_DIG5 = $05	; Digit 5
.equ D_DIG6 = $06	; Digit 6
.equ D_DIG7 = $07	; Digit 7
.equ D_DIG8 = $08	; Digit 8 (datasheet says 7)
.equ D_MOD = $09	; Decode Mode
.equ D_INT = $0a	; Intensity
.equ D_SCN = $0b	; Scan Limit
.equ D_SHT = $0c	; Shutdown
.equ D_TST = $0f	; Display Test

; WWVB goes High: Reset (clear, restart) timer
; WWVB goes Low: Check (stop, read) timer
; Timer reads <180mS: disregard
; Timer reads ~180mS: 0-bit
; Timer reads ~480mS: 1-bit
; Timer reads ~780mS: M-bit
; Timer reads >990mS: disregard
.equ PPD = 64					; Prescaler PerioD of 64uS
.equ T_ZRO = HIGH(181000/PPD)	; High byte of 181mS ($0b0c) for comparison to TC1
.equ T_ONE = HIGH(480000/PPD)	; High byte of 181mS ($1d4c) for comparison to TC1
.equ T_MRK = HIGH(780000/PPD)	; High byte of 181mS ($2f9b) for comparison to TC1
.equ T_MRKH = HIGH(990000/PPD)	; High byte of 181mS ($320c) for comparison to TC1
;.equ T_ZROH = HIGH(230000/PPD)	; High byte of 181mS ($0e09) for comparison to TC1
;.equ T_ONEH = HIGH(520000/PPD)	; High byte of 181mS ($1fbd) for comparison to TC1

; Registers r1:r0 are reserved for multiplication
.def databyte0	= r2		; Data Byte 0: Seconds
.def databyte1	= r3		; Data Byte 1: Minutes
.def databyte2	= r4		; Data Byte 2: Hours
.def databyte3	= r5		; Data Byte 3: High Nibble = Day 100s	& Low Nibble = Day 10s
.def databyte4	= r6		; Data Byte 4: High Nibble = Day 1s		& Low Nibble = DUT1 Sign 
.def databyte5	= r7		; Data Byte 5: High Nibble = DUT1 Value & Low Nibble = Year 10s
.def databyte6	= r8		; Data Byte 6: High Nibble = Year 1s    & Low Nibble = LY/LS/DST
.def temp	= r16		; Temp
.def data_rx	= r17		; Data Byte X
.def bit_val	= r18		; Bit value register
.def bit_num	= r19		; Bit number in minute
.def mark_num	= r20		; Marker number in minute
.def display1L	= r21		; Display 1 low byte
.def display1H	= r22		; Display 1 high byte
.def display2L	= r23		; Display 2 low byte
.def display2H	= r24		; Display 2 high byte

.cseg				; Code Segment
.org 0				; Start Program at Address 0

start:		
; Timer Setup
	ldi	temp, 0			; Load 0 in temp
	sts	TCCR1A, temp		; TC1 Control Reg A set to normal for simple counting operations
	sts	TCCR1C, temp		; TC1 Control Reg C set to normal for simple counting operations

; SPI Setup
	ldi	temp, $fe		; Prepare to configure DDRB
	out	DDRB, temp		; Configure all pins except PB0 as output
	sbi	PORTB, PORTB2		; /SS inactive
	sbi	PORTB, PORTB0		; Pullup for WWVB input
	ldi	temp, $50		; Enable SPI as Master with SPI clock set to fosc/4 (4MHz)
	out	SPCR, temp		; Set SPI Control Register 0
	out	SPSR, temp		; Set SPI Status Register (specifically SPI2X0)

; Display Setup - Decode Mode
	ldi	display1H, D_MOD	; Configure decode mode of display 1
	ldi	display1L, $fd		; All but 2nd from right digit Code B decode
	ldi	display2H, D_MOD	; Configure decode mode of display 2
	ldi	display2L, $1f		; All but left-most digit Code B decode
	rcall	Display_Write		; Write changes to display via SPI

; Display Setup - Intensity	
	ldi	display1H, D_INT	; Configure intensity mode of display 1
	ldi	display1L, $0f		; 31/32 duty cycle (brightest)
	ldi	display2H, D_INT	; Configure intensity mode of display 2
	ldi	display2L, $0f		; 31/32 duty cycle (brightest)
	rcall	Display_Write		; Write changes to display via SPI

; Display Setup - Scan Limit
	ldi	display1H, D_SCN	; Configure scan limit mode of display 1
	ldi	display1L, $07		; All digits displayed
	ldi	display2H, D_SCN	; Configure scan limit mode of display 2
	ldi	display2L, $07		; All digits displayed
	rcall	Display_Write		; Write changes to display via SPI

; Display Setup - Shutdown Mode
	ldi	display1H, D_SHT	; Configure shutdown mode of display 1
	ldi	display1L, $0f		; Normal operation
	ldi	display2H, D_SHT	; Configure shutdown mode of display 2
	ldi	display2L, $0f		; Normal operation
	rcall	Display_Write		; Write changes to display via SPI

; Display Setup - Display Test
	ldi	display1H, D_TST	; Configure display test mode of display 1
	ldi	display1L, $00		; Normal operation
	ldi	display2H, D_TST	; Configure display test mode of display 2
	ldi	display2L, $00		; Normal operation
	rcall	Display_Write		; Write changes to display via SPI

; Clear Registers
	clr	databyte0
	clr	databyte1
	clr	databyte2
	clr	databyte3
	clr	databyte4
	clr	databyte5
	clr	databyte6
	clr	bit_num
	clr	bit_val
	clr	mark_num

; Here we wait for the start of a pulse
Main_Loop:	
	sbic	PINB, PINB0		; Keep looping until PINB7 is pressed, at which point skip rjmp loop
	rjmp	Main_Loop		; Loop until PINB7 pressed

; WWVB Pulse Begin
	ldi	temp, 5			; Set values for clk/1024 prescaler to start timer
	sts	TCCR1B, temp		; Start TC1 and set prescaler to 1/1024

; Increment Seconds
	ldi	temp, $59		; Prepare to load 59 into databyte0 IF:
	sbrc	mark_num, 6		; If 6th marker received
	mov	databyte0, temp		; Put 59 into register to trick into rolling over
	inc	databyte0		; Increment 1s
	ldi	temp, $0f		; Setup bitmask
	and	temp, databyte0		; Copy only lower nibble into temp
	cpi	temp, $0a		; Time to roll over 1s?
	breq	Sec_Clr_1s		; If $xa, rollover 1s
	rjmp	Print_Time		; If not time to rollover, go print time
Sec_Clr_1s:				; Clear 1s and increment 10s
	ldi	temp, $f0		; Prepare for bitmask
	and	databyte0, temp		; Clear lower nibble in register
	swap	databyte0		; Swap nibbles for easy increment
	inc	databyte0		; Increment 10s
	swap	databyte0		; Put 10s back in their place
	mov	temp, databyte0		; Copy to temp for compare
	cpi	temp, $60		; Compare
	breq	Sec_Rollover		; Reset seconds 
	rjmp	Print_Time		; If not time to rollover, go print time
Sec_Rollover:
	clr	databyte0		; Reset register to 00

; Increment Minutes
	inc	databyte1		; Increment 1s
	ldi	temp, $0f		; Setup bitmask
	and	temp, databyte1		; Copy only lower nibble into temp
	cpi	temp, $0a		; Compare
	breq	Min_Clr_1s		; If $xa, rollover 1s
	rjmp	Print_Time		; If not time to rollover, go print time
Min_Clr_1s:				; Clear 1s and increment 10s
	ldi	temp, $f0		; Prepare for bitmask
	and	databyte1, temp		; Clear lower nibble in register
	swap	databyte1		; Swap nibbles for easy increment
	inc	databyte1		; Increment 10s
	swap	databyte1		; Put 10s back in their place
	mov	temp, databyte1		; Copy to temp for compare
	cpi	temp, $60		; Compare
	breq	Min_Rollover		; Branch to rollover minutes and continue
	rjmp	Print_Time		; If not time to rollover, go print time
Min_Rollover:
	clr	databyte1		; Reset register to 00

; Increment Hours
	inc	databyte2		; Increment 1s
	mov	temp, databyte2		; Copy only lower nibble into temp
	cpi	temp, $24		; Compare
	breq	Hr_Rollover		; Branch to rollover hour and continue
	andi	temp, $0f		; Setup bitmask
	cpi	temp, $0a		; Compare
	brne	Print_Time		; If not time to rollover, go print time
	ldi	temp, $f0		; Prepare for bitmask
	and	databyte2, temp		; Clear lower nibble in register
	swap	databyte2		; Swap nibbles for easy increment
	inc	databyte2		; Increment 10s
	swap	databyte2		; Put 10s back in their place
	rjmp	Print_Time		; Print time after rolling over 1s
Hr_Rollover:
	clr databyte2			; Reset register to 00

; Increment Days
	swap	databyte4		; Prepare to increment 1s
	inc	databyte4		; Increment 1s
	swap	databyte4		; Put 1s back in their place
	mov	temp, databyte3		; Prepare to compare 100s & 10s
	cpi	temp, $36		; Compare 100s & 10s
	brne	Day_Decimal		; Go compare 1s & look for 0xa if not last 5 days of year
	mov	temp, databyte4		; Prepare to compare 1s
	andi	temp, $f0		; Bitmask 1s
	cpi	temp, $60		; Compare 1s, look for end of year
	breq	Day_Rollover		; If end of year, rollover days
	rjmp	Print_Time		; Print time if not end of year
Day_Decimal:
	mov	temp, databyte4		; Prepare for bitmask
	andi	temp, $f0		; Apply bitmask for testing
	cpi	temp, $a0		; Compare with 10
	brne	Print_Time		; Print if less than 10
	ldi	temp, $0f		; Prepare to clr high nibble
	and	databyte4, temp		; Clr high nibble (day 1s)
; Increment Days - 10s
	inc	databyte3		; Increment 10s
	ldi	temp, $0f		; Setup bitmask
	and	temp, databyte3		; Copy only lower nibble into temp
	cpi	temp, $0a		; Compare
	brne	Print_Time		; If not time to rollover, go print time
	ldi	temp, $f0		; Prepare for bitmask
	and	databyte3, temp		; Clear lower nibble in register
	swap	databyte3		; Swap nibbles for easy increment
	inc	databyte3		; Increment 10s
	swap	databyte3		; Put 10s back in their place
	rjmp	Print_Time		; Print time
Day_Rollover:
	clr	databyte3		; Clr 100s & 10s
	ldi	temp, $0f		; Prepare to clr 1s
	and	databyte4, temp		; clr 1s
	ldi	temp, $10		; Prepare to set a 1 in the 1s
	or	databyte4, temp		; Start 1s off with 1 (day 1 of year xx)

; Increment Years
	swap	databyte6		; Prepare 1s for incrementing
	inc	databyte6		; Increment 1s
	swap	databyte6		; Put 1s back in their spot
	ldi	temp, $f0		; Setup bitmask
	and	temp, databyte6		; Copy only high nibble into temp
	cpi	temp, $a0		; Compare
	breq	Yr_Clr_1s		; If $ax, rollover 1s
	rjmp	Print_Time		; If not time to rollover, go print time
Yr_Clr_1s:
	ldi	temp, $0f		; Prepare for bitmask
	and	databyte6, temp		; Clear high nibble in register
	inc	databyte5		; Increment 10s
	ldi	temp, $0f		; Setup bitmask
	and	temp, databyte5		; Copy to temp for compare
	cpi	temp, $0a		; Compare
	breq	Yr_Rollover		; Reset seconds 
	rjmp	Print_Time		; If not time to rollover, go print time
Yr_Rollover:
	ldi	temp, $f0		; Setup bitmask
	and	databyte5, temp		; Clear low nibble (10s)

; Display time
; Sets up data registers to write 4 digits at a time, 2 for left display and 2 for right (saves on SPI bytes)
; |   Display 2   |.....|   Display 1   |
; |8|7|6|5|4|3|2|1|.....|8|7|6|5|4|3|2|1|
; |B|D| |YR | DAY |.....|HH |MM |SS |DUT|

Print_Time:
; Bit Value - Display WWVB Pulse With Decimal
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $80		; Display 2, display '.' (decimal)
	rcall	Display_Write		; Write changes to display via SPI

; Display Seconds
	ldi	display1H, D_DIG3	; Display 1, digit 3
	mov	display1L, databyte0	; Display 1, seconds 1s
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI
	ldi	display1H, D_DIG4	; Display 1, digit 4
	swap	display1L		; Display 1, seconds 10s
	rcall	Display_Write		; Write changes to display via SPI

; Display Minutes
	ldi	display1H, D_DIG5	; Display 1, digit 5
	mov	display1L, databyte1	; Display 1, minutes 1s
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI
	ldi	display1H, D_DIG6	; Display 1, digit 6
	swap	display1L		; Display 1, minutes 10s
	rcall	Display_Write		; Write changes to display via SPI

; Display Hours
	ldi	display1H, D_DIG7	; Display 1, digit 7
	mov	display1L, databyte2	; Display 1, hours 1s
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI
	ldi	display1H, D_DIG8	; Display 1, digit 8
	swap	display1L		; Display 1, hours 10s
	rcall	Display_Write		; Write changes to display via SPI

; Display Days (100s & 10s)
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG2	; Display 2, digit 2
	mov	display2L, databyte3	; Display 2, days 10s
	rcall	Display_Write		; Write changes to display via SPI
	ldi	display2H, D_DIG3	; Display 2, digit 3
	swap	display2L		; Display 2, days 100s
	rcall	Display_Write		; Write changes to display via SPI

; Display DUT1 Sign
	ldi	display1H, D_DIG2	; Display 1, digit 2
	ldi	display1L, $80		; Display 1, decimal point only
	sbrc	databyte4, 1		; Check for minus bit
	ldi	display1L, $81		; Display 1, decimal point & minus sign (segment G)
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI

; Display Days (1s)
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG1	; Display 2, digit 1
	mov	display2L, databyte4	; Display 2, prepare to display days 1s
	swap	display2L		; Display 2, days 1s
	rcall	Display_Write		; Write changes to display via SPI

; Display Year (10s)
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG5	; Display 2, digit 5
	mov	display2L, databyte5	; Display 2, years 10s
	rcall	Display_Write		; Write changes to display via SPI

; Display DUT1 Value
	ldi	display1H, D_DIG1	; Display 1, digit 1
	mov	display1L, databyte5	; Display 1, DUT1 value
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI

; Display LY/LS/DST
	ldi	display1H, D_DIG8	; Display 1, digit 8
	ldi	display1L, $00		; Display 1, clear
	sbrc	databyte6, 0		; Check for DST
	sbr	display1L, 1<<6		; If not clear, turn on segment A for DST
	sbrc	databyte6, 2		; Check for LS
	sbr	display1L, 1<<3		; If not clear, turn on segment D for LS
	sbrc	databyte6, 3		; Check for LY
	sbr	display1L, 1<<0		; If not clear, turn on segment G for LY
	ldi	display2H, D_NOP	; Display 2, NOP
	ldi	display2L, D_NOP	; Display 2, NOP
	rcall	Display_Write		; Write changes to display via SPI

; Display Year (1s)
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG4	; Display 2, digit 4
	mov	display2L, databyte6	; Display 2, prepare to display years 1s
	swap	display2L		; Display 2, years 1s
	rcall	Display_Write		; Write changes to display via SPI

; Checking for pulse lengths similar to those listed below and outputs to bit value register
; WWVB PWM Format: pulse of 200mS = 0-bit; 500mS = 1-bit; 800mS = marker bit
; Here we wait for the end of the pulse
; Only comparing high byte of timer since precision is not needed
Clock_Pulse:	
	sbis	PINB, PINB0		; Keep looping until WWVB pulse ends, at which point exit loop
	rjmp	Clock_Pulse		; Loop until pulse ends

; WWVB Pulse End - Check Width of Pulse
	ldi	temp, 0			; For clearing the timer registers later
	sts	TCCR1B, temp		; Stop TC1 to read values
	lds	XL, TCNT1L		; Load TC1 Low value into working register
	lds	XH, TCNT1H		; Load TC1 High value into working register
	sts	TCNT1H, temp		; Clear TC1 High value
	sts	TCNT1L, temp		; Clear TC1 Low value
	cpi	XH, T_MRKH		; Check for too long of pulse
	brge	Clr_Bit_Val		; If too long, clear the bit_val
	cpi	XH, T_MRK		; Check for MRK pulse
	brge	Set_Mrkr_Bit		; If MRK, set MRK; also sets FRM
	cpi	XH, T_ONE		; Check for ONE pulse
	brge	Set_One_Bit		; If ONE, set ONE
	cpi	XH, T_ZRO		; Check for ZRO pulse
	brge	Set_Zero_Bit		; If ZRO, set ZRO
	brlt	Clr_Bit_Val		; If too short, clear the bit_val

Clr_Bit_Val:	
	clr	bit_val			; Clear all bits in bit_val
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $65		; Display 2, display '?' (question mark)
	rcall	Display_Write		; Write changes to display via SPI
	rjmp	Main_Loop		; Start over

Set_Mrkr_Bit:	
	sbrc	bit_val, MRK		; Skip Set_Frame_Bit if no previous MRK
	rjmp	Set_Frame_Bit		; If previous pulse, Set_Frame_Bit
	ldi	bit_val, 1<<MRK		; If no previous MRK, set MRK in bit_val
	lsl	mark_num		; Shift bit left for each marker
	sbrc	mark_num, 1		; Skip if not #1 marker
	mov	databyte1, data_rx	; Move complete byte into register
	sbrc	mark_num, 2		; Skip if not #2 marker
	mov	databyte2, data_rx	; Move complete byte into register
	sbrc	mark_num, 3		; Skip if not #3 marker
	mov	databyte3, data_rx	; Move complete byte into register
	sbrc	mark_num, 4		; Skip if not #4 marker
	mov	databyte4, data_rx	; Move complete byte into register
	sbrc	mark_num, 5		; Skip if not #5 marker
	mov	databyte5, data_rx	; Move complete byte into register
	sbrc	mark_num, 6		; Skip if not #6 marker
	mov	databyte6, data_rx	; Move complete byte into register
; Bit Value - Display Marker Bit
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $01		; Display 2, display '-' (marker bit)
	rcall	Display_Write		; Write changes to display via SPI
	rjmp	Main_Loop		; Start over

Set_Frame_Bit:	
	ldi	bit_val, 1<<FRM		; Set FRM in bit_val
	clr	bit_num			; Clear bit number register
	ldi	mark_num, 1		; Reset marker bit position at start of minute
; Bit Value - Display Frame Marker Bit
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $47		; Display 2, display 'F' (frame marker)
	rcall	Display_Write		; Write changes to display via SPI
	rjmp	Main_Loop		; Start over

Set_One_Bit:	
	ldi	bit_val, 1<<ONE		; Set ONE in bit_val
; Bit Value - Display One Bit
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $30		; Display 2, display '1' (one bit)
	rcall	Display_Write		; Write changes to display via SPI
	rjmp	Store_Bits		; Put bits into working reg data_rx & ignore middle bits

Set_Zero_Bit:	
	ldi	bit_val, 1<<ZRO		; Set ZRO in bit_val
; Bit Value - Display Zero Bit
	ldi	display1H, D_NOP	; Display 1, NOP
	ldi	display1L, D_NOP	; Display 1, NOP
	ldi	display2H, D_DIG8	; Display 2, digit 8
	ldi	display2L, $7e		; Display 2, display '0' (zero bit)
	rcall	Display_Write		; Write changes to display via SPI
	rjmp	Store_Bits		; Put bits into working reg data_rx & ignore middle bits

; The following function takes the ONEs and ZROs and arranges them in a meaningful way into registers
Store_Bits:	
	cpi	bit_num, 4		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	cpi	bit_num, 14		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	cpi	bit_num, 24		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	cpi	bit_num, 34		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	cpi	bit_num, 44		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	cpi	bit_num, 54		; Check if middle bit (unused)
	breq	Do_Not_Store		; Skip if middle bit
	lsl	data_rx			; Prepare for incoming bit by shifting reg left
	sbrc	bit_val, ONE		; Check for a ONE bit and if there is a ONE bit:
	sbr	data_rx, ONE		; Set a 1 in the 0th bit location
Do_Not_Store:
	rjmp	Main_Loop		; Start over

; Because bits are serially shifted through both displays, all 32 bits need to be sent sequentially
Display_Write:
	cbi	PORTB, PORTB2		; Pull down /SS/PB2 pin to start data transfer
	out	SPDR, display1H		; Send display 1 (right display) address bits
	rcall	SPI_DR_Check		; Check serial transmission status before proceeding
	out	SPDR, display1L		; Send display 1 (right display) data bits
	rcall	SPI_DR_Check		; Check serial transmission status before proceeding
	out	SPDR, display2H		; Send display 2 (left display) address bits
	rcall	SPI_DR_Check		; Check serial transmission status before proceeding
	out	SPDR, display2L		; Send display 2 (left display) data bits
	rcall	SPI_DR_Check		; Check serial transmission status before proceeding
	sbi	PORTB, PORTB2		; Pull up /SS/PB2 pin to end data transfer and latch bits into displaya registers
	ret

; A basic routine for checking when the Data Register is clear and ready to accept another byte
SPI_DR_Check:	
	in	temp, SPSR		; Read SPI Flag Register
	sbrs	temp, SPIF		; Check status of interrupt flag
	rjmp	SPI_DR_Check		; Loop until flag detected
	ret				; Return to Display_Write routine
