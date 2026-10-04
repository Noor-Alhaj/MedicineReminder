;========================================================
; xc8_link_stubs.s
;
; Extra file for MPLAB X + XC8 only.
; It does NOT change the partner program.
; XC8's linker script expects these empty sections
; when the project is assembly-only.
;========================================================

#include <xc.inc>

PSECT reset_vec,class=CODE,delta=2
PSECT intentry,class=CODE,delta=2
PSECT sivt,class=CODE,delta=2
PSECT init,class=CODE,delta=2
PSECT end_init,class=CODE,delta=2
PSECT cinit,class=CODE,delta=2
PSECT powerup,class=CODE,delta=2
PSECT functab,class=CODE,delta=2
PSECT eeprom_data,class=EEDATA,space=3,delta=2,noexec
