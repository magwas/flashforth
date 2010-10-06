;**********************************************************************
;                                                                     *
;    Filename:      FlashForth.asm                                    *
;    Date:          5.10.2010                                         *
;    File Version:  0.0                                               *
;    Copyright:     Mikael Nordman                                    *
;    Author:        Mikael Nordman                                    *
;                                                                     * 
;**********************************************************************
; FlashForth is a standalone Forth system for microcontrollers that
; can flash their own flash memory.
;
; Copyright (C) 2010  Mikael Nordman
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License version 3 as 
; published by the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;
; Modified versions of FlashForth must be clearly marked as such, 
; in the name of this file, and in the identification
; displayed when FlashForth starts.
;**********************************************************************


.include "m128def.inc"
; Macros

  .def zerol = r2
  .def zeroh = r3
  .def upl = r4
  .def uph = r5

  .def al  = r6
  .def ah  = r7
  .def bl  = r8
  .def bh  = r9

  .def ibase =r12
  .def ibasel=r12
  .def ibaseh=r13
  .def iaddr =r14
  .def iaddrl=r14
  .def iaddrh=r15

  .def t0 = r16
  .def t1 = r17
  .def t2 = r18
  .def t3 = r19

  .def t6 = r20
  .def t7 = r21

  .def flags0 = r22
  .def flags1 = r23
  .def tos  = r24
  .def tosl = r24  ; ParameterStackLow
  .def tosh = r25  ; ParameterStackHi
;  .def spl = r28  ; StackPointer Ylo
;  .def sph = r29  ; StackPointer Yhi
   

.macro poptos 
    ld tosl, Y+
    ld tosh, Y+
.endmacro

.macro pushtos
    st -Y, tosh
    st -Y, tosl
.endmacro

.macro in_
.if (@1 < $40)
  in @0,@1
.else
  lds @0,@1
.endif
.endmacro

.macro out_
.if (@0 < $40)
  out @0,@1
.else
  sts @0,@1
.endif
.endmacro

.macro sbi_
.if (@0 < $40)
  sbi @0,@1
.else
  in_ @2,@0
  ori @2,exp2(@1)
  out_ @0,@2
.endif
.endmacro

.macro cbi_
.if (@0 < $40)
  cbi @0,@1
.else
  in_ @2,@0
  andi @2,~(exp2(@1))
  out_ @0,@2
.endif
.endmacro


;..............................................................................
;Program Specific Constants (literals used in code)
;..............................................................................
; Flash page size
.equ PAGESIZEB=PAGESIZE*2    ; Page size in bytes 
.equ flashPageMask=0x00      ; One byte, no mask needed on 8 bit processor


; Forth word header flags
.equ NFA= 0x80      ; Name field mask
.equ IMMED= 0x40    ; Immediate mask
.equ INLINE= 0x20   ; Inline mask
.equ COMPILE= 0x10  ; Compile only mask
.equ NFL= 0xf       ; Name field length mask

; flags0
.equ iCR=     7     ; ACCEPT has found CR
.equ noclear= 6     ; dont clear optimisation flags 
.equ idup=    5     ; Use dupzeroequal instead of zeroequal
.equ izeroeq= 4     ; Use bnz instead of bz if zeroequal
.equ istream= 3
.equ idoxoff= 2
.equ ixoff=   1
.equ idirty=  0


; Task flags
.equ running= 0

;;; For Flow Control
.equ XON=   0x11
.equ XOFF=  0x13

;;; Memory mapping prefixes
.equ PRAM    = 0x0000  ; 4 Kbytes of ram
.equ PFLASH  = 0x1000  ; 56 Kbytes of flash + 4 Kbytes hidden boot flash
.equ PEEPROM = 0xf000  ; 4 Kbytes of eeprom

;;; Sizes of the serial RX and TX character queues
.equ rbuf_size= 64
.equ tbuf_size= 64

;;; USER AREA for the OPERATOR task
.equ uaddsize=     0          ; No additional user variables 
.equ ursize=       72         ; 36 cells return stack size ( 2 cells per rcall )
.equ ussize=       72         ; 36 cells parameter stack
.equ utibsize=     72         ; 72 character Terminal Input buffer

;;; User variables and area
.equ us0=          - 30         ; Start of parameter stack
.equ ur0=          - 28         ; Start of return stack
.equ uemit=        - 26         ; User EMIT vector
.equ uemitq=       - 24         ; User EMIT? vector
.equ ukey=         - 22         ; User KEY vector
.equ ukeyq=        - 20         ; User KEY? vector
.equ ulink=        - 18         ; Task link
.equ ubase=        - 16         ; Number Base
.equ utib=         - 14         ; TIB address
.equ utask=        - 12         ; Task area pointer
.equ ursave=       - 10         ; Saved return stack pointer
.equ ussave=       - 8          ; Saved parameter stack pointer
.equ usource=      - 6          ; Two cells
.equ utoin=        - 2          ; Input stream
.equ uhp=            0          ; Hold pointer
.equ urbuf=        -us0 + 2               ; return stack
.equ usbuf=        ustart-us0+ursize + 2        ; Parameter stack
.equ usbuf0=       usbuf - 2
.equ utibbuf=      ustart-us0+ursize+ussize + 2 ; Terminal Input buffer

;;;  Initial USER area pointer (operator)
.equ u0=           ustart-us0
.equ uareasize=    -us0+ursize+ussize+utibsize + 2

;;; Start of free ram
.equ dpdata=       ustart-us0+ursize+ussize+utibsize + 2

;;; Variables in EEPROM
.equ eeprom=       PEEPROM
.equ dp_start=     eeprom + 0x0000 ; TURNKEY
.equ dp_flash=     eeprom + 0x0002 ; FLASH dictionary pointer
.equ dp_eeprom=    eeprom + 0x0004 ; EEPROM dictionary pointer
.equ dp_ram=       eeprom + 0x0006 ; RAM dictionary pointer
.equ latest=       eeprom + 0x0008 ; Pointer to latest dictionary word
.equ prompt=       eeprom + 0x000a ; Deferred prompt
.equ ehere=        eeprom + 0x000c



;****************************************************
.dseg
ibuf:       .byte PAGESIZEB
txqueue:
tbuf_len:   .byte 2
tbuf_wr:    .byte 2
tbuf_rd:    .byte 2
tbuf_lv:    .byte 2
tbuf:       .byte tbuf_size

rxqueue:
rbuf_len:   .byte 2
rbuf_wr:    .byte 2
rbuf_rd:    .byte 2
rbuf_lv:    .byte 2
rbuf:       .byte rbuf_size

iflags:     .byte 2
Preg:       .byte 2
ms_count:   .byte 2
intcon1dbg: .byte 2
upcurrdbg:  .byte 2
rpdbg:      .byte 2
spdbg:      .byte 2
dpSTART:    .byte 2
dpFLASH:    .byte 2 ; DP's and LATEST in RAM
dpEEPROM:   .byte 2
dpRAM:      .byte 2
dpLATEST:   .byte 2
sect:       .byte 2 ; Current data section 0=flash, 1=eeprom, 2=ram
state:      .byte 2 ; Compilation state
upcurr:     .byte 2 ; Current USER area pointer
ustart:     .byte uareasize ; The operator user area

.cseg
.org 0
RESET_:     .dw  WARM
INT0_:      .dw  RESET_FF
INT1_:      .dw  RESET_FF
INT2_:      .dw  RESET_FF
INT3_:      .dw  RESET_FF
INT4_:      .dw  RESET_FF
INT5_:      .dw  RESET_FF
INT6_:      .dw  RESET_FF
INT7_:      .dw  RESET_FF
TIMER2COMP_: .dw RESET_FF
TIMER2OVF_:  .dw RESET_FF
TIMER1CAPT_: .dw RESET_FF
TIMER1COMPA_: .dw RESET_FF
TIMER1COMPB_: .dw RESET_FF
TIMER1OVF_:   .dw RESET_FF
TIMER0COMP_:  .dw RESET_FF
SPISTC_:      .dw RESET_FF
USART0RX_:    .dw RESET_FF
USART0UDRE_:  .dw RESET_FF
USART0TX_:    .dw RESET_FF
ADC_:         .dw RESET_FF
EEREADY_:     .dw RESET_FF
ANALOGCOMP_:  .dw RESET_FF
TIMER1COMPC_: .dw RESET_FF
TIMER3CAPT_:  .dw RESET_FF
TIMER3COMPA_: .dw RESET_FF
TIMER3COMPB_: .dw RESET_FF
TIMER3COMPC_: .dw RESET_FF
TIMER3OVF_:   .dw RESET_FF
USART1RX_:    .dw RESET_FF
USART1UDRE_:  .dw RESET_FF
USART1TX_:    .dw RESET_FF
TWI_:         .dw RESET_FF
SPMREADY_:    .dw RESET_FF


RESET_FF:
        
WARM_L:
WARM:
        nop

;;; *************************************
;;; COLD dictionary data
.equ coldlitsize= 6
;.section user_eedata
COLDLIT:
STARTV: .dw      0
DPC:    .dw      KERNEL_END+PFLASH
DPE:    .dw      ehere
DPD:    .dw      dpdata
LW:     .dw      lastword+PFLASH
STAT:   .dw      DOTSTATUS+PFLASH
;;; *************************************************
;;; WARM user area data
.equ warmlitsize= 13
WARMLIT:
        .dw      0x0002                ; CSE RAM
        .dw      0x0000                ; STATE
        .dw      u0                    ; UP
        .dw      usbuf0                ; S0
        .dw      urbuf                 ; R0
        .dw      TX1+PFLASH
        .dw      TX1Q+PFLASH
        .dw      RX1+PFLASH
        .dw      RX1Q+PFLASH
        .dw      u0                    ; ULINK
        .dw      0x0010                ; BASE
        .dw      utibbuf               ; TIB
        .dw      OPERATOR_AREA+PFLASH  ; TASK
;;; *************************************************

OPERATOR_AREA:

; *******************************************************************
; Coded for max 256 byte pagesize !
;if (ibaselo != (iaddrlo&(~(PAGESIZEB-1))))(ibasehi != iaddrhi)
;   if (idirty)
;       writebuffer_to_imem
;   endif
;   fillbuffer_from_imem
;   ibaselo = iaddrlo&(~(PAGESIZEB-1))
;   ibasehi = iaddrhi
;endif
IUPDATEBUF:
        mov     t0, iaddr
        andi    t0, ~(PAGESIZEB-1)
        cpse    t0, ibasel
        rjmp    IFILL_BUFFER
        cpse    iaddrh, ibaseh
        rjmp    IFILL_BUFFER
        ret

IFILL_BUFFER:
        rcall   IFLUSH
        mov     t0, iaddrl
        andi    t0, ~(PAGESIZEB-1)
        mov     ibasel, t0
        mov     ibaseh, iaddrh
IFILL_BUFFER_1:
        ldi     t0, PAGESIZEB&(PAGESIZEB-1)
        movw    zl, ibase
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IFILL_BUFFER_2:
        lpm     t1, z+
        st      x+, t1
        dec     t0
        brne    IFILL_BUFFER_2
        ret

IWRITE_BUFFER:

        lds     t3, (1<<PGERS) | (1<<SPMEN) ; Page erase
        rcall   DO_SPM
        ldi     t3, (1<<RWWSRE) | (1<<SPMEN); re-enable the RWW section
        rcall   DO_SPM

        ; transfer data from RAM to Flash page buffer
        ldi     t0, low(PAGESIZEB);init loop variable
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IWRITE_BUFFER1:
        ld      r0, x+
        ld      r1, x+
        ldi     t3, (1<<SPMEN)
        rcall   DO_SPM
        adiw    ZH:ZL, 2
        subi    t0, 2
        brne    IWRITE_BUFFER1

        ; execute page write
        subi    ZL, low(PAGESIZEB) ;restore pointer
        ldi     t3, (1<<PGWRT) | (1<<SPMEN)
        rcall   DO_SPM
        ; re-enable the RWW section
        ldi     t3, (1<<RWWSRE) | (1<<SPMEN)
        rcall   DO_SPM
#if 0
        ; read back and check, optional
        ldi     t0, low(PAGESIZEB);init loop variable
        subi    xl, low(PAGESIZEB) ;restore pointer
        sbci    xh, high(PAGESIZEB)
IWRITE_BUFFER2:
        lpm     r0, z+
        ld      r1, x+
        cpse    r0, r1
        jmp     VERIFY_ERROR     ; What to do here ?? reset ?
        subi    t0, 1
        brne    IWRITE_BUFFER2
#endif
        ; return to RWW section
        ; verify that RWW section is safe to read
IWRITE_BUFFER3:
        lds     t0, SPMCSR
        sbrs    t0, RWWSB ; If RWWSB is set, the RWW section is not ready yet
        ret
        ; re-enable the RWW section
        ldi     t3, (1<<RWWSRE) | (1<<SPMEN)
        rcall   DO_SPM
        rjmp    IWRITE_BUFFER3

DO_SPM:
        lds     t2, SPMCSR
        sbrc    t2, SPMEN
        rjmp    DO_SPM       ; Wait for previous write to complete
        in      t2, SREG
        cli
        sts     SPMCSR, t3
        spm
        out     SREG, t2
        ret
;*****************************************************************
IFLUSH:
        sbrc    flags1, idirty
        rjmp    IWRITE_BUFFER
        ret
TX1:
TX1Q:
RX1:
RX1Q:




ISTORE:
        movw    iaddr, tos
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, ~(PAGESIZEB-1)
        add     xh, t0
        st      x+, tosl
        st      x+, tosh
        poptos
        ret

        .dw     WARM_L+PFLASH
STORE_L:
        .db     NFA|1, "!"
STORE:
        cpi     tosh, 0x01
        brmi    STORE_RAM
        cpi     tosh, 0xe0
        brmi    ISTORE
        rjmp    ESTORE
STORE_RAM:
        movw    zl, tosl
        poptos
        std     Z+1, tosh
        std     Z+0, tosl
        poptos
        ret

ESTORE:
        sbic    eecr, eewe
        rjmp    ESTORE
        out     eearl, tosl
        out     eearh, tosh
        poptos
        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe

ESTORE1:
        sbic    eecr, eewe
        rjmp    ESTORE1

        in      tosl, eearl
        inc     tosl
        out     eearl, tosl

        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe

        poptos
        ret

;***********************************************************
IFETCH:
        movw    z, tos
        cpse    zh, ibaseh
        rjmp    IIFETCH
        mov     t0, zh
        andi    t0, ~(PAGESIZEB-1)
        breq    IIFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zh, (PAGESIZEB-1)
        add     xl, zh
        ld      tosl, x+
        ld      tosh, x+
IIFETCH:
        lpm     tosl, z+     ; Fetch from Flash directly
        lpm     tosh, z+
        ret
                
        .dw     STORE_L+PFLASH
FETCH_L:
        .db     NFA|1, "@"
FETCH:
        cpi     tosh, 0x01
        brmi    FETCH_RAM
        cpi     tosh, 0xe0
        brmi    IFETCH
        rjmp    EFETCH
FETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        ld      tosh, z+
        ret

EFETCH:
        sbic    eecr, eewe
        rjmp    EFETCH
        out     eearl, tosl
        out     eearh, tosh
        sbi     eecr, eere
        in      tosl, eedr
        in      tosh, eearl
        inc     tosh
        out     eearl, tosh
        sbi     eecr, eere
        in      tosh, eedr
        ret

ICFETCH:
        movw    z, tos
        cpse    zh, ibaseh
        rjmp    IICFETCH
        mov     t0, zh
        andi    t0, ~(PAGESIZEB-1)
        breq    IICFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zh, (PAGESIZEB-1)
        add     xl, zh
        ld      tosl, x+
        clr     tosh
        ret
IICFETCH:
        lpm     tosl, z+     ; Fetch from Flash directly
        clr     tosh
        ret
        .dw     FETCH_L+PFLASH
CFETCH_L:
        .db     NFA|2, "c@"
CFETCH:
        cpi     tosh, 0x01
        brmi    CFETCH_RAM
        cpi     tosh, 0xe0
        brmi    ICFETCH
        rjmp    ECFETCH
CFETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        clr     tosh
        ret
ECFETCH:
        sbic    eecr, eewe
        rjmp    ECFETCH
        out     eearl, tosl
        out     eearh, tosh
        sbi     eecr, eere
        in      tosl, eedr
        clr     tosh
        ret

ICSTORE:
        movw    iaddr, tos
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, ~(PAGESIZEB-1)
        add     xh, t0
        st      x+, tosl
        poptos
        ret

        .dw     CFETCH_L+PFLASH
CSTORE_L:
        .db     NFA|2, "c!"
CSTORE:
        cpi     tosh, 0x01
        brmi    CSTORE_RAM
        cpi     tosh, 0xe0
        brmi    ICSTORE
        rjmp    ECSTORE
CSTORE_RAM:
        movw zl, tosl
        poptos
        std Z+0, tosl
        poptos
        ret

ECSTORE:
        sbic    eecr, eewe
        rjmp    ECSTORE
        out     eearl, tosl
        out     eearh, tosh
        poptos
        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe
        poptos
        ret


ICOMMA:
        ret

; LITERAL  x --           compile literal x as native code
        .dw     0
LITERAL_L:
        .db     NFA|IMMED|7,"literal"
LITERAL:
        pushtos
        ldi     tosl, 0x9a      ; savettos
        ldi     tosh, 0x93      ; savettos
        rcall   ICOMMA
        ldi     tosl, 0x8a      ; savettos
        ldi     tosh, 0x93      ; savettos
        rcall   ICOMMA
        poptos
        rcall   DUP
        mov     tosh, tosl
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x80
        rcall   ICOMMA
        poptos
        mov     tosl, tosh
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x90
        jmp     ICOMMA

#if 0
LITERALruntime:
        st      -Y, tosh    ; 0x939a
        st      -Y, tosl    ; 0x938a
        ldi     tosl, 0x12  ; 0xe1r2 r=8 (r24)
        ldi     tosh, 0x34  ; 0xe3r4 r=9 (r25)
#endif

DOLIT_L:
        .db     NFA|3, "lit"
DOLIT:
        pop     zl
        pop     zh
        pushtos
        lpm     tosl, z+
        lpm     tosh, z+
        ijmp    ; (z)

DOCREATE_L:
        .db     NFA|3, "(c)"
DOCREATE:
        pop     zl
        pop     zh
        pushtos
        lpm     tosl, z+
        lpm     tosh, z+
        ret
      
DODOES_L:
        .db     NFA|3, "(d)"
DODOES:
        pop     xl
        pop     xh
        pop     zl
        pop     zh
        pushtos
        lpm     tosl, z+
        lpm     tosh, z+
        movw    z, x
        ijmp    ; (z)

        .dw     CSTORE_L+PFLASH
DUP_L:
        .db     NFA|3, "dup"
DUP:
        pushtos
        ret

ABS_L:
        .dw     ABS_L+PFLASH
PLUS_L:
        .db     NFA|1, "+"

PLUS:
        ld      t0, Y+        
        ld      t1, Y+
        add     tosl, t0
        adc     tosh, t1
        ret

; m+  ( d n -- d1 )
        .dw     PLUS_L+PFLASH
MPLUS_L:
        .db     NFA|2, "m+",0
MPLUS:
        ld      t2, Y+
        ld      t3, Y+
        ld      t0, Y+
        ld      t1, Y+
        add     t0, tosl
        adc     t1, tosh
        clr     tosl
        adc     tosl, t2
        clr     tosh
        adc     tosh, t3
        st      -Y, t1
        st      -Y, t0
        ret

        .dw     MPLUS_L+PFLASH
MINUS_L:
        .db     NFA|1, "-"
MINUS:
        ld      t0, Y+
        ld      t1, Y+
        sub     t0, tosl
        sbc     t1, tosh
        movw    tosl, t0
        ret


        .dw     ONEMINUS_L+PFLASH
AND_L:
        .db     NFA|3, "and"
AND_:
        ld      t0, Y+
        ld      t1, Y+
        and     tosl, t0
        and     tosh, t1
        ret

        .dw     AND_L+PFLASH
OR_L:
        .db     NFA|2, "or"
OR_:
        ld      t0, Y+
        ld      t1, Y+
        or      tosl, t0
        or      tosh, t1
        ret

        .dw     OR_L+PFLASH
XOR_L:
        .db     NFA|3, "xor"
XOR_:
        ld      t0, Y+
        ld      t1, Y+
        eor     tosl, t0
        eor     tosh, t1
        ret

        .dw     XOR_L+PFLASH
INVERT_L:
        .db     NFA|6, "invert"
INVERT:
        com     tosl
        com     tosh
        ret

        .dw     INVERT_L+PFLASH
NEGATE_L:
        .db     NFA|6, "negate"
NEGATE:
        rcall   INVERT
        jmp     ONEPLUS

        .dw     NEGATE_L+PFLASH
ONEPLUS_L:
        .db     NFA|INLINE|2, "1+"
ONEPLUS:
        adiw    tosl, 1
        ret

        .dw     ONEPLUS_L+PFLASH
ONEMINUS_L:
        .db     NFA|INLINE|2, "1-"
ONEMINUS:
        sbiw    tosl, 1
        ret

        .dw     ONEMINUS_L+PFLASH
TWOPLUS_L:
        .db     NFA|INLINE|2, "2+"
TWOPLUS:
        adiw    tosl, 2
        ret

        .dw     TWOPLUS_L+PFLASH
TWOMINUS_L:
        .db     NFA|INLINE|2, "2-"
TWOMINUS:
        sbiw    tosl, 2
        ret

        .dw     TWOMINUS_L+PFLASH
TOBODY_L:
        .db     NFA|INLINE|5, ">body"
TOBODY:
        adiw    tosl, 4
        ret

        .dw     TOBODY_L+PFLASH
TWOSTAR_L:
        .db     NFA|INLINE|2, "2*"
TWOSTAR:
        lsl     tosl
        rol     tosh
        ret

        .dw     TWOSTAR_L+PFLASH
TWOSLASH_L:
        .db     NFA|INLINE|2, "2/"
TWOSLASH:
        asr     tosh
        ror     tosl
        ret

        .dw     TWOSLASH_L+PFLASH
ZEROEQUAL_L:
        .db     NFA|COMPILE|2, "0="
ZEROEQUAL:      
        or      tosh, tosl
        brne    ZEROEQUAL_1
TRUE_F:
        ser     tosh
        ser     tosl
ZEROEQUAL_1:
        ret

        .dw     ZEROEQUAL_L+PFLASH
ZEROLESS_L:
        .db     NFA, COMPILE|2, "0<"
ZEROLESS:
        tst     tosh
        brmi    TRUE_F
        clr     tosh
        clr     tosl
        ret
        

DOTSTATUS:
lastword:
KERNEL_END:
