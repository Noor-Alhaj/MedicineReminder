#include <xc.inc>

;========================================================
; MEDICINE REMINDER SYSTEM
; PIC16F877A
; CLOCK = 4 MHz
;
; LCD 16x2 - 4 BIT
; RS -> RD1
; E  -> RD2
; D4 -> RD4
; D5 -> RD5
; D6 -> RD6
; D7 -> RD7
;
; KEYPAD 3x4
; Row A -> RB0
; Row B -> RB1
; Row C -> RB2
; Row D -> RB3
; Col 1 -> RB4
; Col 2 -> RB5
; Col 3 -> RB6
;
; ACK  -> RC0
; LED1 -> RC1
; LED2 -> RC2
; LED3 -> RC3
; BUZZER -> RC4
;========================================================


;========================================================
; CONFIGURATION
;========================================================

CONFIG  FOSC = XT       ; crystal mode (not internal RC)
CONFIG  WDTE = OFF      ; watchdog OFF
CONFIG  PWRTE = ON      ; power-up timer ON. after we apply 5 V, wait ~72 ms before main so the crystal and supply become stable
CONFIG  BOREN = OFF     ; brown-out reset OFF. Proteus VDD is a clean 5 V
CONFIG  LVP = OFF       ; low-voltage programming OFF (so RB3 is a normal I/O pin (keypad row))
CONFIG  CPD = OFF       ; lock1: do not lock EEPROM (nothing secret)
CONFIG  WRT = OFF       ; lock2: do not write-protect flash
CONFIG  CP  = OFF       ; lock3: do not code-protect the program
                        
; Note: the three OFF locks = we can read/rebuild the HEX


;========================================================
; VARIABLES  (Bank 0)
;
; PSECT udata_bank0 = put ALL our GPRs in Bank 0.
; name: DS 1  = reserve 1 byte and call it "name"
;========================================================

PSECT udata_bank0

delay1:       DS 1      ; For Welcome screen step   
delay2:       DS 1      ; For Welcome screen step    
delay3:       DS 1      ; For Welcome screen step    

lcd_byte:     DS 1	; For Welcome screen step 
lcd_nibble:   DS 1	; For Welcome screen step 

key_code:     DS 1

;--------------------------------------------------------
; Time input digits
;--------------------------------------------------------

hour_tens:    DS 1	; For set current time step 
hour_ones:    DS 1	; For set current time step 
min_tens:     DS 1	; For set current time step 
min_ones:     DS 1	; For set current time step 

;--------------------------------------------------------
; Current time, to save it RAM as binary 
;--------------------------------------------------------

hour:         DS 1	; For set current time step
minute:       DS 1	; For set current time step

;--------------------------------------------------------
; Medicine 1, to save it RAM as binary
;--------------------------------------------------------

med1_hour:    DS 1
med1_minute:  DS 1

;--------------------------------------------------------
; Medicine 2, to save it RAM as binary
;--------------------------------------------------------

med2_hour:    DS 1
med2_minute:  DS 1

;--------------------------------------------------------
; Medicine 3, to save it RAM as binary
;--------------------------------------------------------

med3_hour:    DS 1
med3_minute:  DS 1

;--------------------------------------------------------
; Number of entered digits
;--------------------------------------------------------

digit_count:  DS 1

;--------------------------------------------------------
; Temporary calculation variable (when turn ASCII to binary)
;--------------------------------------------------------

calc_temp:    DS 1

;--------------------------------------------------------
; Next medicine display variables
;--------------------------------------------------------
next_med:     DS 1
next_hour:    DS 1
next_minute:  DS 1
next_valid:   DS 1

;--------------------------------------------------------
; Reminder variables
;--------------------------------------------------------
reminder_active: DS 1
reminder_med:    DS 1
blink_state:     DS 1

; 1 = already Taken or Missed today. Midnight clears them.
med1_served:     DS 1
med2_served:     DS 1
med3_served:     DS 1

; Counts 1-second ticks while an alert is on (20 = miss).
miss_count:      DS 1

; HH:MM of this alert. Clock moves during Dose Taken, so
; we keep this slot to find the next same-time medicine.
alert_hour:      DS 1
alert_minute:    DS 1

;--------------------------------------------------------
; Timer0 variables
;--------------------------------------------------------
timer_count:  DS 1
minute_tick:  DS 1

; ISR context save variables
w_temp:       DS 1
status_temp: DS 1
pclath_temp: DS 1


;========================================================
; RESET VECTOR
; PSECT resetVec = a named block of program flash
; class=CODE    = instructions, not RAM
; delta=2       = PIC16: 1 instruction = 2 bytes
; abs           = we pick the address (not the linker)
;========================================================

PSECT resetVec,class=CODE,delta=2,abs
ORG 0x0000

resetVec:
    goto    main


;========================================================
; INTERRUPT VECTOR
;========================================================

PSECT intVec,class=CODE,delta=2,abs
ORG 0x0004

intVec:
    goto    Timer0_ISR


;========================================================
; MAIN
;========================================================

PSECT code

main:

    ;----------------------------------------------------
    ; PORT B
    ; RB0-RB3 = keypad rows OUTPUT
    ; RB4-RB6 = keypad columns INPUT
    ;----------------------------------------------------

    BANKSEL TRISB 

    movlw   0xF0 
    movwf   TRISB ; Direnction of input/output
 
    BANKSEL PORTB 

    movlw   0x0F ; Set the outputs high 
    movwf   PORTB


    ;----------------------------------------------------
    ; Enable PORTB weak pull-ups
    ;----------------------------------------------------

    BANKSEL OPTION_REG 

    bcf     OPTION_REG,7 ; 0->Enable pull-ups 


    ;----------------------------------------------------
    ; PORT C
    ; RC0 = ACK input
    ; RC1 = Medicine 1 LED output
    ; RC2 = Medicine 2 LED output
    ; RC3 = Medicine 3 LED output
    ; RC4 = Buzzer output
    ;----------------------------------------------------

    BANKSEL TRISC

    movlw   0x01
    movwf   TRISC

    BANKSEL PORTC

    clrf    PORTC


    ;----------------------------------------------------
    ; PORT D = LCD
    ;----------------------------------------------------

    BANKSEL TRISD

    clrf    TRISD ; All outputs 

    BANKSEL PORTD

    clrf    PORTD  


    ;----------------------------------------------------
    ; Clear variables
    ;----------------------------------------------------

    BANKSEL hour_tens 

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    clrf    hour
    clrf    minute

    clrf    med1_hour
    clrf    med1_minute

    clrf    med2_hour
    clrf    med2_minute

    clrf    med3_hour
    clrf    med3_minute

    clrf    digit_count
    clrf    calc_temp
    clrf    next_med
    clrf    next_hour
    clrf    next_minute
    clrf    next_valid
    clrf    reminder_active
    clrf    reminder_med
    clrf    blink_state
    clrf    med1_served
    clrf    med2_served
    clrf    med3_served
    clrf    miss_count
    clrf    alert_hour
    clrf    alert_minute


    ;----------------------------------------------------
    ; LCD initialization
    ;----------------------------------------------------

    call    LCD_Init

    ; Welcome screen
    call    Display_Welcome
    call    Delay_Welcome

    call    Display_Set_Time

    goto    Time_Input_Loop


;========================================================
; CURRENT TIME INPUT
;========================================================

Time_Input_Loop:

    call    Keypad_GetKey
    movwf   key_code ; key_code = w (the returen value from keypad_Getkey)


    ;----------------------------------------------------
    ; * = CLEAR
    ;----------------------------------------------------

    movf    key_code,W
    xorlw   '*' ; Compare W with '*'

    btfsc   STATUS,2 ; if z = 0 (not '*') -> skip and check if '#'
    goto    Clear_Time_Input


    ;----------------------------------------------------
    ; # = CONFIRM
    ;----------------------------------------------------

    movf    key_code,W 
    xorlw   '#' ; Compare W with '#'

    btfsc   STATUS,2 ; if z = 0 (not '#') -> skip and check Digit
    goto    Confirm_Time


    ;----------------------------------------------------
    ; DIGIT
    ;----------------------------------------------------

    goto    Current_Digit_Check


;========================================================
; CURRENT TIME DIGIT CHECK
;========================================================

Current_Digit_Check:
    
    movf    digit_count,W      ; how many digits already saved 
    xorlw   0                  ; is it 0?
    
    btfsc   STATUS,2           ; Z=0 -> count is not 0 -> skip
    goto    Enter_Hour_Tens    ; Z=1 -> count is 0 -> this key = hour tens
    
    movf    digit_count,W
    xorlw   1                  ; already have 1 digit?
    
    btfsc   STATUS,2           ; not 1 -> skip
    goto    Enter_Hour_Ones    ; yes 1 -> this key = hour ones
    
    movf    digit_count,W
    xorlw   2
    
    btfsc   STATUS,2
    goto    Enter_Min_Tens     ; already 2 digits -> this key = minute tens
    
    movf    digit_count,W
    xorlw   3
    
    btfsc   STATUS,2
    goto    Enter_Min_Ones     ; already 3 digits -> this key = minute ones
    
    goto    Time_Input_Loop    ; already 4 digits: ignore extra 0-9, wait for * or #


;========================================================
; ENTER HOUR TENS
;========================================================

Enter_Hour_Tens:

    movf    key_code,W ; W = the digit we just pressed 
    movwf   hour_tens ; save it in RAM (hour_tens)

    movlw   0xC0 ; Line 2, Column 0 
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F ; digit_count ++ 

    goto    Time_Input_Loop ; Wait for the next key 


;========================================================
; ENTER HOUR ONES
;========================================================

Enter_Hour_Ones:

    movf    key_code,W
    movwf   hour_ones

    movlw   0xC1 ; Line 2, Column 1 
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Time_Input_Loop


;========================================================
; ENTER MINUTE TENS
;========================================================

Enter_Min_Tens:

    movf    key_code,W
    movwf   min_tens

    movlw   0xC3 ; Line 2, Column 3
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Time_Input_Loop


;========================================================
; ENTER MINUTE ONES
;========================================================

Enter_Min_Ones:

    movf    key_code,W
    movwf   min_ones

    movlw   0xC4 ; Line 2, Column 4 
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Time_Input_Loop


;========================================================
; CLEAR CURRENT TIME (user pressed '*')
;========================================================

Clear_Time_Input:

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    clrf    hour
    clrf    minute

    clrf    digit_count

    call    Display_Set_Time

    goto    Time_Input_Loop


;========================================================
; CONFIRM CURRENT TIME (user entered '#') 
;========================================================

Confirm_Time:

    ; Exactly 4 digits required

    movf    digit_count,W
    xorlw   4 ; check if w = 4

    btfss   STATUS,2 ; If digit_count is 4, XOR is 0 and Z = 1 -> skip 
    goto    Invalid_Time ; w not 4 digits 


    ;----------------------------------------------------
    ; Hour tens <= 2
    ;----------------------------------------------------

    movf    hour_tens,W
    sublw   '2' ; W = '2' - hour_tens

    btfss   STATUS,0  ; C = 1 (tens <= 2) -> skip
    goto    Invalid_Time ; C = 0 (tens >= 3), Ex: 27:00


    ;----------------------------------------------------
    ; If hour tens = 2 -> hour ones must be <= 3
    ; If tens is 0 or 1 -> hour ones valid to be (0..9)
    ;----------------------------------------------------

    movf    hour_tens,W
    xorlw   '2' ; is tens the character '2'?

    btfss   STATUS,2 ; Z=1 (it is 2) -> skip Hours_Valid, check ones
    goto    Hours_Valid ; Z=0 (0 or 1) -> hour is fine


    movf    hour_ones,W ; tens was 2, so check second digit
    sublw   '3'

    btfss   STATUS,0 ; C = 1 (ones <= 3) -> skip
    goto    Invalid_Time ; C = 0 (24..29) -> Invalid 


Hours_Valid: ; Hours was valid now check minutes 

    ;----------------------------------------------------
    ; Minute tens <= 5
    ;----------------------------------------------------

    movf    min_tens,W
    sublw   '5'

    btfss   STATUS,0
    goto    Invalid_Time


;========================================================
; CURRENT TIME VALID
;========================================================

Valid_Time:

    ;----------------------------------------------------
    ; Convert hour tens
    ; hour = tens * 10
    ;----------------------------------------------------

    movf    hour_tens,W
    addlw   -'0' ; Convert ASCII to number 
    movwf   calc_temp

    movf    calc_temp,W
    movwf   hour

    ; hour = digit * 2
    movf    hour,W
    addwf   hour,F

    ; hour = digit * 4
    movf    hour,W
    addwf   hour,F

    ; hour = digit * 8
    movf    hour,W
    addwf   hour,F

    ; hour = digit * 9
    movf    calc_temp,W
    addwf   hour,F

    ; hour = digit * 10
    movf    calc_temp,W
    addwf   hour,F


    ; Add hour ones

    movf    hour_ones,W
    addlw   -'0'
    addwf   hour,F


    ;----------------------------------------------------
    ; Convert minute tens
    ; minute = tens * 10
    ;----------------------------------------------------

    movf    min_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   minute

    ; minute = digit * 2
    movf    minute,W
    addwf   minute,F

    ; minute = digit * 4
    movf    minute,W
    addwf   minute,F

    ; minute = digit * 8
    movf    minute,W
    addwf   minute,F

    ; minute = digit * 9
    movf    calc_temp,W
    addwf   minute,F

    ; minute = digit * 10
    movf    calc_temp,W
    addwf   minute,F


    ; Add minute ones

    movf    min_ones,W
    addlw   -'0'
    addwf   minute,F


    ;----------------------------------------------------
    ; Display TIME SET
    ;----------------------------------------------------

    movlw   0x01
    call    LCD_Command

    call    Delay_Long

    movlw   'T'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   'S'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    call    Delay_Invalid


    ;----------------------------------------------------
    ; Prepare Medicine 1
    ;----------------------------------------------------

    clrf    digit_count

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    call    Display_Medicine1

    goto    Medicine1_Input_Loop


;========================================================
; INVALID CURRENT TIME
;========================================================

Invalid_Time:

    call    LCD_Clear


    ; First line = INVALID

    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'V'
    call    LCD_Data

    movlw   'A'
    call    LCD_Data

    movlw   'L'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data


    ; Second line = TIME

    movlw   0xC0
    call    LCD_Command

    movlw   'T'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data


    call    Delay_Invalid


    clrf    digit_count

    call    Display_Set_Time

    goto    Time_Input_Loop


;========================================================
; MEDICINE 1 DISPLAY
;========================================================

Display_Medicine1:

    call    LCD_Clear


    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'C'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '1'
    call    LCD_Data


    movlw   0xC0
    call    LCD_Command

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   ':'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    return


;========================================================
; MEDICINE 1 INPUT
;========================================================

Medicine1_Input_Loop:

    call    Keypad_GetKey
    movwf   key_code


    ; * = clear

    movf    key_code,W
    xorlw   '*'

    btfsc   STATUS,2
    goto    Clear_Medicine1


    ; # = confirm

    movf    key_code,W
    xorlw   '#'

    btfsc   STATUS,2
    goto    Confirm_Medicine1


    ; Digit 0

    movf    digit_count,W
    xorlw   0

    btfsc   STATUS,2
    goto    Med1_Hour_Tens


    ; Digit 1

    movf    digit_count,W
    xorlw   1

    btfsc   STATUS,2
    goto    Med1_Hour_Ones


    ; Digit 2

    movf    digit_count,W
    xorlw   2

    btfsc   STATUS,2
    goto    Med1_Min_Tens


    ; Digit 3

    movf    digit_count,W
    xorlw   3

    btfsc   STATUS,2
    goto    Med1_Min_Ones


    goto    Medicine1_Input_Loop


;========================================================
; MED 1 HOUR TENS
;========================================================

Med1_Hour_Tens:

    movf    key_code,W
    movwf   hour_tens

    movlw   0xC0
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine1_Input_Loop


;========================================================
; MED 1 HOUR ONES
;========================================================

Med1_Hour_Ones:

    movf    key_code,W
    movwf   hour_ones

    movlw   0xC1
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine1_Input_Loop


;========================================================
; MED 1 MINUTE TENS
;========================================================

Med1_Min_Tens:

    movf    key_code,W
    movwf   min_tens

    movlw   0xC3
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine1_Input_Loop


;========================================================
; MED 1 MINUTE ONES
;========================================================

Med1_Min_Ones:

    movf    key_code,W
    movwf   min_ones

    movlw   0xC4
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine1_Input_Loop


;========================================================
; CLEAR MEDICINE 1
;========================================================

Clear_Medicine1:

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    clrf    digit_count

    call    Display_Medicine1

    goto    Medicine1_Input_Loop


;========================================================
; CONFIRM MEDICINE 1
;========================================================

Confirm_Medicine1:

    movf    digit_count,W
    xorlw   4

    btfss   STATUS,2
    goto    Invalid_Medicine1


    ; Hour tens <= 2

    movf    hour_tens,W
    sublw   '2'

    btfss   STATUS,0
    goto    Invalid_Medicine1


    ; If hour tens = 2, hour ones <= 3

    movf    hour_tens,W
    xorlw   '2'

    btfss   STATUS,2
    goto    Med1_Hours_Valid


    movf    hour_ones,W
    sublw   '3'

    btfss   STATUS,0
    goto    Invalid_Medicine1


Med1_Hours_Valid:

    ; Minute tens <= 5

    movf    min_tens,W
    sublw   '5'

    btfss   STATUS,0
    goto    Invalid_Medicine1


;========================================================
; SAVE MEDICINE 1
;========================================================

Valid_Medicine1:

    ;----------------------------------------------------
    ; Hour tens * 10
    ;----------------------------------------------------

    movf    hour_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med1_hour

    ; med1_hour = digit * 2
    movf    med1_hour,W
    addwf   med1_hour,F

    ; med1_hour = digit * 4
    movf    med1_hour,W
    addwf   med1_hour,F

    ; med1_hour = digit * 8
    movf    med1_hour,W
    addwf   med1_hour,F

    ; med1_hour = digit * 9
    movf    calc_temp,W
    addwf   med1_hour,F

    ; med1_hour = digit * 10
    movf    calc_temp,W
    addwf   med1_hour,F


    ; Add hour ones

    movf    hour_ones,W
    addlw   -'0'
    addwf   med1_hour,F


    ;----------------------------------------------------
    ; Minute tens * 10
    ;----------------------------------------------------

    movf    min_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med1_minute

    ; med1_minute = digit * 2
    movf    med1_minute,W
    addwf   med1_minute,F

    ; med1_minute = digit * 4
    movf    med1_minute,W
    addwf   med1_minute,F

    ; med1_minute = digit * 8
    movf    med1_minute,W
    addwf   med1_minute,F

    ; med1_minute = digit * 9
    movf    calc_temp,W
    addwf   med1_minute,F

    ; med1_minute = digit * 10
    movf    calc_temp,W
    addwf   med1_minute,F


    ; Add minute ones

    movf    min_ones,W
    addlw   -'0'
    addwf   med1_minute,F


    ;----------------------------------------------------
    ; MED 1 SET
    ;----------------------------------------------------

    movlw   0x01
    call    LCD_Command

    call    Delay_Long

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '1'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   'S'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    call    Delay_Invalid


    ;----------------------------------------------------
    ; Prepare Medicine 2
    ;----------------------------------------------------

    clrf    digit_count

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    call    Display_Medicine2

    goto    Medicine2_Input_Loop


;========================================================
; INVALID MEDICINE 1
;========================================================

Invalid_Medicine1:

    call    LCD_Clear


    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'V'
    call    LCD_Data

    movlw   'A'
    call    LCD_Data

    movlw   'L'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data


    movlw   0xC0
    call    LCD_Command

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '1'
    call    LCD_Data


    call    Delay_Invalid

    clrf    digit_count

    call    Display_Medicine1

    goto    Medicine1_Input_Loop


;========================================================
; MEDICINE 2 DISPLAY
;========================================================

Display_Medicine2:

    call    LCD_Clear


    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'C'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '2'
    call    LCD_Data


    movlw   0xC0
    call    LCD_Command

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   ':'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    return


;========================================================
; MEDICINE 2 INPUT
;========================================================

Medicine2_Input_Loop:

    call    Keypad_GetKey
    movwf   key_code


    ; * = clear

    movf    key_code,W
    xorlw   '*'

    btfsc   STATUS,2
    goto    Clear_Medicine2


    ; # = confirm

    movf    key_code,W
    xorlw   '#'

    btfsc   STATUS,2
    goto    Confirm_Medicine2


    ; Digit 0

    movf    digit_count,W
    xorlw   0

    btfsc   STATUS,2
    goto    Med2_Hour_Tens


    ; Digit 1

    movf    digit_count,W
    xorlw   1

    btfsc   STATUS,2
    goto    Med2_Hour_Ones


    ; Digit 2

    movf    digit_count,W
    xorlw   2

    btfsc   STATUS,2
    goto    Med2_Min_Tens


    ; Digit 3

    movf    digit_count,W
    xorlw   3

    btfsc   STATUS,2
    goto    Med2_Min_Ones


    goto    Medicine2_Input_Loop


;========================================================
; MED 2 HOUR TENS
;========================================================

Med2_Hour_Tens:

    movf    key_code,W
    movwf   hour_tens

    movlw   0xC0
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine2_Input_Loop


;========================================================
; MED 2 HOUR ONES
;========================================================

Med2_Hour_Ones:

    movf    key_code,W
    movwf   hour_ones

    movlw   0xC1
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine2_Input_Loop


;========================================================
; MED 2 MINUTE TENS
;========================================================

Med2_Min_Tens:

    movf    key_code,W
    movwf   min_tens

    movlw   0xC3
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine2_Input_Loop


;========================================================
; MED 2 MINUTE ONES
;========================================================

Med2_Min_Ones:

    movf    key_code,W
    movwf   min_ones

    movlw   0xC4
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine2_Input_Loop


;========================================================
; CLEAR MEDICINE 2
;========================================================

Clear_Medicine2:

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    clrf    digit_count

    call    Display_Medicine2

    goto    Medicine2_Input_Loop


;========================================================
; CONFIRM MEDICINE 2
;========================================================

Confirm_Medicine2:

    movf    digit_count,W
    xorlw   4

    btfss   STATUS,2
    goto    Invalid_Medicine2


    ; Hour tens <= 2

    movf    hour_tens,W
    sublw   '2'

    btfss   STATUS,0
    goto    Invalid_Medicine2


    ; If hour tens = 2, hour ones <= 3

    movf    hour_tens,W
    xorlw   '2'

    btfss   STATUS,2
    goto    Med2_Hours_Valid


    movf    hour_ones,W
    sublw   '3'

    btfss   STATUS,0
    goto    Invalid_Medicine2


Med2_Hours_Valid:

    ; Minute tens <= 5

    movf    min_tens,W
    sublw   '5'

    btfss   STATUS,0
    goto    Invalid_Medicine2


;========================================================
; SAVE MEDICINE 2
;========================================================

Valid_Medicine2:

    ;----------------------------------------------------
    ; Hour tens * 10
    ;----------------------------------------------------

    movf    hour_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med2_hour

    ; med2_hour = digit * 2
    movf    med2_hour,W
    addwf   med2_hour,F

    ; med2_hour = digit * 4
    movf    med2_hour,W
    addwf   med2_hour,F

    ; med2_hour = digit * 8
    movf    med2_hour,W
    addwf   med2_hour,F

    ; med2_hour = digit * 9
    movf    calc_temp,W
    addwf   med2_hour,F

    ; med2_hour = digit * 10
    movf    calc_temp,W
    addwf   med2_hour,F


    ; Add hour ones

    movf    hour_ones,W
    addlw   -'0'
    addwf   med2_hour,F


    ;----------------------------------------------------
    ; Minute tens * 10
    ;----------------------------------------------------

    movf    min_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med2_minute

    ; med2_minute = digit * 2
    movf    med2_minute,W
    addwf   med2_minute,F

    ; med2_minute = digit * 4
    movf    med2_minute,W
    addwf   med2_minute,F

    ; med2_minute = digit * 8
    movf    med2_minute,W
    addwf   med2_minute,F

    ; med2_minute = digit * 9
    movf    calc_temp,W
    addwf   med2_minute,F

    ; med2_minute = digit * 10
    movf    calc_temp,W
    addwf   med2_minute,F


    ; Add minute ones

    movf    min_ones,W
    addlw   -'0'
    addwf   med2_minute,F


    ;----------------------------------------------------
    ; MED 2 SET
    ;----------------------------------------------------

    movlw   0x01
    call    LCD_Command

    call    Delay_Long

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '2'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   'S'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    call    Delay_Invalid


    ;----------------------------------------------------
    ; Prepare Medicine 3
    ;----------------------------------------------------

    clrf    digit_count

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    call    Display_Medicine3

    goto    Medicine3_Input_Loop


;========================================================
; INVALID MEDICINE 2
;========================================================

Invalid_Medicine2:

    call    LCD_Clear


    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'V'
    call    LCD_Data

    movlw   'A'
    call    LCD_Data

    movlw   'L'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data


    movlw   0xC0
    call    LCD_Command

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '2'
    call    LCD_Data


    call    Delay_Invalid

    clrf    digit_count

    call    Display_Medicine2

    goto    Medicine2_Input_Loop


;========================================================
; MEDICINE 3 DISPLAY
;========================================================

Display_Medicine3:

    call    LCD_Clear


    ;----------------------------------------------------
    ; First line = MEDICINE 3
    ;----------------------------------------------------

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'C'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '3'
    call    LCD_Data


    ;----------------------------------------------------
    ; Second line = __:__
    ;----------------------------------------------------

    movlw   0xC0
    call    LCD_Command

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   ':'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    return


;========================================================
; MEDICINE 3 INPUT
;========================================================

Medicine3_Input_Loop:

    call    Keypad_GetKey
    movwf   key_code


    ;----------------------------------------------------
    ; * = clear
    ;----------------------------------------------------

    movf    key_code,W
    xorlw   '*'

    btfsc   STATUS,2
    goto    Clear_Medicine3


    ;----------------------------------------------------
    ; # = confirm
    ;----------------------------------------------------

    movf    key_code,W
    xorlw   '#'

    btfsc   STATUS,2
    goto    Confirm_Medicine3


    ;----------------------------------------------------
    ; Digit 0
    ;----------------------------------------------------

    movf    digit_count,W
    xorlw   0

    btfsc   STATUS,2
    goto    Med3_Hour_Tens


    ;----------------------------------------------------
    ; Digit 1
    ;----------------------------------------------------

    movf    digit_count,W
    xorlw   1

    btfsc   STATUS,2
    goto    Med3_Hour_Ones


    ;----------------------------------------------------
    ; Digit 2
    ;----------------------------------------------------

    movf    digit_count,W
    xorlw   2

    btfsc   STATUS,2
    goto    Med3_Min_Tens


    ;----------------------------------------------------
    ; Digit 3
    ;----------------------------------------------------

    movf    digit_count,W
    xorlw   3

    btfsc   STATUS,2
    goto    Med3_Min_Ones


    goto    Medicine3_Input_Loop


;========================================================
; MED 3 HOUR TENS
;========================================================

Med3_Hour_Tens:

    movf    key_code,W
    movwf   hour_tens

    movlw   0xC0
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine3_Input_Loop


;========================================================
; MED 3 HOUR ONES
;========================================================

Med3_Hour_Ones:

    movf    key_code,W
    movwf   hour_ones

    movlw   0xC1
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine3_Input_Loop


;========================================================
; MED 3 MINUTE TENS
;========================================================

Med3_Min_Tens:

    movf    key_code,W
    movwf   min_tens

    movlw   0xC3
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine3_Input_Loop


;========================================================
; MED 3 MINUTE ONES
;========================================================

Med3_Min_Ones:

    movf    key_code,W
    movwf   min_ones

    movlw   0xC4
    call    LCD_Command

    movf    key_code,W
    call    LCD_Data

    incf    digit_count,F

    goto    Medicine3_Input_Loop


;========================================================
; CLEAR MEDICINE 3
;========================================================

Clear_Medicine3:

    clrf    hour_tens
    clrf    hour_ones
    clrf    min_tens
    clrf    min_ones

    clrf    digit_count

    call    Display_Medicine3

    goto    Medicine3_Input_Loop


;========================================================
; CONFIRM MEDICINE 3
;========================================================

Confirm_Medicine3:

    ;----------------------------------------------------
    ; Exactly 4 digits
    ;----------------------------------------------------

    movf    digit_count,W
    xorlw   4

    btfss   STATUS,2
    goto    Invalid_Medicine3


    ;----------------------------------------------------
    ; Hour tens <= 2
    ;----------------------------------------------------

    movf    hour_tens,W
    sublw   '2'

    btfss   STATUS,0
    goto    Invalid_Medicine3


    ;----------------------------------------------------
    ; If hour tens = 2,
    ; hour ones <= 3
    ;----------------------------------------------------

    movf    hour_tens,W
    xorlw   '2'

    btfss   STATUS,2
    goto    Med3_Hours_Valid


    movf    hour_ones,W
    sublw   '3'

    btfss   STATUS,0
    goto    Invalid_Medicine3


Med3_Hours_Valid:

    ;----------------------------------------------------
    ; Minute tens <= 5
    ;----------------------------------------------------

    movf    min_tens,W
    sublw   '5'

    btfss   STATUS,0
    goto    Invalid_Medicine3


;========================================================
; SAVE MEDICINE 3
;========================================================

Valid_Medicine3:

    ;----------------------------------------------------
    ; Hour tens * 10
    ;----------------------------------------------------

    movf    hour_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med3_hour

    ; med3_hour = digit * 2
    movf    med3_hour,W
    addwf   med3_hour,F

    ; med3_hour = digit * 4
    movf    med3_hour,W
    addwf   med3_hour,F

    ; med3_hour = digit * 8
    movf    med3_hour,W
    addwf   med3_hour,F

    ; med3_hour = digit * 9
    movf    calc_temp,W
    addwf   med3_hour,F

    ; med3_hour = digit * 10
    movf    calc_temp,W
    addwf   med3_hour,F


    ; Add hour ones

    movf    hour_ones,W
    addlw   -'0'
    addwf   med3_hour,F


    ;----------------------------------------------------
    ; Minute tens * 10
    ;----------------------------------------------------

    movf    min_tens,W
    addlw   -'0'
    movwf   calc_temp

    movf    calc_temp,W
    movwf   med3_minute

    ; med3_minute = digit * 2
    movf    med3_minute,W
    addwf   med3_minute,F

    ; med3_minute = digit * 4
    movf    med3_minute,W
    addwf   med3_minute,F

    ; med3_minute = digit * 8
    movf    med3_minute,W
    addwf   med3_minute,F

    ; med3_minute = digit * 9
    movf    calc_temp,W
    addwf   med3_minute,F

    ; med3_minute = digit * 10
    movf    calc_temp,W
    addwf   med3_minute,F


    ; Add minute ones

    movf    min_ones,W
    addlw   -'0'
    addwf   med3_minute,F


    ;----------------------------------------------------
    ; MED 3 SET
    ;----------------------------------------------------

    movlw   0x01
    call    LCD_Command

    call    Delay_Long

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '3'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   'S'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    call    Delay_Invalid


    ;----------------------------------------------------
    ; Start Timer0 and enter normal mode
    ;----------------------------------------------------

    call    Timer0_Init
    goto    Normal_Mode


;========================================================
; TIMER0 INITIALIZATION
;========================================================

Timer0_Init:

    BANKSEL OPTION_REG 

    ; Internal clock = Fosc/4
    ; Prescaler assigned to Timer0
    ; Prescaler = 1:32
    ; Keep PORTB weak pull-ups enabled
    movlw   0x04
    movwf   OPTION_REG

    BANKSEL TMR0 
    clrf    TMR0

    BANKSEL timer_count
    clrf    timer_count
    clrf    minute_tick

    BANKSEL INTCON
    bcf     INTCON,2          ; Clear T0IF
    bsf     INTCON,5          ; Enable Timer0 interrupt (T0IE)
    bsf     INTCON,7          ; Enable global interrupts (GIE)

    return


;========================================================
; TIMER0 INTERRUPT SERVICE ROUTINE
;========================================================

Timer0_ISR:

    ;----------------------------------------------------
    ; Save CPU context
    ;----------------------------------------------------
    movwf   w_temp
    swapf   STATUS,W
    movwf   status_temp
    movf    PCLATH,W ; save page bits (which 2K flash block we were in)
    movwf   pclath_temp

    ;----------------------------------------------------
    ; Handle Timer0 overflow
    
    ; Timer0 overflows about every 8 ms. Each overflow is ONE interrupt.

    ; overflow 1   ? timer_count = 1   ? not 122 ? exit ? main again
    ; overflow 2   ? timer_count = 2   ? not 122 ? exit ? main again
    ; ...
    ; overflow 122 ? timer_count = 122 ? add 1 simulated minute ? exit
    ;----------------------------------------------------
    BANKSEL INTCON
    btfss   INTCON,2          ; T0IF set?
    goto    Timer0_ISR_Exit

    bcf     INTCON,2          ; Clear T0IF, the ISR never stops without this 

    BANKSEL timer_count
    incf    timer_count,F

    ; 122 overflows ~= 1 simulated second/minute
    movf    timer_count,W
    xorlw   122
    btfss   STATUS,2 ; Z = 1 (yes 122) -> skip
    goto    Timer0_ISR_Exit

    ; One simulated minute elapsed
    clrf    timer_count
    movlw   1
    movwf   minute_tick

    ; Increment software minute
    incf    minute,F
    movf    minute,W
    xorlw   60
    btfss   STATUS,2
    goto    Timer0_ISR_Exit

    ; Minute rolled over
    clrf    minute ; 08:60 -> 09:00
    incf    hour,F
    movf    hour,W
    xorlw   24 ; hour reached 24?
    btfss   STATUS,2
    goto    Timer0_ISR_Exit ; still 0..23 -> exit

    ; Day rolled over: 23:59 -> 00:00
    clrf    hour

    ; New day: the same three reminders can fire again
    clrf    med1_served
    clrf    med2_served
    clrf    med3_served

Timer0_ISR_Exit:

    ;----------------------------------------------------
    ; Restore CPU context
    ;----------------------------------------------------
    movf    pclath_temp,W
    movwf   PCLATH
    swapf   status_temp,W
    movwf   STATUS
    swapf   w_temp,F
    swapf   w_temp,W
    retfie


;========================================================
; NORMAL MODE
;========================================================

Normal_Mode:

    ; ACK is ignored here. We only read RC0 in Reminder_Mode.

Normal_Mode_Loop:

    ; Check whether current time matches a medicine reminder.
    call    Check_Reminder

    ; If a reminder is active, handle the alert.
    BANKSEL reminder_active
    movf    reminder_active,W
    btfss   STATUS,2
    goto    Reminder_Mode

    ; Normal display: find and show next reminder.
    call    Find_Next_Medicine
    call    Display_Current_Time

Normal_Mode_Wait:

    BANKSEL minute_tick
    movf    minute_tick,W
    btfsc   STATUS,2
    goto    Normal_Mode_Wait

    ; One simulated minute has passed.
    clrf    minute_tick
    goto    Normal_Mode_Loop


;========================================================
; CHECK REMINDER
;========================================================

Check_Reminder:

    ; Check Medicine 1 first. This also gives lower medicine
    ; number priority if two reminders have the same time.

    movf    med1_served,W ; 1 = already Taken or Missed today
    btfss   STATUS,2 
    goto    Check_Med2_Reminder     ; already Taken/Missed today

    ; Due if time == now, or a little late (same hour / next hour).
    ; 00:04 at 23:58 is NEXT day (hour jumped a lot), so do not fire now.
    movf    hour,W
    subwf   med1_hour,W             ; W = med1_hour - hour
    
    btfss   STATUS,0 ; C = 1 (med_hour >= now) -> skip
    goto    Med1_Hour_Past          ; C = 0 (med hour < now)

    btfss   STATUS,2  ; Z = 1 (same hour) -> skip, check minutes
    goto    Check_Med2_Reminder     ; med hour is still in the future

    ; Same hour, W = med1_minute - minute
    movf    minute,W
    subwf   med1_minute,W
    btfss   STATUS,0
    goto    Fire_Med1               ; same hour, minute already passed

    btfss   STATUS,2  ; Z = 1 (exact hour and minute) -> skip
    goto    Check_Med2_Reminder

    goto    Fire_Med1

; Med hour < clock hour:
;   09:10 vs Med 08:05 ? really late today (hour-med = 1) -> alert on
;   23:58 vs Med 00:04 ? that time is tomorrow (23-0 = 23) -> alert off
Med1_Hour_Past:
    movf    med1_hour,W
    subwf   hour,W                  ; hour - med_hour
    xorlw   1 ; alert on only if we are exactly 1 hour late.
    btfss   STATUS,2
    goto    Check_Med2_Reminder     ; more than 1 hour: wait

Fire_Med1:
    movlw   1
    movwf   reminder_med
    goto    Start_New_Alert

Check_Med2_Reminder:

    movf    med2_served,W
    btfss   STATUS,2
    goto    Check_Med3_Reminder

    movf    hour,W
    subwf   med2_hour,W
    btfss   STATUS,0
    goto    Med2_Hour_Past

    btfss   STATUS,2
    goto    Check_Med3_Reminder

    movf    minute,W
    subwf   med2_minute,W
    btfss   STATUS,0
    goto    Fire_Med2

    btfss   STATUS,2
    goto    Check_Med3_Reminder

    goto    Fire_Med2

Med2_Hour_Past:
    movf    med2_hour,W
    subwf   hour,W
    xorlw   1
    btfss   STATUS,2
    goto    Check_Med3_Reminder

Fire_Med2:
    movlw   2
    movwf   reminder_med
    goto    Start_New_Alert

Check_Med3_Reminder:

    movf    med3_served,W
    btfss   STATUS,2
    goto    No_Reminder

    movf    hour,W
    subwf   med3_hour,W
    btfss   STATUS,0
    goto    Med3_Hour_Past

    btfss   STATUS,2
    goto    No_Reminder

    movf    minute,W
    subwf   med3_minute,W
    btfss   STATUS,0
    goto    Fire_Med3

    btfss   STATUS,2
    goto    No_Reminder

    goto    Fire_Med3

Med3_Hour_Past:
    movf    med3_hour,W
    subwf   hour,W
    xorlw   1
    btfss   STATUS,2
    goto    No_Reminder

Fire_Med3:
    movlw   3
    movwf   reminder_med
    goto    Start_New_Alert

No_Reminder:
    return ; leave Check_Reminder. do not set reminder_active.


; Save THIS medicine's HH:MM (not the running clock), then start.
; So Med1/Med2 at 8:05 still queue if the clock is already 8:12.
Start_New_Alert:

    movf    reminder_med,W
    xorlw   1
    btfsc   STATUS,2
    goto    Save_Alert_Med1

    movf    reminder_med,W
    xorlw   2
    btfsc   STATUS,2
    goto    Save_Alert_Med2

    movf    med3_hour,W
    movwf   alert_hour
    movf    med3_minute,W
    movwf   alert_minute
    goto    Start_Alert_Common

Save_Alert_Med1:
    movf    med1_hour,W
    movwf   alert_hour
    movf    med1_minute,W
    movwf   alert_minute
    goto    Start_Alert_Common

Save_Alert_Med2:
    movf    med2_hour,W
    movwf   alert_hour
    movf    med2_minute,W
    movwf   alert_minute

Start_Alert_Common:
    movlw   1
    movwf   reminder_active
    clrf    blink_state
    clrf    miss_count
    return


;========================================================
; REMINDER MODE
;========================================================

Reminder_Mode:

    ; Display "Take Medicine n".
    call    Display_Reminder_Message

Reminder_Blink_Loop:

    ; Generate an audible tone on RC4.
    call    Buzzer_Tone

    ; Blink only the selected medicine LED.
    BANKSEL blink_state
    movf    blink_state,W
    btfss   STATUS,2
    goto    Reminder_LED_Off

Reminder_LED_On:

    BANKSEL PORTC
    bcf     PORTC,1
    bcf     PORTC,2
    bcf     PORTC,3

    BANKSEL reminder_med
    movf    reminder_med,W
    xorlw   1
    btfsc   STATUS,2
    bsf     PORTC,1

    movf    reminder_med,W
    xorlw   2
    btfsc   STATUS,2
    bsf     PORTC,2

    movf    reminder_med,W
    xorlw   3
    btfsc   STATUS,2
    bsf     PORTC,3

    goto    Reminder_Blink_Delay

Reminder_LED_Off:

    BANKSEL PORTC
    bcf     PORTC,1
    bcf     PORTC,2
    bcf     PORTC,3

Reminder_Blink_Delay:

    ; Short delay creates visible blinking.
    call    Delay_Long

    BANKSEL blink_state
    movf    blink_state,W
    btfsc   STATUS,2
    goto    Set_Blink_On

    clrf    blink_state
    goto    Reminder_Blink_Check

Set_Blink_On:
    movlw   1
    movwf   blink_state

Reminder_Blink_Check:

    ; ACK is read ONLY here, not in Normal_Mode.
    ; RC0 = 0 means the button is pressed (external 10k pull-up).
    BANKSEL PORTC
    btfsc   PORTC,0
    goto    Reminder_Check_Miss

    call    Delay_Debounce
    BANKSEL PORTC
    btfsc   PORTC,0
    goto    Reminder_Check_Miss     ; it was bounce, not a real press

    goto    Reminder_Taken


Reminder_Check_Miss:

    ; Same 1 s tick as the clock (minute_tick).
    ; 20 ticks = 20 simulated seconds (spec miss time).
    BANKSEL minute_tick
    movf    minute_tick,W
    btfsc   STATUS,2
    goto    Reminder_Blink_Loop

    clrf    minute_tick
    incf    miss_count,F

    movf    miss_count,W
    xorlw   20
    btfsc   STATUS,2
    goto    Reminder_Missed

    goto    Reminder_Blink_Loop


;========================================================
; ACK PRESSED  ->  Dose Taken
;========================================================

Reminder_Taken:

    call    Alert_Outputs_Off
    call    Wait_ACK_Release        ; so the next same-time alert is not auto-acked
    clrf    reminder_active
    call    Mark_Current_Served

    call    Display_Dose_Taken
    call    Delay_Welcome           ; about 2 seconds (spec)
    goto    After_Alert


;========================================================
; NO ACK FOR 20 s  ->  Dose Missed
;========================================================

Reminder_Missed:

    call    Alert_Outputs_Off
    clrf    reminder_active
    call    Mark_Current_Served

    call    Display_Dose_Missed
    call    Delay_Welcome           ; about 2 seconds (spec)
    goto    After_Alert


;========================================================
; After Taken/Missed: if another med has the same time,
; start it now (lower number was already served).
;========================================================

After_Alert:

    ; Clock already moved during Dose Taken (~2 s).
    ; Look for the next unserved med at alert_hour:alert_minute.
    call    Check_Queued_Reminder

    BANKSEL reminder_active
    movf    reminder_active,W
    btfss   STATUS,2
    goto    Reminder_Mode

    goto    Normal_Mode


;========================================================
; Same-time queue 
;
; After Dose Taken / Missed: is another med at the SAME HH:MM still waiting?
; Compare with alert_hour:alert_minute, NOT the running clock.
; Dose Taken takes ~2 s, so the clock may have already moved past that time.
; If we used hour/minute, the next same-time med would be skipped.
; Check Med1 then Med2 then Med3. Already served ? skip.
; Exact time match ? reminder_med = n, start that alert.
;========================================================

Check_Queued_Reminder:

    movf    med1_served,W
    btfss   STATUS,2
    goto    Queue_Check_Med2

    movf    alert_hour,W
    subwf   med1_hour,W
    btfss   STATUS,2
    goto    Queue_Check_Med2

    movf    alert_minute,W
    subwf   med1_minute,W
    btfss   STATUS,2
    goto    Queue_Check_Med2

    movlw   1
    movwf   reminder_med
    goto    Start_Queued_Alert

Queue_Check_Med2:

    movf    med2_served,W
    btfss   STATUS,2
    goto    Queue_Check_Med3

    movf    alert_hour,W
    subwf   med2_hour,W
    btfss   STATUS,2
    goto    Queue_Check_Med3

    movf    alert_minute,W
    subwf   med2_minute,W
    btfss   STATUS,2
    goto    Queue_Check_Med3

    movlw   2
    movwf   reminder_med
    goto    Start_Queued_Alert

Queue_Check_Med3:

    movf    med3_served,W
    btfss   STATUS,2
    return

    movf    alert_hour,W
    subwf   med3_hour,W
    btfss   STATUS,2
    return

    movf    alert_minute,W
    subwf   med3_minute,W
    btfss   STATUS,2
    return

    movlw   3
    movwf   reminder_med

Start_Queued_Alert:

    movlw   1
    movwf   reminder_active
    clrf    blink_state
    clrf    miss_count
    return


;========================================================
; Turn LEDs and buzzer OFF (do not clrf PORTC: RC0 is ACK)
;========================================================

Alert_Outputs_Off:

    BANKSEL PORTC
    bcf     PORTC,1
    bcf     PORTC,2
    bcf     PORTC,3
    bcf     PORTC,4
    return


;========================================================
; Wait until ACK is released, then debounce
;========================================================

Wait_ACK_Release:

    BANKSEL PORTC
    btfss   PORTC,0
    goto    Wait_ACK_Release

    call    Delay_Debounce
    return


;========================================================
; Mark this reminder as served today
;========================================================

Mark_Current_Served:

    movf    reminder_med,W
    xorlw   1
    btfsc   STATUS,2
    goto    Serve_Med1

    movf    reminder_med,W
    xorlw   2
    btfsc   STATUS,2
    goto    Serve_Med2

    movlw   1
    movwf   med3_served
    return

Serve_Med1:
    movlw   1
    movwf   med1_served
    return

Serve_Med2:
    movlw   1
    movwf   med2_served
    return


;========================================================
; BUZZER TONE
;========================================================

Buzzer_Tone:

    ; Toggle RC4 rapidly to generate an audible tone.
    ; The buzzer is connected between RC4 and GND.
    movlw   0x80
    movwf   delay3

Buzzer_Tone_Loop:
    BANKSEL PORTC
    bsf     PORTC,4
    call    Delay_Short
    bcf     PORTC,4
    call    Delay_Short

    decfsz  delay3,F
    goto    Buzzer_Tone_Loop

    return


;========================================================
; DISPLAY REMINDER MESSAGE
;========================================================

Display_Reminder_Message:

    call    LCD_Clear

    movlw   'T'
    call    LCD_Data
    movlw   'a'
    call    LCD_Data
    movlw   'k'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data
    movlw   'M'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'd'
    call    LCD_Data
    movlw   'i'
    call    LCD_Data
    movlw   'c'
    call    LCD_Data
    movlw   'i'
    call    LCD_Data
    movlw   'n'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data

    movf    reminder_med,W
    addlw   '0'
    call    LCD_Data

    return


;========================================================
; DISPLAY "Dose Taken"
;========================================================

Display_Dose_Taken:

    call    LCD_Clear

    movlw   'D'
    call    LCD_Data
    movlw   'o'
    call    LCD_Data
    movlw   's'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data
    movlw   'T'
    call    LCD_Data
    movlw   'a'
    call    LCD_Data
    movlw   'k'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'n'
    call    LCD_Data

    return


;========================================================
; DISPLAY "Dose Missed"
;========================================================

Display_Dose_Missed:

    call    LCD_Clear

    movlw   'D'
    call    LCD_Data
    movlw   'o'
    call    LCD_Data
    movlw   's'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data
    movlw   'M'
    call    LCD_Data
    movlw   'i'
    call    LCD_Data
    movlw   's'
    call    LCD_Data
    movlw   's'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'd'
    call    LCD_Data

    return


;========================================================
; DISPLAY CURRENT TIME
;========================================================

Display_Current_Time:

    call    LCD_Clear

    ;----------------------------------------------------
    ; First line = TIME HH:MM
    ;----------------------------------------------------

    movlw   'T'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    ; Display current hour
    movf    hour,W
    movwf   calc_temp
    call    Display_2_Digit

    movlw   ':'
    call    LCD_Data

    ; Display current minute
    movf    minute,W
    movwf   calc_temp
    call    Display_2_Digit

    ;----------------------------------------------------
    ; Second line = MED n HH:MM
    ;----------------------------------------------------

    movlw   0xC0
    call    LCD_Command

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movf    next_med,W
    addlw   '0'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movf    next_hour,W
    movwf   calc_temp
    call    Display_2_Digit

    movlw   ':'
    call    LCD_Data

    movf    next_minute,W
    movwf   calc_temp
    call    Display_2_Digit

    return


;========================================================
; FIND NEXT MEDICINE
;
; Selects the earliest reminder that is still due today.
; If all three reminders have already passed, selects the
; earliest reminder for the next day.
; For equal times, lower medicine number is selected.
;========================================================

Find_Next_Medicine:

    clrf    next_valid

    ;----------------------------------------------------
    ; Check Medicine 1
    ;----------------------------------------------------
    call    Check_Med1_Next

    ;----------------------------------------------------
    ; Check Medicine 2
    ;----------------------------------------------------
    call    Check_Med2_Next

    ;----------------------------------------------------
    ; Check Medicine 3
    ;----------------------------------------------------
    call    Check_Med3_Next

    ;----------------------------------------------------
    ; If no medicine remains today, select the earliest
    ; reminder among all three for the next day.
    ;----------------------------------------------------
    movf    next_valid,W
    btfss   STATUS,2
    goto    Find_Next_Done

    ; Start with Medicine 1
    movlw   1
    movwf   next_med

    movf    med1_hour,W
    movwf   next_hour

    movf    med1_minute,W
    movwf   next_minute

    call    Compare_Med2_With_Next
    call    Compare_Med3_With_Next

Find_Next_Done:
    return


;--------------------------------------------------------
; Check Medicine 1 against current time
;--------------------------------------------------------

Check_Med1_Next:

    movf    med1_served,W
    btfss   STATUS,2
    return                      ; already Taken/Missed today

    ; Candidate if Med1 hour > current hour
    movf    hour,W
    subwf   med1_hour,W
    btfss   STATUS,0
    return

    movf    med1_hour,W
    subwf   hour,W
    btfss   STATUS,2
    goto    Med1_Is_Candidate

    ; Same hour: candidate if Med1 minute >= current minute
    movf    minute,W
    subwf   med1_minute,W
    btfss   STATUS,0
    return

Med1_Is_Candidate:

    movf    next_valid,W
    btfsc   STATUS,2
    goto    Select_Med1

    ; Select Med1 if its hour is earlier than next_hour
    movf    med1_hour,W
    subwf   next_hour,W
    btfss   STATUS,0
    return

    movf    next_hour,W
    subwf   med1_hour,W
    btfss   STATUS,2
    goto    Select_Med1

    ; Same hour: select if Med1 minute is earlier
    movf    med1_minute,W
    subwf   next_minute,W
    btfss   STATUS,0
    return

    ; Equal time: keep the lower medicine number
    return

Select_Med1:
    movlw   1
    movwf   next_med
    movf    med1_hour,W
    movwf   next_hour
    movf    med1_minute,W
    movwf   next_minute
    movlw   1
    movwf   next_valid
    return


;--------------------------------------------------------
; Check Medicine 2 against current time
;--------------------------------------------------------

Check_Med2_Next:

    movf    med2_served,W
    btfss   STATUS,2
    return

    movf    hour,W
    subwf   med2_hour,W
    btfss   STATUS,0
    return

    movf    med2_hour,W
    subwf   hour,W
    btfss   STATUS,2
    goto    Med2_Is_Candidate

    movf    minute,W
    subwf   med2_minute,W
    btfss   STATUS,0
    return

Med2_Is_Candidate:

    movf    next_valid,W
    btfsc   STATUS,2
    goto    Select_Med2

    ; Select Med2 if its hour is earlier than next_hour
    movf    med2_hour,W
    subwf   next_hour,W
    btfss   STATUS,0
    return

    movf    next_hour,W
    subwf   med2_hour,W
    btfss   STATUS,2
    goto    Select_Med2

    ; Same hour: select Med2 if its minute is earlier
    movf    med2_minute,W
    subwf   next_minute,W
    btfss   STATUS,0
    return

    movf    next_minute,W
    subwf   med2_minute,W
    btfss   STATUS,2
    goto    Select_Med2

    ; Equal time: keep the lower medicine number
    return

Select_Med2:
    movlw   2
    movwf   next_med
    movf    med2_hour,W
    movwf   next_hour
    movf    med2_minute,W
    movwf   next_minute
    movlw   1
    movwf   next_valid
    return


;--------------------------------------------------------
; Check Medicine 3 against current time
;--------------------------------------------------------

Check_Med3_Next:

    movf    med3_served,W
    btfss   STATUS,2
    return

    movf    hour,W
    subwf   med3_hour,W
    btfss   STATUS,0
    return

    movf    med3_hour,W
    subwf   hour,W
    btfss   STATUS,2
    goto    Med3_Is_Candidate

    movf    minute,W
    subwf   med3_minute,W
    btfss   STATUS,0
    return

Med3_Is_Candidate:

    movf    next_valid,W
    btfsc   STATUS,2
    goto    Select_Med3

    ; Select Med3 if its hour is earlier than next_hour
    movf    med3_hour,W
    subwf   next_hour,W
    btfss   STATUS,0
    return

    movf    next_hour,W
    subwf   med3_hour,W
    btfss   STATUS,2
    goto    Select_Med3

    ; Same hour: select Med3 if its minute is earlier
    movf    med3_minute,W
    subwf   next_minute,W
    btfss   STATUS,0
    return

    movf    next_minute,W
    subwf   med3_minute,W
    btfss   STATUS,2
    goto    Select_Med3

    ; Equal time: keep the lower medicine number
    return

Select_Med3:
    movlw   3
    movwf   next_med
    movf    med3_hour,W
    movwf   next_hour
    movf    med3_minute,W
    movwf   next_minute
    movlw   1
    movwf   next_valid
    return


;--------------------------------------------------------
; Compare Medicine 2 with next medicine when all reminders
; have passed today.
;--------------------------------------------------------

Compare_Med2_With_Next:

    ; Keep next if Med2 hour is later (C=0: next_hour < med2_hour)
    movf    med2_hour,W
    subwf   next_hour,W
    btfss   STATUS,0
    return

    movf    next_hour,W
    subwf   med2_hour,W
    btfss   STATUS,2
    goto    Select_Next_Med2        ; hours differ -> Med2 is earlier

    ; Same hour: select Med2 only if its minute is earlier
    movf    med2_minute,W
    subwf   next_minute,W
    btfss   STATUS,0
    return

    movf    next_minute,W
    subwf   med2_minute,W
    btfss   STATUS,2
    goto    Select_Next_Med2

    return                          ; equal: keep lower number (Med1)

Select_Next_Med2:
    movlw   2
    movwf   next_med
    movf    med2_hour,W
    movwf   next_hour
    movf    med2_minute,W
    movwf   next_minute
    return


;--------------------------------------------------------
; Compare Medicine 3 with next medicine when all reminders
; have passed today.
;--------------------------------------------------------

Compare_Med3_With_Next:

    ; Keep next if Med3 hour is later
    movf    med3_hour,W
    subwf   next_hour,W
    btfss   STATUS,0
    return

    movf    next_hour,W
    subwf   med3_hour,W
    btfss   STATUS,2
    goto    Select_Next_Med3        ; hours differ -> Med3 is earlier

    ; Same hour: select Med3 only if its minute is earlier
    movf    med3_minute,W
    subwf   next_minute,W
    btfss   STATUS,0
    return

    movf    next_minute,W
    subwf   med3_minute,W
    btfss   STATUS,2
    goto    Select_Next_Med3

    return                          ; equal: keep lower number

Select_Next_Med3:
    movlw   3
    movwf   next_med
    movf    med3_hour,W
    movwf   next_hour
    movf    med3_minute,W
    movwf   next_minute
    return


;========================================================
; DISPLAY 2 DIGITS
; Input: calc_temp = binary value 0..59
    
; LCD needs characters. RAM has a number (e.g. 23).
; 23 / 10 = 2 remainder 3  ->  tens=2, ones=3.
; delay1 = tens. calc_temp = ones.
;========================================================

Display_2_Digit:

    clrf    delay1

Display_Tens_Loop:

    movlw   10
    subwf   calc_temp,F
    btfss   STATUS,0
    goto    Display_Tens_Done

    incf    delay1,F
    goto    Display_Tens_Loop

Display_Tens_Done:

    movlw   10
    addwf   calc_temp,F

    movf    delay1,W
    addlw   '0'
    call    LCD_Data

    movf    calc_temp,W
    addlw   '0'
    call    LCD_Data

    return


;========================================================
; INVALID MEDICINE 3
;========================================================

Invalid_Medicine3:

    call    LCD_Clear


    ; First line = INVALID

    movlw   'I'
    call    LCD_Data

    movlw   'N'
    call    LCD_Data

    movlw   'V'
    call    LCD_Data

    movlw   'A'
    call    LCD_Data

    movlw   'L'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data


    ; Second line = MED 3

    movlw   0xC0
    call    LCD_Command

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'D'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   '3'
    call    LCD_Data


    call    Delay_Invalid


    clrf    digit_count

    call    Display_Medicine3

    goto    Medicine3_Input_Loop


;========================================================
; DISPLAY WELCOME SCREEN
;========================================================

Display_Welcome:

    call    LCD_Clear

    movlw   'W'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'l'
    call    LCD_Data
    movlw   'c'
    call    LCD_Data
    movlw   'o'
    call    LCD_Data
    movlw   'm'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data
    movlw   't'
    call    LCD_Data
    movlw   'o'
    call    LCD_Data

    movlw   0xC0 ; line2, column0
    call    LCD_Command

    movlw   'M'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'd'
    call    LCD_Data
    movlw   ' '
    call    LCD_Data
    movlw   'R'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'm'
    call    LCD_Data
    movlw   'i'
    call    LCD_Data
    movlw   'n'
    call    LCD_Data
    movlw   'd'
    call    LCD_Data
    movlw   'e'
    call    LCD_Data
    movlw   'r'
    call    LCD_Data

    return


;========================================================
; WELCOME DELAY  (~2 seconds)
;
; Clock is 4 MHz, so 1 instruction takes 1 us.
; One small loop (decfsz + goto) takes about 3 us.
;
; One RAM byte can only count 255 times. That is too short
; for 2 seconds, so we use 3 counters inside each other:
;
;   delay1 = 255  steps
;   delay2 = repeat delay1, 255 times
;   delay3 = repeat all of that, 10 times
;
; time -> 10 * 255 * 255 * 3 us = ~2 seconds
;
;
;   Why count DOWN from 255, not UP from 0?
;   The PIC already has a ready instruction: decfsz.
;   decfsz = subtract 1, and if the result is 0, skip the loop.
;   We put 255, then decfsz each time, stop at 0.
;   And there is no single ready instruction that means
;   "add 1 and stop when you reach 255".
;   If we start at 0 and add 1, we must also keep asking
;   If we reached 255 and this is extra work.
;========================================================

Delay_Welcome:

    movlw   10              
    movwf   delay3

Welcome_Delay_Outer:

    movlw   0xFF
    movwf   delay2

Welcome_Delay_Middle:

    movlw   0xFF
    movwf   delay1

Welcome_Delay_Inner:

    decfsz  delay1,F
    goto    Welcome_Delay_Inner

    decfsz  delay2,F
    goto    Welcome_Delay_Middle

    decfsz  delay3,F
    goto    Welcome_Delay_Outer

    return


;========================================================
; DISPLAY SET TIME
;========================================================

Display_Set_Time:

    call    LCD_Clear

    ;----------------------------------------------------
    ; First line = SET TIME:
    ;----------------------------------------------------

    movlw   'S'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    movlw   ' '
    call    LCD_Data

    movlw   'T'
    call    LCD_Data

    movlw   'I'
    call    LCD_Data

    movlw   'M'
    call    LCD_Data

    movlw   'E'
    call    LCD_Data

    movlw   ':'
    call    LCD_Data


    ;----------------------------------------------------
    ; Second line = __:__
    ;----------------------------------------------------

    movlw   0xC0 ; Line2, Column0
    call    LCD_Command

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   ':'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    movlw   '_'
    call    LCD_Data

    return


;========================================================
; KEYPAD
;
;          C1   C2   C3
;
; R0       1    2    3
; R1       4    5    6
; R2       7    8    9
; R3       *    0    #
;========================================================

Keypad_GetKey:

    ;----------------------------------------------------
    ; ROW 0
    ;----------------------------------------------------

    BANKSEL PORTB 

    movlw   0x0E
    movwf   PORTB ; 0x0E: RB0=0 (scan this row). RB1-RB3=1 

    call    Keypad_CheckColumns ; Short delay 

    btfsc   PORTB,4 ; Test if RB4 = 0 -> pressed then the number is '1'
    goto    Row0_Col2 ; if RB4 = 1 -> not pressed then go test number '2' 

    movlw   '1'
    goto    Key_Found


Row0_Col2:

    btfsc   PORTB,5
    goto    Row0_Col3

    movlw   '2'
    goto    Key_Found


Row0_Col3:

    btfsc   PORTB,6
    goto    Scan_Row1 ; if Rb6=1 -> not pressed then go to scan The next row (Row1-RB1)

    movlw   '3'
    goto    Key_Found


    ;----------------------------------------------------
    ; ROW 1
    ;----------------------------------------------------

Scan_Row1:

    movlw   0x0D
    movwf   PORTB ; RB0, RB2, RB3 = high, RB1 = low (to test it) 

    call    Keypad_CheckColumns

    btfsc   PORTB,4
    goto    Row1_Col2

    movlw   '4'
    goto    Key_Found


Row1_Col2:

    btfsc   PORTB,5
    goto    Row1_Col3

    movlw   '5'
    goto    Key_Found


Row1_Col3:

    btfsc   PORTB,6
    goto    Scan_Row2

    movlw   '6'
    goto    Key_Found


    ;----------------------------------------------------
    ; ROW 2
    ;----------------------------------------------------

Scan_Row2:

    movlw   0x0B
    movwf   PORTB

    call    Keypad_CheckColumns

    btfsc   PORTB,4
    goto    Row2_Col2

    movlw   '7'
    goto    Key_Found


Row2_Col2:

    btfsc   PORTB,5
    goto    Row2_Col3

    movlw   '8'
    goto    Key_Found


Row2_Col3:

    btfsc   PORTB,6
    goto    Scan_Row3

    movlw   '9'
    goto    Key_Found


    ;----------------------------------------------------
    ; ROW 3
    ;----------------------------------------------------

Scan_Row3:

    movlw   0x07
    movwf   PORTB

    call    Keypad_CheckColumns

    btfsc   PORTB,4
    goto    Row3_Col2

    movlw   '*'
    goto    Key_Found


Row3_Col2:

    btfsc   PORTB,5
    goto    Row3_Col3

    movlw   '0'
    goto    Key_Found


Row3_Col3:

    btfsc   PORTB,6
    goto    No_Key

    movlw   '#'
    goto    Key_Found


;========================================================
; KEY FOUND
;========================================================

Key_Found:

    movwf   key_code ; The number found (pressed)  

    call    Delay_Debounce


;========================================================
; WAIT FOR KEY RELEASE
;========================================================

Wait_Key_Release:

    BANKSEL PORTB 

    movlw   0x00
    movwf   PORTB ; All outputs (rows) are become low, Note RB4?RB6 are inputs so they will not becomen low

    movf    PORTB,W ; copy the pins of PORTB in W 
    andlw   0x70 ; clear all w excluded RB4?RB6 (the inputs) 

    xorlw   0x70 ; all columns 1 â?? W=0, Z=1 (released). any column 0 â?? Wâ? 0, Z=0 (still pressed) 

    btfss   STATUS,2 ; Test if z = 1 then skip not pressed 
    goto    Wait_Key_Release ;still pressed 

    call    Delay_Debounce

    movf    key_code,W

    return


;========================================================
; NO KEY
;========================================================

No_Key:

    BANKSEL PORTB

    movlw   0x0F
    movwf   PORTB

    goto    Keypad_GetKey


;========================================================
; KEYPAD CHECK COLUMNS
;========================================================

Keypad_CheckColumns:

    call    Delay_Short

    return


;========================================================
; LCD INITIALIZATION
; Wake the LCD, set 4-bit / 2-line, turn it on, wipe screen.
;========================================================

LCD_Init:

    call    Delay_Long          ; LCD just got 5 V. Wait ~24 ms

    BANKSEL PORTD               

    bcf     PORTD,1             ; RS = 0 (COMMAND)
    bcf     PORTD,2             ; E  = 0 (no pulse yet)


    movlw   0x03                ; first reset nibble. Datasheet: do it 3 times
    call    LCD_Nibble          

    call    Delay_Long          ; Wait so the LCD can finish this step


    movlw   0x03                ; Second reset nibble 
    call    LCD_Nibble

    call    Delay_Long


    movlw   0x03                ; Third reset nibble
    call    LCD_Nibble

    call    Delay_Long


    movlw   0x02                ; Now switch to 4-bit mode
    call    LCD_Nibble        

    call    Delay_Long


    movlw   0x28                ; 4-bit, 2 lines
    call    LCD_Command         ; Full byte = two nibbles 


    movlw   0x0C                ; Display ON, cursor OFF, no blink
    call    LCD_Command


    ; Entry mode 
    movlw   0x06                ; After each letter, move right
    call    LCD_Command


    ; clear display 
    movlw   0x01                ; Wipe the screen, cursor to line 1
    call    LCD_Command

    call    Delay_Long          ; Clear is slow. Extra wait ~24 ms.

    return                      ; LCD is ready. main can print Welcome.


;========================================================
; LCD COMMAND
;========================================================

LCD_Command:

    movwf   lcd_byte

    BANKSEL PORTD

    bcf     PORTD,1 ; RS = 0 -> this is a COMMAND


    ; High nibble
    
    swapf   lcd_byte,W
    andlw   0x0F
    call    LCD_Nibble


    ; Low nibble

    movf    lcd_byte,W
    andlw   0x0F
    call    LCD_Nibble


    call    Delay_Short ; Almost 0.8 ms so the LCD can finish this command
    return


;========================================================
; LCD DATA
;========================================================

LCD_Data:

    movwf   lcd_byte

    BANKSEL PORTD

    bsf     PORTD,1 ;RS = 1 -> this is DATA


    ; High nibble

    swapf   lcd_byte,W
    andlw   0x0F
    call    LCD_Nibble


    ; Low nibble

    movf    lcd_byte,W
    andlw   0x0F
    call    LCD_Nibble


    call    Delay_Short

    bcf     PORTD,1 ; RS back to 0 (idle = command mode)

    return


;========================================================
; LCD NIBBLE
; Send only 4 bits on RD4-RD7, then pulse E.
; RS was already set by LCD_Command (0) or LCD_Data (1).
;========================================================

LCD_Nibble:

    andlw   0x0F                ; keep only the low 4 bits of W
    movwf   lcd_nibble         

    BANKSEL PORTD              


    movf    PORTD,W             ; Read current pins (RS, E, old data)
    andlw   0x0F                ; Keep RD0-RD3 (RS and E). Clear D4-D7
    movwf   PORTD               ; Write back. Data bits are 0, RS/E same


    swapf   lcd_nibble,W        ; 0x03 -> 0x30 so bits sit in the HIGH half
    andlw   0xF0                ; Keep only D4-D7 in W
    iorwf   PORTD,F             ; OR onto PORTD: set data, do not touch RS/E


    bsf     PORTD,2             ; E = 1 

    nop                         ; Keep E high a few us
    nop
    nop

    bcf     PORTD,2             ; E = 0  (LCD copies D4-D7 now)

    return                    


;========================================================
; LCD CLEAR
;========================================================

LCD_Clear:

    movlw   0x01 ; Datasheet: 0x01 = clear
    call    LCD_Command

    call    Delay_Long

    return


;========================================================
; SHORT DELAY
;========================================================

Delay_Short:

    movlw   0xFF ; count = 255
    movwf   delay1 


Delay_Short_Loop:

    decfsz  delay1,F
    goto    Delay_Short_Loop

    return ; About 255 * 3 us = 0.8 ms


;========================================================
; DEBOUNCE DELAY (wait till the key sattles)
;========================================================

Delay_Debounce:

    movlw   0x18 ; Outer count = 24
    movwf   delay2


Debounce_Loop:

    movlw   0xFF ; Innter count = 255 
    movwf   delay1


Debounce_Inner:

    decfsz  delay1,F
    goto    Debounce_Inner


    decfsz  delay2,F
    goto    Debounce_Loop

    return ; About 24 * 255 * 3 us = 18 ms


;========================================================
; LONG DELAY
;========================================================

Delay_Long:

    movlw   0x20            ; outer count = 32
    movwf   delay2


Delay_Long_1:

    movlw   0xFF            ; inner count = 255
    movwf   delay1


Delay_Long_2:

    decfsz  delay1,F
    goto    Delay_Long_2


    decfsz  delay2,F
    goto    Delay_Long_1

    return ; About 32 * 255 * 3 us = 24 ms


;========================================================
; INVALID / MESSAGE DELAY
;========================================================

Delay_Invalid:

    movlw   0x05 ; Outer count = 5
    movwf   delay3


Delay_Invalid_Outer:

    movlw   0xFF ; Middle count = 255
    movwf   delay2


Delay_Invalid_Middle:

    movlw   0xFF ; Inner count = 255
    movwf   delay1


Delay_Invalid_Inner:

    decfsz  delay1,F
    goto    Delay_Invalid_Inner


    decfsz  delay2,F
    goto    Delay_Invalid_Middle


    decfsz  delay3,F
    goto    Delay_Invalid_Outer

    return ; About 10 * 255 * 255 us= 1 second


;========================================================
; END
;========================================================

END
    