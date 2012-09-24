;**********************************************************************
;                                                                     *
;    Filename:      FlashForth.asm                                    *
;    Date:          15.01.2012                                        *
;    File Version:  Atmega                                            *
;    Copyright:     Mikael Nordman                                    *
;    Author:        Mikael Nordman                                    *
;                                                                     * 
;**********************************************************************
; FlashForth is a standalone Forth system for microcontrollers that
; can flash their own flash memory.
;
; Copyright (C) 2011  Mikael Nordman

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

; Include the FlashForth configuration file
.include "config.inc"


; Register definitions
  .def upl = r2         ; not in interrupt 
  .def uph = r3         ; not in interrupt
  .def zero = r5        ; read only zero
  .def r_one = r6       ; read only one
  .def r_two = r7       ; read only two
  .def r_four = r8      ; read only four
  .def wflags  = r9     ; not in interrupt

  .def ibasel=r10       ; Not in interrupt
  .def ibaseh=r11       ; Not in interrupt
  .def iaddrl=r12       ; Not in interrupt
  .def iaddrh=r13       ; Not in interrupt
  .def t8 = r14         ; Not in interrupt
  .def t9 = r15         ; Not in interrupt
  .def t0 = r16
  .def t1 = r17
  .def t2 = r0          ; Not in interrupt
  .def t3 = r1          ; Not in interrupt

  .def pl = r20
  .def ph = r21

  .def FLAGS1 = r22     ; Not in interrupt
  .def FLAGS2 = r23     ; Not in interrupt
  .def tosl = r24
  .def tosh = r25
;  xl = r26
;  xh = r27
;  yl = r28  ; StackPointer Ylo
;  yh = r29  ; StackPointer Yhi
;  zl = r30
;  zh = r31
  .def t4 = r26
  .def t5 = r27
  .def t6 = r30
  .def t7 = r31

; Macros
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

.macro lpm_
.if (FLASHEND < 0x8000) ; Word address
        lpm @0,@1
.else
        elpm @0,@1
.endif
.endmacro

.macro sub_pflash_z
.if (PFLASH > 0)
        subi    zh, high(PFLASH)
.endif
.endmacro

.macro add_pflash_z
.if (PFLASH > 0)
        subi    zh, high(0x10000-PFLASH)
.endif        
.endmacro

.macro sub_pflash_tos
.if (PFLASH > 0)
        subi    tosh, high(PFLASH)
.endif
.endmacro

.macro add_pflash_tos
.if (PFLASH > 0)
        subi    tosh, high(0x10000-PFLASH)
.endif        
.endmacro

.macro rampv_to_c
.if (FLASHEND >= 0x8000)
        bset    0
.else
        bclr    0
.endif
.endmacro

.macro fdw
  .dw ((@0<<1)+PFLASH)
.endmacro

; Symbol naming compatilibity

.ifndef SPMEN
.equ SPMEN=SELFPRGEN
.endif

.ifndef EEWE
.equ EEWE=EEPE
.endif

.ifndef EEMWE
.equ EEMWE=EEMPE
.endif

;.if OPERATOR_UART == 1
;.equ OP_TX_=TX1_
;.equ OP_RX_=RX1_
;.equ OP_RXQ=RX1Q
;.else
;.if OPERATOR_UART == 0
;.equ OP_TX_=TX0_
;.equ OP_RX_=RX0_
;.equ OP_RXQ=RX0Q
;.endif
;.endif

.define ubrr0val (FREQ_OSC/16/BAUDRATE0) - 1
.define ubrr1val (FREQ_OSC/16/BAUDRATE1) - 1
.define ms_value -(FREQ_OSC/1000)
.define BOOT_SIZE 0x400
.define BOOT_START FLASHEND - BOOT_SIZE + 1  ; atm128: 0xfc00, atm328: 0x3c00 
.define KERNEL_START BOOT_START - 0x0c00

;..............................................................................
;Program Specific Constants (literals used in code)
;..............................................................................
; Flash page size
.equ PAGESIZEB=PAGESIZE*2    ; Page size in bytes 

; Forth word header flags
.equ NFA= 0x80      ; Name field mask
.equ IMMED= 0x40    ; Immediate mask
.equ INLINE= 0x20   ; Inline mask for 1 and 2 cell code
.equ INLINE4= 0x20   ; Inline mask for 4 cell code
.equ INLINE5= 0x20   ; Inline mask for 5 cell code
.equ COMPILE= 0x10  ; Compile only mask
.equ NFAmask= 0xf   ; Name field length mask

; FLAGS2
.equ fLOAD=     4   ; 256 ms Load sample available
.equ fFC_tx1=   3   ; 0=Flow Control, 1 = no Flow Control   
.equ fFC_tx0=   2   ; 0=Flow Control, 1 = no Flow Control   
.equ ixoff_tx1= 1                    
.equ ixoff_tx0= 0

; FLAGS1
.equ noclear= 6     ; dont clear optimisation flags 
.equ idup=    5     ; Use dupzeroequal instead of zeroequal
.equ izeroeq= 4     ; Use brne instead of breq if zeroequal
.equ istream= 3
.equ fLOCK=   2
.equ fTAILC=  1
.equ idirty=  0

;;; For Flow Control
.equ XON=   0x11
.equ XOFF=  0x13

.equ CR_=0x0d
.equ LF_=0x0a
.equ BS_=0x08

;;; Memory mapping prefixes
.equ PRAM    = 0x0000                 ; 4 Kbytes of ram (atm128)
.equ PEEPROM = RAMEND+1               ; 4 Kbytes of eeprom (atm128)
.if (FLASHEND == 0xffff)              ; 64 Kwords flash
.equ OFLASH  = PEEPROM+EEPROMEND+1    ; 56 Kbytes available for FlashForth(atm128)
.equ PFLASH  = 0
.equ RAMPZV  = 1
.else
.if (FLASHEND == 0x7fff)              ; 32 Kwords flash
.equ OFLASH = PEEPROM+EEPROMEND+1     ; 56 Kbytes available for FlashForth
.equ PFLASH = 0
.equ RAMPZV  = 0
.else
.if (FLASHEND == 0x3fff)              ; 16 Kwords flash
.equ OFLASH = 0x8000                  ; 32 Kbytes available for FlashForth
.equ PFLASH = OFLASH
.else
.if (FLASHEND == 0x1fff)              ; 8  Kwords flash
.equ OFLASH = 0xC000                  ; 16 Kbytes available for FlashForth
.equ PFLASH = OFLASH
.endif
.endif
.endif
.endif

;;; USER AREA for the OPERATOR task
;.equ uaddsize=     0          ; No additional user variables 
.equ ursize=       RETURN_STACK_SIZE
.equ ussize=       PARAMETER_STACK_SIZE
.equ utibsize=     TIB_SIZE

;;; User variables and area
.equ us0=          -32         ; Start of parameter stack
.equ ur0=          -30         ; Start of ret stack
.equ uemit=        -28         ; User EMIT vector
.equ ukey=         -26         ; User KEY vector
.equ ukeyq=        -24         ; User KEY? vector
.equ ulink=        -22         ; Task link
.equ ubase=        -20         ; Number Base
.equ utib=         -18         ; TIB address
.equ utask=        -16         ; Task area pointer
.equ ustatus=      -14
.equ uflg=         -13
.equ ursave=       -12         ; Saved ret stack pointer
.equ ussave=       -10         ; Saved parameter stack pointer
.equ upsave=       -8
.equ usource=      -6          ; Two cells
.equ utoin=        -2          ; Input stream
.equ uhp=           0          ; Hold pointer


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
ivec:       .byte INT_VECTORS_SIZE

rxqueue0:
rbuf0_wr:    .byte 1
rbuf0_rd:    .byte 1
rbuf0_lv:    .byte 1
rbuf0:       .byte RX0_BUF_SIZE

.ifdef UDR1
rxqueue1:
rbuf1_wr:    .byte 1
rbuf1_rd:    .byte 1
rbuf1_lv:    .byte 1
rbuf1:       .byte RX1_BUF_SIZE
.endif

ms_count:   .byte 2
dpSTART:    .byte 2
dpFLASH:    .byte 2 ; DP's and LATEST in RAM
dpEEPROM:   .byte 2
dpRAM:      .byte 2
dpLATEST:   .byte 2


status:     .byte 1 ; Idle status of all tasks
cse:        .byte 1 ; Current data section 0=flash, 1=eeprom, 2=ram
state:      .byte 1 ; Compilation state
uvars:      .byte   (-us0)
up0:        .byte   2
urbuf:      .byte   ursize
usbuf:      .byte   ussize
utibbuf:    .byte   utibsize
dpdata:     .byte   2

.eseg
.org 0
        .dw 0xffff  ; Force first cell of eeprom to 0xffff
;*******************************************************************
; Start of kernel
;*******************************************************************
.cseg
.org KERNEL_START

;*******************************************************
umstar0:
        movw t0, tosl
        poptos
        mul tosl,t0
        movw t4, r0 ; r0=t2, r1=t3
        clr t6
        clr t7
        mul tosh, t0
        add t5, r0
        adc t6, r1
        adc t7, zero
        mul tosl, t1
        add t5, r0
        adc t6, r1
        adc t7, zero
        mul tosh, t1
        add t6, r0
        adc t7, r1
        movw tosl, t4
        pushtos
        movw tosl, t6
        ret

;***********************************************************
; unsigned 32/16 -> 16/16 division
umslashmod0:
        movw t4, tosl

        ld t3, Y+
        ld t6, Y+
  
        ld t1, Y+
        ld t2, Y+

; unsigned 32/16 -> 16/16 division
        ; set loop counter
        ldi t0,$10 ;6

umslashmod1:
        ; shift left, saving high bit
        clr t7
        lsl t1
        rol t2
        rol t3
        rol t6
        rol t7

        ; try subtracting divisor
        cp  t3, t4
        cpc t6, t5
        cpc t7,zero

        brcs umslashmod2

        ; dividend is large enough
        ; do the subtraction for real
        ; and set lowest bit
        inc t1
        sub t3, t4
        sbc t6, t5

umslashmod2:
        dec  t0
        brne umslashmod1 ;16=17=272

umslashmod3:
        ; put remainder on stack
        st -Y,t6
        st -Y,t3

        ; put quotient on stack
        mov tosl, t1
        mov tosh, t2     ; 6 + 272 + 6 =284 cycles
        ret
; *******************************************************************
; EXIT --   Compile a return
;        variable link
        .dw     0
EXIT_L:
        .db     NFA|4,"exit",0
EXIT:
        pop     t0
        pop     t0
        ret

; idle
        fdw EXIT_L 
IDLE_L:
        .db     NFA|4,"idle",0
IDLE:
.if IDLE_MODE == 1
        rcall   IDLE_HELP
        breq    IDLE1
        lds     t0, status 
        dec     t0
        sts     status, t0
        st      x, zero
.endif
IDLE1:
        ret
        
; busy
        fdw IDLE_L 
BUSY_L:
        .db     NFA|4,"busy",0
BUSY:
.if IDLE_MODE == 1
        rcall   IDLE_HELP
        brne    BUSY1
        lds     t0, status
        inc     t0
        sts     status, t0
        st      x, t0
BUSY1:
.endif
        ret


.if IDLE_MODE == 1
IDLE_HELP:
        movw    xl, upl
        sbiw    xl, -ustatus 
        ld      t0, x
        cpi     t0, 0
        ret
.endif
        
; busy
        fdw BUSY_L 
LOAD_L:
        .db     NFA|4,"load",0
LOAD:
        ret
; *********************************************
; Bit masking 8 bits, only for ram addresses !
; : mset ( mask addr -- )
;   dup >r c@ swap or r> c!
; ;
        fdw     ICCOMMA_L
MSET_L:
        .db     NFA|4,"mset",0
MSET:
        movw    zl, tosl
        poptos
        ld      t0, z
        or      t0, tosl
        st      z, t0
        poptos
        ret
        
; : mclr  ( mask addr -- )
;  dup >r c@ swap invert and r> c!
; ;
        fdw     MSET_L
MCLR_L:
        .db     NFA|4,"mclr",0
MCLR_:
        movw    zl, tosl
        poptos
        ld      t0, z
        com     tosl
        and     t0, tosl
        st      z, t0
        poptos
        ret

;   LSHIFT      x1 u -- x2
        fdw     MCLR_L
LSHIFT_L:
        .db     NFA|6,"lshift",0
LSHIFT:
        movw    zl, tosl
        poptos
LSHIFT1:
        sbiw    zl, 1
        brmi    LSHIFT2
        lsl     tosl
        rol     tosh
        rjmp    LSHIFT1
LSHIFT2:
        ret

;   RSHIFT      x1 u -- x2
        fdw     LSHIFT_L
RSHIFT_L:
        .db     NFA|6,"rshift",0
RSHIFT:
        movw    zl, tosl
        poptos
RSHIFT1:
        sbiw    zl, 1
        brmi    RSHIFT2
        lsr     tosh
        ror     tosl
        rjmp    RSHIFT1
RSHIFT2:
        ret

;**********************************************
NEQUALSFETCH:
        rcall   CFETCHPP
        rcall   ROT
        rcall   CFETCHPP
        jmp     ROT
;***************************************************
; N=    c-addr nfa -- n   string:name cmp
;             n=0: s1==s2, n=ffff: s1!=s2
; N= is specificly used for finding dictionary entries
; It can also be used for comparing strings shorter than 16 characters,
; but the first string must be in ram and the second in program memory.
        fdw     RSHIFT_L
NEQUAL_L:
        .db     NFA|2,"n=",0
NEQUAL:
        rcall   NEQUALSFETCH
        andi    tosl, 0xf
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    NEQUAL5
        rcall   ONEMINUS
        rcall   CFETCHPP
        rcall   TOR
        rjmp    NEQUAL4
NEQUAL2:
        rcall   NEQUALSFETCH
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        breq    NEQUAL3
        rcall   TRUE_
        call    LEAVE
        rjmp    NEQUAL4
NEQUAL3:
        rcall   RFETCH
        rcall   ZEROSENSE
        brne    NEQUAL4
        rcall   FALSE_
NEQUAL4:
        call    XNEXT
        brcc    NEQUAL2
        pop     t1
        pop     t0
        rjmp    NEQUAL6
NEQUAL5:
        rcall   TRUE_
NEQUAL6:
        rcall   NIP
        jmp     NIP

; SKIP   c-addr u c -- c-addr' u'
;                          skip matching chars
; u (count) must be smaller than 256
        fdw     NEQUAL_L
SKIP_L:
        .db     NFA|4,"skip",0
SKIP:

        rcall   TOR
SKIP1:
        rcall   DUP
        rcall   ZEROSENSE
        breq    SKIP2
        rcall   OVER
        rcall   CFETCH_A
        rcall   RFETCH
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    SKIP2
        rcall   ONE
        rcall   SLASHSTRING
        rjmp    SKIP1
SKIP2:
        pop     t0
        pop     t0
        ret


; SCAN   c-addr u c -- c-addr' u'
;                          find matching chars


        fdw     SKIP_L
SCAN_L:
        .db     NFA|4,"scan",0
SCAN:
        rcall   STORE_P_TO_R
        rcall   TOR
        rjmp    SCAN3
SCAN1:
        rcall   CFETCHPP
        call    FETCH_P
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    SCAN3
        rcall   ONEMINUS
        rjmp    SCAN4
SCAN3:
        call    XNEXT
        brcc    SCAN1
SCAN4:
        rcall   RFROM
        rcall   ONEPLUS
        rcall   R_TO_P
        ret

; : mtst ( mask addr -- flag )
;   c@ and 
; ;
        fdw     SCAN_L
MTST_L:
        .db     NFA|4,"mtst",0
MTST:
        call    CFETCH
        jmp     AND_

        fdw     MTST_L
FCY_L:
        .db     NFA|3,"Fcy"
        rcall   DOCREATE
        .dw     FREQ_OSC / 1000

;*******************************************************
; Assembler
;*******************************************************
; FIXME
;*******************************************************
        

;;; Check parameter stack pointer
        .db     NFA|3,"sp?"
check_sp:
        rcall   SPFETCH
        call    R0_
        rcall   FETCH_A
        call    S0
        rcall   FETCH_A
        rcall   ONEPLUS
        rcall   WITHIN
        rcall   XSQUOTE
        .db     3,"SP?"
        rcall   QABORT
        ret
;***************************************************
; EMIT  c --    output character to the emit vector
        fdw     FCY_L
EMIT_L:
        .db     NFA|4,"emit",0
EMIT:
        rcall   UEMIT_
        jmp     FEXECUTE

;***************************************************
; KEY   -- c    get char from UKEY vector
        fdw     EMIT_L
KEY_L:
        .db     NFA|3,"key"
KEY:
        rcall   UKEY_
        jmp     FEXECUTE

;***************************************************
; KEY   -- c    get char from UKEY vector
        fdw     KEY_L
KEYQ_L:
        .db     NFA|4,"key?",0
KEYQ:
        rcall   UKEYQ_
        jmp     FEXECUTE

        fdw     KEYQ_L
EXECUTE_L:
        .db     NFA|7,"execute"
EXECUTE:
        movw    zl, tosl
        sub_pflash_z
        poptos
        rampv_to_c
        ror     zh
        ror     zl
        ijmp

        fdw     EXECUTE_L
FEXECUTE_L:
        .db     NFA|3,"@ex"
FEXECUTE:
        rcall   FETCH_A
        jmp     EXECUTE

        fdw     FEXECUTE_L
VARIABLE_L:
        .db     NFA|8,"variable",0
VARIABLE_:
        rcall   CREATE
        rcall   CELL
        jmp     ALLOT

        fdw     VARIABLE_L
CONSTANT_L:
        .db     NFA|8,"constant",0
CONSTANT_:
        rcall   COLON
        call    LITERAL
        jmp     SEMICOLON

; DOCREATE, code action of CREATE
; Fetch the next cell from program memory to the parameter stack
DOCREATE_L:
        .db     NFA|3, "(c)"
DOCREATE:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        lpm_    tosl, z+
        lpm_    tosh, z+
        pop     zh
        pop     zl
        ijmp

;;; Resolve the runtime action of the word created by using does>
DODOES_L:
        .db     NFA|3, "(d)"
DODOES:
        pop     xh
        pop     xl
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        pushtos
        lpm_    tosl, z+
        lpm_    tosh, z+
        movw    r31:r30, r27:r26
        ijmp    ; (z)

;   SP@     -- addr         get parameter stack pointer
        fdw     CONSTANT_L
SPFETCH_L:
        .db     NFA|3,"sp@"
SPFETCH:
        movw    r31:r30, r29:r28 ;z,y
        pushtos
        movw    tosl, r31:r30 ;z
        ret

;   SP!     addr --         store stack pointer
        .db     NFA|3,"sp!"
SPSTORE:
        movw    r29:r28, tosl ; y
        ret

;   RPEMPTY     -- EMPTY THE RETURN STACK       
        .db     NFA|3,"rp0"
RPEMPTY:
        pop     xh
        pop     xl
        rcall   R0_
        rcall   FETCH_A
        out     spl, tosl
        out     sph, tosh
        poptos
        movw    zl, xl
        ijmp

; DICTIONARY POINTER FOR the current section
; Flash -- sets the data section to flash
        fdw     SPFETCH_L
FLASH_L:
ROM_N:  
        .db     NFA|5,"flash"
ROM_:
        sts     cse, zero
        ret

; EEPROM -- sets the data section to EEPROM data memory
        fdw     FLASH_L
EEPROM_L:
EROM_N: 
        .db     NFA|6,"eeprom",0
EROM:
        sts     cse, r_two
        ret
        
; RAM -- sets the data section to RAM memory
        fdw     EEPROM_L
RAM_L:
FRAM_N: 
        .db     NFA|3,"ram"
FRAM:
        sts     cse, r_four
        ret

; DP    -- a-addr          
; Fetched from EEPROM
        fdw     RAM_L
DP_L:
        .db     NFA|2,"dp",0
DP:
        rcall   IDP
        rcall   CSE_
        jmp     PLUS


;;; 
        .db     NFA|3,"cse"
CSE_:
        pushtos
        lds     tosl, cse
        clr     tosh
        ret

; HERE    -- addr    get current data space ptr
;   DP @ ;
        fdw     DP_L
HERE_L:
        .db     NFA|4,"here",0
HERE:
        rcall   DP
        jmp     FETCH

; ,   x --             append cell to current data space
;   HERE ! CELL ALLOT ;
        fdw     HERE_L
COMMA_L:
        .db     NFA|1,","
COMMA:
        rcall   HERE
        rcall   STORE_A
        rcall   CELL
        jmp     ALLOT

; C,  c --             append char to current data space
;   HERE C! 1 ALLOT ;
        fdw     COMMA_L 
CCOMMA_L:
        .db     NFA|2,"c,",0
CCOMMA:
        rcall   HERE
        rcall   CSTORE_A
        rcall   ONE
        jmp     ALLOT


; CELL     -- n                 size of one cell
        fdw     CCOMMA_L
CELL_L:
        .db     NFA|4,"cell",0
CELL:
        pushtos
        ldi     tosl, 2
        ldi     tosh, 0
        ret

; ALIGN    --                         align DP
        fdw     CELL_L
ALIGN_L:
        .db     NFA|5,"align"
ALIGN:
        rcall   HERE
        rcall   ALIGNED
        rcall   DP
        jmp     STORE

; ALIGNED  addr -- a-addr       align given addr
        fdw     ALIGN_L
ALIGNED_L:
        .db     NFA|7,"aligned"
ALIGNED:
        adiw    tosl, 1
        rcall   DOLIT
        .dw     0xfffe
        jmp     AND_

; CELL+    a-addr1 -- a-addr2      add cell size
;   2 + ;
        fdw     ALIGNED_L
CELLPLUS_L:
        .db     NFA|INLINE|5,"cell+"
CELLPLUS:
        adiw    tosl, 2
        ret

; CELLS    n1 -- n2            cells->adrs units
        fdw     CELLPLUS_L
CELLS_L:
        .db     NFA|INLINE|5,"cells"
CELLS:
        lsl     tosl
        rol     tosh
        ret

; CHAR+    c-addr1 -- c-addr2   add char size
        fdw     CELLS_L
CHARPLUS_L:
        .db     NFA|INLINE|5,"char+"
CHARPLUS:
        adiw    tosl, 1
        ret

; CHARS    n1 -- n2            chars->adrs units
        fdw     CHARPLUS_L
CHARS_L:
        .db     NFA|INLINE|5,"chars"
CHARS:  ret

        fdw     CHARS_L
COMMAXT_L:
        .db     NFA|3, "cf,"
COMMAXT:
        rcall   DUP
        rcall   IHERE
        rcall   MINUS
        rcall   ABS_ 
        rcall   DOLIT
        .dw     0xff0
        rcall   GREATER
        rcall   ZEROSENSE
        breq    STORECF1
STORECFF1: 
;        rcall   CALL_
        rcall   DOLIT
        .dw     0x940E      ; call jmp:0x940d
        call    ICOMMA
        sub_pflash_tos
        rampv_to_c
        ror     tosh
        ror     tosl
        call    ICOMMA
        rjmp    STORECF2
STORECF1:
        rcall   IHERE
        rcall   MINUS
        rcall   TWOMINUS
        rcall   TWOSLASH
        ;rcall   RCALL_
        andi    tosh, 0x0f
        ori     tosh, 0xd0
        call    ICOMMA
STORECF2:
        ret


; !COLON   --       change code field to docolon
;   -6 IALLOT ; 
;       .dw    link
;link   set     $
        .db     NFA|6,"!colon",0
STORCOLON:
        rcall   DOLIT
        .dw     0xfffa         ;  -6
        jmp     IALLOT


; 2@    a-addr -- x1 x2            fetch 2 cells
;   DUP @ SWAP CELL+ @ ;
;   the lower address will appear on top of stack
        fdw     COMMAXT_L
TWOFETCH_L:
        .db     NFA|2,"2@",0
TWOFETCH:
        rcall   DUP
        rcall   FETCH_A
        rcall   SWOP
        rcall   CELLPLUS
        jmp     FETCH_A

; 2!    x1 x2 a-addr --            store 2 cells
;   SWAP OVER ! CELL+ ! ;
;   the top of stack is stored at the lower adrs
        fdw     TWOFETCH_L
TWOSTORE_L:
        .db     NFA|2,"2!",0
TWOSTORE:
        rcall   SWOP
        rcall   OVER
        rcall   CELLPLUS
        rcall   STORE_A
        jmp     STORE

; 2DROP  x1 x2 --                   drop 2 cells
;   DROP DROP ;
        fdw     TWOSTORE_L
TWODROP_L:
        .db     NFA|5,"2drop"
TWODROP:
        rcall   DROP
        jmp     DROP

; 2DUP   x1 x2 -- x1 x2 x1 x2    dup top 2 cells
;   OVER OVER ;
        fdw     TWODROP_L
TWODUP_L:
        .db     NFA|4,"2dup",0
TWODUP:
        rcall   OVER
        jmp     OVER

; 2SWAP   x1 x2 x3 x4 -- x3 x4 x1 x2    dup top 2 cells
        fdw     TWODUP_L
TWOSWAP_L:
        .db     NFA|5,"2swap"
TWOSWAP:
        rcall   ROT
        rcall   TOR
        rcall   ROT
        rcall   RFROM
        ret

; INPUT/OUTPUT ==================================

; SPACE   --                      output a space
;   BL EMIT ;
        fdw     TWOSWAP_L
SPACE_L:
        .db     NFA|5,"space"
SPACE_:  
        rcall   BL
        jmp     EMIT

; SPACES   n --                  output n spaces
;   BEGIN DUP WHILE SPACE 1- REPEAT DROP ;
        fdw     SPACE_L
SPACES_L:
        .db     NFA|6,"spaces",0
SPACES:
SPCS1:
        rcall   DUPZEROSENSE
        breq    SPCS2
        rcall   SPACE_
        rcall   ONEMINUS
        rjmp    SPCS1
SPCS2:  jmp     DROP


; umin     u1 u2 -- u           unsigned minimum
;   2DUP U> IF SWAP THEN DROP ;
        fdw     SPACES_L
UMIN_L:
        .db     NFA|4,"umin",0
UMIN:
        rcall   TWODUP
        rcall   UGREATER
        rcall   ZEROSENSE
        breq    UMIN1
        rcall   SWOP
UMIN1:  jmp     DROP


; umax    u1 u2 -- u            unsigned maximum
;   2DUP U< IF SWAP THEN DROP ;
        fdw     UMIN_L
UMAX_L:
        .db     NFA|4,"umax",0
UMAX:
        rcall   TWODUP
        rcall   ULESS
        rcall   ZEROSENSE
        breq    UMAX1
        rcall   SWOP
UMAX1:  jmp     DROP

        fdw     UMAX_L
ONE_L:
        .db     NFA|INLINE4|1,"1"
ONE:
        pushtos
        ldi     tosl, 1
        ldi     tosh, 0
        ret

; ACCEPT  c-addr +n -- +n'  get line from terminal
        fdw     ONE_L
ACCEPT_L:
        .db     NFA|6,"accept",0
ACCEPT:
        rcall   OVER
        rcall   PLUS
        rcall   OVER
ACC1:
        rcall   KEY

        cpi     tosl, CR_
        brne    ACC_LF
        
        rcall   TRUE_
        rcall   FCR
        rcall   CSTORE_A
        rcall   DROP
        rjmp    ACC6
ACC_LF:
        cpi     tosl, LF_
        brne    ACC2
        rcall   DROP

        rcall   FCR
        rcall   CFETCH_A
        rcall   ZEROSENSE
        breq    ACC6
        rjmp    ACC1
ACC2:
        rcall   FALSE_
        rcall   FCR
        rcall   CSTORE_A
        rcall   DUP
        rcall   EMIT
        rcall   DUP
        rcall   DOLIT
        .dw     BS_
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ACC3
        rcall   DROP
        rcall   ONEMINUS
        rcall   TOR
        rcall   OVER
        rcall   RFROM
        rcall   UMAX
        rjmp    ACC1
ACC3:
        rcall   OVER
        rcall   CSTORE_A
        rcall   ONEPLUS
        rcall   OVER
        rcall   UMIN
        rcall   TWODUP
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        brne     ACC1
ACC6:
        rcall   NIP
        rcall   SWOP
        jmp     MINUS

        .db     NFA|3,"fcr"
FCR:
        rcall   DOUSER
        .dw     uflg


; TYPE    c-addr u --   type line to terminal u < $100
; : type for c@+ emit next drop ;

        fdw      ACCEPT_L
TYPE_L:
        .db     NFA|4,"type",0
TYPE:
        rcall   TOR
        rjmp    TYPE2       ; XFOR
TYPE1:  
        rcall   CFETCHPP
        rcall   EMIT
TYPE2:
        rcall   XNEXT
        brcc    TYPE1
        pop     t1
        pop     t0
        jmp     DROP


; (S"    -- c-addr u      run-time code for S"
        .db      NFA|3,"(s",0x22
XSQUOTE:
        rcall   RFETCH
        lsl     tosl
        rol     tosh
        add_pflash_tos
        rcall   CFETCHPP
        rcall   DUP
        rcall   ALIGNED
        lsr     tosh
        ror     tosl
        rcall   RFROM
        rcall   PLUS
        rcall   TOR
        ret

        fdw     TYPE_L
SQUOTE_L:
        .db      NFA|IMMED|COMPILE|2,"s",0x22,0
SQUOTE:
        rcall   DOLIT
        fdw     XSQUOTE
        rcall   COMMAXT
        rcall   ROM_
        rcall   CQUOTE
        jmp     FRAM

        fdw     SQUOTE_L
CQUOTE_L:
        .db     NFA|2,",",0x22,0
CQUOTE: 
        rcall   DOLIT
        .dw     0x22
        rcall   PARSE
        rcall   HERE
        rcall   OVER
        rcall   ONEPLUS
        rcall   ALIGNED
        rcall   ALLOT
        jmp     PLACE


        fdw     CQUOTE_L
DOTQUOTE_L:
        .db      NFA|IMMED|COMPILE|2,".",0x22,0
DOTQUOTE:
        rcall   SQUOTE
        rcall   DOLIT
        fdw     TYPE
        jmp     COMMAXT

        fdw     DOTQUOTE_L
ALLOT_L:
        .db     NFA|5,"allot"
ALLOT:
        rcall   DP
        jmp     PLUSSTORE

        fdw     ALLOT_L
DROP_L:
        .db     NFA|INLINE|4,"drop",0
DROP:
        poptos
        ret

        fdw     DROP_L
SWOP_L:
        .db     NFA|INLINE5|4,"swap",0
SWOP:
        ld      t0, y+
        ld      t1, y+
        pushtos
        movw    tosl, t0
        ret

        fdw     SWOP_L
OVER_L:
        .db     NFA|INLINE4|4,"over",0
OVER:
        pushtos
        ldd     tosl, y+2
        ldd     tosh, y+3
        ret

        fdw     OVER_L
ROT_L:
        .db     NFA|3, "rot"
ROT:
        rcall   TOR
        rcall   SWOP
        rcall   RFROM
        rjmp    SWOP

        fdw     ROT_L
TOR_L:
        .db     NFA|COMPILE|2,">r",0
TOR:
        pop     zh
        pop     zl
        push    tosl
        push    tosh
        poptos
        ijmp

        fdw     TOR_L
RFROM_L:
        .db     NFA|COMPILE|2,"r>",0
RFROM:
        pop     zh
        pop     zl
        pushtos
        pop     tosh
        pop     tosl
        ijmp

        fdw     RFROM_L
RFETCH_L:
        .db     NFA|COMPILE|2,"r@",0
RFETCH:
        pop     zh
        pop     zl
        pushtos
        pop     tosh
        pop     tosl
        push    tosl
        push    tosh
        ijmp


;   ABS     n   --- n1      absolute value of n
        fdw     DUP_L
ABS_L:
        .db     NFA|3,"abs"
ABS_:
        rcall   DUP
        jmp     QNEGATE

        fdw     ABS_L
PLUS_L:
        .db     NFA|INLINE4|1, "+"

PLUS:
        ld      t0, Y+        
        ld      t1, Y+
        add     tosl, t0
        adc     tosh, t1
        ret

; m+  ( d n -- d1 )
        fdw     PLUS_L
MPLUS_L:
        .db     NFA|2, "m+",0
MPLUS:
        rcall   STOD
        jmp     DPLUS

        fdw     MPLUS_L
MINUS_L:
        .db     NFA|INLINE5|1, "-"
MINUS:
        ld      t0, Y+
        ld      t1, Y+
        sub     t0, tosl
        sbc     t1, tosh
        movw    tosl, t0
        ret

        fdw     MINUS_L
AND_L:
        .db     NFA|INLINE4|3, "and"
AND_:
        ld      t0, Y+
        ld      t1, Y+
        and     tosl, t0
        and     tosh, t1
        ret

        fdw     AND_L
OR_L:
        .db     NFA|INLINE4|2, "or",0
OR_:
        ld      t0, Y+
        ld      t1, Y+
        or      tosl, t0
        or      tosh, t1
        ret

        fdw     OR_L
XOR_L:
        .db     NFA|INLINE4|3, "xor"
XOR_:
        ld      t0, Y+
        ld      t1, Y+
        eor     tosl, t0
        eor     tosh, t1
        ret

        fdw     XOR_L
INVERT_L:
        .db     NFA|INLINE|6, "invert",0
INVERT:
        com     tosl
        com     tosh
        ret

        fdw     INVERT_L
NEGATE_L:
        .db     NFA|6, "negate",0
NEGATE:
        rcall   INVERT
        jmp     ONEPLUS

        fdw     NEGATE_L
ONEPLUS_L:
        .db     NFA|INLINE|2, "1+",0
ONEPLUS:
        adiw    tosl, 1
        ret

        fdw     ONEPLUS_L
ONEMINUS_L:
        .db     NFA|INLINE|2, "1-",0
ONEMINUS:
        sbiw    tosl, 1
        ret

        fdw     ONEMINUS_L
TWOPLUS_L:
        .db     NFA|INLINE|2, "2+",0
TWOPLUS:
        adiw    tosl, 2
        ret

        fdw     TWOPLUS_L
TOBODY_L:
        .db     NFA|INLINE|5, ">body"
TOBODY:
        adiw    tosl, 4
        ret

        fdw     TOBODY_L
TWOSTAR_L:
        .db     NFA|INLINE|2, "2*",0
TWOSTAR:
        lsl     tosl
        rol     tosh
        ret

        fdw     TWOSTAR_L
TWOSLASH_L:
        .db     NFA|INLINE|2, "2/",0
TWOSLASH:
        asr     tosh
        ror     tosl
        ret

        fdw     TWOSLASH_L
PLUSSTORE_L:
        .db     NFA|2,"+!",0
PLUSSTORE:
        rcall   SWOP
        rcall   OVER
        rcall   FETCH_A
        rcall   PLUS
        rcall   SWOP
        jmp     STORE

        fdw     PLUSSTORE_L
WITHIN_L:
        .db     NFA|6,"within",0
WITHIN:
        rcall   OVER
        rcall   MINUS
        rcall   TOR
        rcall   MINUS
        rcall   RFROM
        jmp     ULESS

        fdw     WITHIN_L
NOTEQUAL_L:
        .db     NFA|2,"<>",0
NOTEQUAL:
        jmp     XOR_

        fdw     ZEROLESS_L
EQUAL_L:
        .db     NFA|1, "="
EQUAL:
        rcall   MINUS
        jmp     ZEROEQUAL


        fdw     EQUAL_L
LESS_L:
        .db     NFA|1,"<"
LESS:
        rcall   MINUS
        jmp     ZEROLESS

        fdw     LESS_L
GREATER_L:
        .db     NFA|1,">"
GREATER:
        rcall   SWOP
        jmp     LESS

        fdw     GREATER_L
ULESS_L:
        .db     NFA|2,"u<",0
ULESS:
        rcall   MINUS
        brpl    ULESS1        ; Carry test  
        rjmp    TRUE_F
ULESS1:
        jmp     FALSE_F


        fdw     ULESS_L
UGREATER_L:
        .db     NFA|2, "u>",0
UGREATER:
        rcall   SWOP
        jmp     ULESS

        fdw     UGREATER_L
STORE_P_L:
        .db     NFA|2,"!p",0
STORE_P:
        movw    pl, tosl
        poptos
        ret

        fdw     STORE_P_L
STORE_P_TO_R_L:
        .db     NFA|COMPILE|4,"!p>r",0
STORE_P_TO_R:
        pop     zh
        pop     zl
        push    pl
        push    ph
        movw    pl, tosl
        poptos
        ijmp

        fdw     STORE_P_TO_R_L
R_TO_P_L:
        .db     NFA|COMPILE|3,"r>p"
R_TO_P:
        pop     zh
        pop     zl
        pop     ph
        pop     pl
        ijmp

        fdw     R_TO_P_L
PFETCH_L:
        .db     NFA|2,"p@",0
PFETCH:
        pushtos
        movw    tosl, pl
        jmp     FETCH

        fdw     PFETCH_L
PSTORE_L:
        .db     NFA|2,"p!",0
PSTORE:
        pushtos
        movw    tosl, pl
        jmp     STORE

        fdw     PSTORE_L
PCSTORE_L:
        .db     NFA|3,"pc!"
PCSTORE:
        pushtos
        movw    tosl, pl
        jmp     CSTORE

        fdw     PCSTORE_L
PPLUS_L:
        .db     NFA|INLINE|2,"p+",0
PPLUS:
        add     pl, r_one
        adc     ph, zero
        ret

        fdw     PPLUS_L
PNPLUS_L:
        .db     NFA|3,"p++"
PNPLUS:
        add     pl, tosl
        adc     ph, tosh
        poptos
        ret

        fdw     PNPLUS_L
UEMIT_L:
        .db     NFA|5,"'emit"
UEMIT_:
        rcall   DOUSER
        .dw     uemit
        
        fdw     UEMIT_L
UKEY_L:
        .db     NFA|4,"'key",0
UKEY_:
        rcall   DOUSER
        .dw     ukey

        fdw     UKEY_L
UKEYQ_L:
        .db     NFA|5,"'key?"
UKEYQ_:
        rcall   DOUSER
        .dw     ukeyq

        .db     NFA|3,"?0="
ZEROSENSE:
        sbiw    tosl, 0
        poptos
        ret

        .db     NFA|3,"d0="
DUPZEROSENSE:
        sbiw    tosl, 0
        ret

        fdw     UKEYQ_L
UMSTAR_L:
        .db     NFA|3,"um*"
UMSTAR:
        jmp     umstar0

        fdw     UMSTAR_L
UMSLASHMOD_L:
        .db     NFA|6,"um/mod",0
UMSLASHMOD:
        jmp     umslashmod0


        fdw     UMSLASHMOD_L
USLASHMOD_L:
        .db     NFA|5,"u/mod"
USLASHMOD:
        rcall   FALSE_
        rcall   SWOP
        jmp     umslashmod0

        fdw     USLASHMOD_L
STAR_L:
        .db     NFA|1,"*"
STAR: 
        rcall   UMSTAR
        jmp     DROP

        fdw     STAR_L
USLASH_L:
        .db     NFA|2,"u/",0
USLASH:
        rcall   USLASHMOD
        jmp     NIP

        fdw     USLASH_L
USSMOD_L:
        .db     NFA|6,"u*/mod",0
USSMOD:
        rcall   TOR
        rcall   UMSTAR
        rcall   RFROM
        jmp     UMSLASHMOD


        fdw     USSMOD_L
SLASH_L:
        .db     NFA|1,"/"
SLASH: 
        rcall   TWODUP
        rcall   XOR_
        rcall   TOR
        rcall   ABS_
        rcall   SWOP
        rcall   ABS_
        rcall   SWOP
        rcall   USLASH
        rcall   RFROM
        jmp     QNEGATE

        fdw     SLASH_L
NIP_L:
        .db     NFA|3,"nip"
NIP:
        rcall   SWOP
        jmp     DROP
    
        fdw     NIP_L
TUCK_L:
        .db     NFA|4,"tuck",0
TUCK:
        rcall   SWOP
        jmp     OVER

        fdw     TUCK_L
QNEGATE_L:
        .db     NFA|7,"?negate"
QNEGATE:
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    QNEGATE1
        rcall   NEGATE
QNEGATE1:
        ret

        fdw     QNEGATE_L
MAX_L:
        .db     NFA|3,"max"
MAX:    rcall   TWODUP
        rcall   LESS
        rcall   ZEROSENSE
        breq    max1
        rcall   SWOP
max1:   jmp     DROP

        fdw     MAX_L
MIN_L:
        .db     NFA|3,"min"
MIN:    rcall   TWODUP
        rcall   GREATER
        rcall   ZEROSENSE
        brne    pc+2
        rjmp    min1
;        breq    min1
        rcall   SWOP
min1:   jmp     DROP

        .db     NFA|2,"c@",0
CFETCH_A:       
        jmp     CFETCH

        .db     NFA|2,"c@",0
CSTORE_A:       
        jmp     CSTORE

        fdw     MIN_L
UPTR_L:
        .db     NFA|2,"up",0
UPTR:   rcall   DOCREATE
        .dw     2 ; upl

        fdw     UPTR_L
HOLD_L:
        .db     NFA|4,"hold",0
HOLD:   rcall   TRUE_
        rcall   HP
        rcall   PLUSSTORE
        rcall   HP
        rcall   FETCH_A
        jmp     CSTORE

; <#    --              begin numeric conversion
;   PAD HP ! ;          (initialize Hold Pointer)
        fdw     HOLD_L
LESSNUM_L:
        .db     NFA|2,"<#",0
LESSNUM: 
        rcall   PAD
        rcall   HP
        jmp     STORE

; >digit   n -- c            convert to 0..9a..z
        fdw     LESSNUM_L
TODIGIT_L:
        .db     NFA|6,">digit",0
TODIGIT: 
        rcall   DUP
        rcall   DOLIT
        .dw     9
        rcall   GREATER
        rcall   DOLIT
        .dw     0x27
        rcall   AND_
        rcall   PLUS
        rcall   DOLIT
        .dw     0x30
        jmp     PLUS

; #     ud1 -- ud2     convert 1 digit of output
;   base @ ud/mod rot >digit hold ;
        fdw     TODIGIT_L
NUM_L:
        .db     NFA|1,"#"
NUM:
        rcall   BASE
        rcall   FETCH_A
        rcall   UDSLASHMOD
        rcall   ROT
        rcall   TODIGIT
        jmp     HOLD

; #S    ud1 -- ud2      convert remaining digits
;   begin # 2dup or 0= until ;
        fdw     NUM_L
NUMS_L:
        .db     NFA|2,"#s",0
NUMS:
        rcall   NUM
        rcall   TWODUP
        rcall   OR_
        rcall   ZEROSENSE
        brne    NUMS
        ret

; #>    ud1 -- c-addr u    end conv., get string
;   2drop hp @ pad over - ;
        fdw     NUMS_L
NUMGREATER_L:
        .db     NFA|2,"#>", 0
NUMGREATER:
        rcall   TWODROP
        rcall   HP
        rcall   FETCH_A
        rcall   PAD
        rcall   OVER
        jmp     MINUS

; SIGN  n --               add minus sign if n<0
;   0< IF 2D HOLD THEN ; 
        fdw     NUMGREATER_L
SIGN_L:
        .db     NFA|4,"sign",0
SIGN:   
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    SIGN1
        rcall   DOLIT
        .dw     0x2D
        rcall   HOLD
SIGN1:
        ret

; U.    u --                  display u unsigned
;   <# 0 #S #> TYPE SPACE ;
        fdw     SIGN_L
UDOT_L:
        .db     NFA|2,"u.",0
UDOT:
        rcall   LESSNUM
        rcall   FALSE_
        rcall   NUMS
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_


; U.R    u +n --      display u unsigned in field of n. 1<n<=255 
;    0 swap <# 1- for # next #s #> type space ;
        fdw     UDOT_L
UDOTR_L:
        .db     NFA|3,"u.r"
UDOTR:
        rcall   LESSNUM
        rcall   ONEMINUS
        rcall   TOR
        rcall   FALSE_
        rjmp    UDOTR2
UDOTR1:
        rcall   NUM
UDOTR2: 
        rcall   XNEXT
        brcc    UDOTR1
        pop     t1
        pop     t0
        rcall   NUMS
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_

; .     n --                    display n signed
;   <# DUP ABS #S SWAP SIGN #> TYPE SPACE ;
        fdw     UDOTR_L
DOT_L:
        .db     NFA|1,"."
DOT:    rcall   LESSNUM
        rcall   DUP
        rcall   ABS_
        rcall   FALSE_
        rcall   NUMS
        rcall   ROT
        rcall   SIGN
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_

        FDW     DOT_L
DECIMAL_L:
        .db     NFA|7,"decimal"
DECIMAL: 
        rcall   TEN
        rcall   BASE
        jmp     STORE

; HEX     --              set number base to hex
;   #16 BASE ! ;
        Fdw     DECIMAL_l
HEX_L:
        .db     NFA|3,"hex"
HEX:
        rcall   DOLIT
        .dw     16
        rcall   BASE
        jmp     STORE

; BIN     --              set number base to binary
;   #2 BASE ! ;
        Fdw     HEX_L
BIN_L:
        .db     NFA|3,"bin"
BIN:    rcall   CELL
        rcall   BASE
        jmp     STORE

.ifndef SKIP_MULTITASKING
; RSAVE   -- a-addr     Saved return stack pointer
        fdw     BIN_L
RSAVE_L:
        .db     NFA|5,"rsave"
RSAVE_: rcall   DOUSER
        .dw     ursave


; SSAVE   -- a-addr     Saved parameter stack pointer
        fdw     RSAVE_L
SSAVE_L:
        .db     NFA|5,"ssave"
SSAVE_: rcall   DOUSER
        .dw     ussave


; ULINK   -- a-addr     link to next task
        fdw     SSAVE_L
ULINK_L:
        .db     NFA|5,"ulink"
ULINK_: rcall   DOUSER
        .dw     ulink


; TASK       -- a-addr              TASK pointer
        fdw     ULINK_L
.else
        fdw     BIN_L
.endif
TASK_L:
        .db     NFA|4,"task",0
TASK:   rcall   DOUSER
        .dw     utask


; HP       -- a-addr                HOLD pointer
        fdw     TASK_L
HP_L:
        .db     NFA|2,"hp",0
HP:     rcall   DOUSER
        .dw     uhp

; PAD     -- a-addr        User Pad buffer
        fdw     HP_L
PAD_L:
        .db     NFA|3,"pad"
PAD:
        rcall   TIB
        rcall   TIBSIZE
        jmp     PLUS

; BASE    -- a-addr       holds conversion radix
        fdw     PAD_L
BASE_L:
        .db     NFA|4,"base",0
BASE:
        rcall   DOUSER
        .dw     ubase

; USER   n --
        fdw     BASE_L
USER_L:
        .db     NFA|4,"user",0
USER:
        rcall   CONSTANT_
        rcall   XDOES
DOUSER:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        lpm_    tosl, z+
        lpm_    tosh, z+
        add     tosl, upl
        adc     tosh, uph
        ret

; SOURCE   -- adr n         current input buffer
;   'SOURCE 2@ ;        length is at higher adrs
        fdw     USER_L
SOURCE_L:
        .db     NFA|6,"source",0
SOURCE:
        rcall   TICKSOURCE
        jmp     TWOFETCH


; /STRING  a u n -- a+n u-n          trim string
;   swap over - >r + r>
        fdw      SOURCE_L
SLASHSTRING_L:
        .db     NFA|7,"/string"
SLASHSTRING:
        rcall   SWOP
        rcall   OVER
        rcall   MINUS
        rcall   TOR
        rcall   PLUS
        rcall   RFROM
        ret

; \     Skip the rest of the line
        fdw     SLASHSTRING_L
BSLASH_L:
        .db     NFA|IMMED|1,0x5c
BSLASH:
        rcall   SOURCE
        rcall   TOIN
        rcall   STORE_A
        sbr     FLAGS1, (1<<noclear)  ; dont clear flags in case of \
        jmp     DROP

; PARSE  char -- c-addr u
        fdw     BSLASH_L
PARSE_L:
        .db     NFA|5,"parse"
PARSE:
        rcall   DUP             ; c c
        rcall   SOURCE          ; c c a u
        rcall   TOIN            ; c c a u a
        rcall   FETCH_A         ; c c a u n
        rcall   SLASHSTRING     ; c c a u   new tib addr/len
        rcall   DUP             ; c c a u u
        rcall   TOR             ; c c a u                  R: u (new tib len
        rcall   ROT             ; c a u c
        rcall   SKIP            ; c a u        
        rcall   OVER            ; c a u a
        rcall   TOR             ; c a u                    R: u a (start of word
        rcall   ROT             ; a u c
        rcall   SCAN            ; a u      end of word, tib left       
        rcall   DUPZEROSENSE
        breq    PARSE1
        rcall   ONEMINUS
PARSE1: rcall   RFROM           ; a u a
        rcall   RFROM           ; a u a u
        rcall   ROT             ; a a u u
        rcall   MINUS           ; a a n  ( addition to toin
        rcall   TOIN
        rcall   PLUSSTORE       ; aend astart
        rcall   TUCK            ; astart aend astart
        jmp     MINUS           ; astart wlen
     

; WORD   char -- c-addr        word delimited by char and/or TAB
        fdw     PARSE_L
WORD_L:
        .db     NFA|4,"word",0
WORD:
        rcall   PARSE           ; c-addr wlen
        rcall   SWOP
        rcall   ONEMINUS
        rcall   TUCK
        jmp     CSTORE          ; Write the length into the TIB ! 

; CMOVE  src dst u --  copy u bytes from src to dst
; cmove swap !p for c@+ pc! p+ next drop ;
        fdw     WORD_L
CMOVE_L:
        .db     NFA|5,"cmove"
CMOVE:
        rcall   SWOP
        rcall   STORE_P_TO_R
        rcall   TOR
        rjmp    CMOVE2
CMOVE1:
        rcall   CFETCHPP
        rcall   PCSTORE
        rcall   PPLUS
CMOVE2:
        rcall   XNEXT
        brcc    CMOVE1
        pop     t1
        pop     t0
        rcall   R_TO_P
        jmp     DROP


; place  src n dst --     place as counted str
        fdw     CMOVE_L
PLACE_L:
        .db     NFA|5,"place"
PLACE: 
        rcall   TWODUP
        rcall   CSTORE_A
        rcall   CHARPLUS
        rcall   SWOP
        jmp     CMOVE

; :     c@+ ( addr -- addr+1 n ) dup 1+ swap c@ ;
        fdw     PLACE_L
CFETCHPP_L:
        .db     NFA|3,"c@+"
CFETCHPP:
        rcall   DUP
        rcall   ONEPLUS
        rcall   SWOP
        jmp     CFETCH

; :     @+ ( addr -- addr+2 n ) dup 2+ swap @ ;
        fdw     CFETCHPP_L
FETCHPP_L:
        .db     NFA|2,"@+",0
FETCHPP:
        rcall   DUP
        rcall   TWOPLUS
        rcall   SWOP
        jmp     FETCH

        .db     NFA|1,"!"
STORE_A:        
        jmp     STORE

; N>C   nfa -- cfa    name adr -> code field
        fdw    FETCHPP_L
NTOC_L:
        .db     NFA|3,"n>c"
NFATOCFA:
        rcall   CFETCHPP
        rcall   DOLIT
        .dw     0x0f
        rcall   AND_
        rcall   PLUS
        jmp     ALIGNED

; C>N   cfa -- nfa    code field addr -> name field addr
        fdw    NTOC_L
CTON_L:
        .db     NFA|3,"c>n"
CFATONFA:
        rcall   TWOMINUS
        rcall   DUP
        rcall   CFETCH_A
        rcall   DOLIT
        .dw     0x007F
        rcall   GREATER
        rcall   ZEROSENSE
        breq    CFATONFA
        ret

; findi   c-addr nfa -- c-addr 0   if not found
;                          xt  1      if immediate
;                          xt -1      if "normal"
        fdw     CTON_L
BRACFIND_L:
        .db     NFA|3,"(f)"
findi:
findi1:
FIND_1: 
        rcall   TWODUP
;        rcall   OVER
;        rcall   CFETCH_A
        rcall   NEQUAL
        rcall   DUPZEROSENSE
        breq    findi2
        rcall   DROP
        rcall   TWOMINUS ;;;      NFATOLFA
        rcall   FETCH_A
        rcall   DUP
findi2:
        rcall   ZEROSENSE
        brne    findi1
        rcall   DUPZEROSENSE
        breq    findi3
        rcall   NIP
        rcall   DUP
        rcall   NFATOCFA
        rcall   SWOP
        rcall   IMMEDQ
        rcall   ZEROEQUAL
        rcall   ONE
        rcall   OR_
findi3: 
        ret
;        jmp     PAUSE

; IMMED?    nfa -- f        fetch immediate flag
        fdw     BRACFIND_L
IMMEDQ_L:
        .db     NFA|6,"immed?",0
IMMEDQ: 
        rcall   CFETCH_A
        mov     wflags, tosl  ; COMPILE and INLINE flags for the compiler
        rcall   DOLIT
        .dw     IMMED
        jmp     AND_

; FIND   c-addr -- c-addr 0   if not found
;                  xt  1      if immediate
;                  xt -1      if "normal"
        fdw     IMMEDQ_L
FIND_L:
        .db     NFA|4,"find",0
FIND:   
        rcall   DOLIT
        fdw     kernellink
        rcall   findi
        rcall   DUPZEROSENSE
        brne    FIND1
        rcall   DROP
        rcall   LATEST_
        rcall   FETCH_A
        rcall   findi
FIND1:
        ret

; DIGIT?   c -- n -1   if c is a valid digit
        fdw     FIND_L
DIGITQ_L:
        .db     NFA|6,"digit?",0
DIGITQ:
                                ; 1 = 31    A = 41
        rcall   DUP             ; c c       c c
        rcall   DOLIT
        .dw     0x39            ; c c 39    c c 39
        rcall   GREATER         ; c 0       c ffff
        rcall   ZEROSENSE
        breq    DIGITQ1
        rcall   DOLIT
        .dw     0x27
        rcall   MINUS
DIGITQ1:        
        rcall   DOLIT
        .dw     0x30            ; c 30
        rcall   MINUS           ; 1
        rcall   DUP             ; 1 1
        rcall   BASE            ; 1 1 base
        rcall   FETCH_A         ; 1 1 10
        rcall   LESS            ; 1 ffff
        rcall   OVER            ; 1 ffff 1
        rcall   ZEROLESS        ; 1 ffff 0
        rcall   INVERT
        jmp     AND_

; SIGN?   adr n -- adr' n' f   get optional sign
; + leaves $0000 flag
; - leaves $0002 flag
        fdw     DIGITQ_L
SIGNQ_L:
        .db     NFA|5,"sign?"
SIGNQ:
        rcall   OVER
        rcall   CFETCH_A
        rcall   DOLIT
        .dw     ','
        rcall   MINUS
        rcall   DUP
        rcall   ABS_
        rcall   ONE
        rcall   EQUAL
        rcall   AND_
        rcall   DUPZEROSENSE
        breq    QSIGN1
        rcall   ONEPLUS
        rcall   TOR
        rcall   ONE
        rcall   SLASHSTRING
        rcall   RFROM
QSIGN1: ret

; UD*  ud u -- ud
        fdw     SIGNQ_L
UDSTAR_L:
        .db     NFA|3,"ud*"
UDSTAR:
        rcall   DUP
        rcall   TOR
        rcall   UMSTAR
        rcall   DROP
        rcall   SWOP
        rcall   RFROM
        rcall   UMSTAR
        rcall   ROT
        jmp     PLUS
        
; UD/MOD  ud u --u(rem) ud(quot)
        fdw     UDSTAR_L
UDSLASHMOD_L:
        .db     NFA|6,"ud/mod",0
UDSLASHMOD:
        rcall   TOR             ; ud.l ud.h 
        rcall   FALSE_          ; ud.l ud.h 0
        rcall   RFETCH          ; ud.l ud.h 0 u
        rcall   UMSLASHMOD      ; ud.l r.h q.h
        rcall   ROT             ; r.h q.h ud.l
        rcall   ROT             ; q.h ud.l r.h
        rcall   RFROM           ; q.h ud.l r.h u
        rcall   UMSLASHMOD      ; q.h r.l q.l
        jmp     ROT             ; r.l q.l q.h
        
; >NUMBER  0 0 adr u -- ud.l ud.h adr' u'
;                       convert string to number
        fdw     UDSLASHMOD_L
TONUMBER_L:
        .db     NFA|7,">number"
TONUMBER:
TONUM1:
        rcall   DUPZEROSENSE      ; ud.l ud.h adr u
        breq    TONUM3
        rcall   TOR
        rcall   DUP
        rcall   TOR             ; ud.l ud.h adr
        rcall   CFETCH_A
        rcall   DIGITQ          ; ud.l ud.h digit flag
        rcall   ZEROSENSE
        brne    TONUM2
        rcall   DROP
        rcall   RFROM
        rcall   RFROM
        rjmp    TONUM3
TONUM2: 
        rcall   TOR             ; ud.l ud.h digit
        rcall   BASE
        rcall   FETCH_A
        rcall   UDSTAR
        rcall   RFROM
        rcall   MPLUS
        rcall   RFROM
        rcall   RFROM
        
        rcall   ONE
        rcall   SLASHSTRING
        rjmp    TONUM1
TONUM3: 
        ret

BASEQV:   
        fdw     DECIMAL
        fdw     HEX
        fdw     BIN


; NUMBER?  c-addr -- n 1
;                 -- dl dh 2
;                 -- c-addr 0  if convert error
        fdw     TONUMBER_L
NUMBERQ_L:
        .db     NFA|7,"number?"
NUMBERQ:
        rcall   DUP             ; a a
        rcall   FALSE_          ; a a 0 0
        rcall   FALSE_          ; a a 0 0
        rcall   ROT             ; a 0 0 a
        rcall   CFETCHPP        ; a 0 0 a' u
        rcall   SIGNQ           ; a 0 0 a' u f
        rcall   TOR             ; a 0 0 a' u

        rcall   BASE
        rcall   FETCH_A
        rcall   TOR             ; a 0 0 a' u
        
        rcall   OVER
        rcall   CFETCH_A
        
        rcall   DOLIT
        .dw     '#'
        rcall   MINUS
        rcall   DUP
        rcall   DOLIT
        .dw     3
        rcall   ULESS
        rcall   ZEROSENSE
        breq    BASEQ1
        rcall   CELLS
        
        rcall   DOLIT
        fdw     BASEQV
        rcall   PLUS
        rcall   FEXECUTE

        rcall   ONE
        rcall   SLASHSTRING
        rjmp    BASEQ2
BASEQ1:
        rcall   DROP
BASEQ2:                         ; a 0 0 a' u
        rcall   TONUMBER        ; a ud.l ud.h  a' u
        rcall   RFROM           ; a ud.l ud.h  a' u oldbase
        rcall   BASE            ; a ud.l ud.h  a' u oldbase addr
        rcall   STORE_A         ; a ud.l ud.h  a' u

        rcall   DUP
        rcall   TWOMINUS
        rcall   ZEROLESS        ; a ud.l ud.h  a' u f
        rcall   ZEROSENSE       ; a ud.l ud.h  a' u
        brne    QNUMD
QNUM_ERR:                       ; Not a number
        rcall   RFROM           ; a ud.l ud.h a' u sign
        rcall   DROP
        rcall   TWODROP
QNUM_ERR1:      
        rcall   TWODROP
        rcall   FALSE_          ; a 0           Not a number
        rjmp    QNUM3
QNUMD:                          ; Double number
                                ; a ud.l ud.h a' u
        rcall   TWOSWAP         ; a a' u ud.l ud.h 
        rcall   RFROM           ; a a' u ud.l ud.d sign
        rcall   ZEROSENSE
        breq    QNUMD1
        rcall   DNEGATE
QNUMD1: 
        rcall   TWOSWAP         ; a d.l d.h a' u
        rcall   ZEROSENSE       ; a d.l d.h a'
        breq    QNUM1
        call    CFETCH
        rcall   DOLIT
        .dw     '.'
        rcall   MINUS
        rcall   ZEROSENSE       ; a d.l d.h
        brne    QNUM_ERR1
        rcall   ROT             ; d.l d.h a
        rcall   DROP            ; d.l d.h
        rcall   DOLIT         ; 
        .dw     2               ; d.l ud.h 2    Double number
        rjmp    QNUM3
QNUM1:                          ; single precision dumber
                                ; a ud.l ud.h  a'
        rcall   TWODROP         ; a n
        rcall   NIP             ; n
        rcall   ONE             ; n 1           Single number
QNUM3:  
        ret


        .db     NFA|4,"swap",0
SWOP_A:
        jmp     SWOP

; TI#  -- n                      size of TIB
; : ti# task @ 8 + @ ;
        fdw     NUMBERQ_L
TIBSIZE_L:
        .db     NFA|3,"ti#"
TIBSIZE:
        rcall   TASK
        rcall   FETCH_A
        adiw    tosl, 5
        jmp     CFETCH

; TIB     -- a-addr        Terminal Input Buffer
        fdw     TIBSIZE_L
TIB_L:
        .db     NFA|3,"tib"
TIB:
        rcall   TIU
        jmp     FETCH
        
; TIU     -- a-addr        Terminal Input Buffer user variable 
        fdw     TIB_L
TIU_L:
        .db     NFA|3,"tiu"
TIU:
        rcall   DOUSER
        .dw     utib       ; pointer to Terminal input buffer

; >IN     -- a-addr        holds offset into TIB
; In RAM
        fdw     TIU_L
TOIN_L:
        .db     NFA|3,">in"
TOIN:
        rcall   DOUSER
        .dw     utoin

; 'SOURCE  -- a-addr        two cells: len, adrs
; In RAM ?
        fdw     TOIN_L
TICKSOURCE_L:
        .db     NFA|7,"'source"
TICKSOURCE:
        rcall   DOUSER
        .dw     usource       ; two cells !!!!!!

;  INTERPRET  c-addr u --    interpret given buffer
        fdw     TICKSOURCE_L
INTERPRET_L:
        .db     NFA|9,"interpret"
INTERPRET: 
        rcall   TICKSOURCE
        rcall   TWOSTORE
        rcall   FALSE_
        rcall   TOIN
        rcall   STORE_A
IPARSEWORD:
        rcall   BL
        rcall   WORD

        rcall   DUP
        rcall   CFETCH_A
        rcall   ZEROSENSE
        brne    IPARSEWORD1
        rjmp    INOWORD
IPARSEWORD1:
        rcall   FIND            ; sets also wflags
        rcall   DUPZEROSENSE    ; 0 = not found, -1 = normal, 1 = immediate
        breq    INUMBER         ; NUMBER?
        rcall   ONEPLUS         ; 0 = normal 2 = immediate
        rcall   STATE_
        rcall   ZEROEQUAL
        rcall   OR_
        rcall   ZEROSENSE
        breq    ICOMPILE_1      ; Compile a word
        
                                ; Execute a word
                                ; immediate&compiling or interpreting
        sbrs    wflags, 4       ; Compile only check
        rjmp    IEXECUTE        ; Not a compile only word
        rcall   STATE_          ; Compile only word check
        rcall   XSQUOTE
        .db     3,"CO?"
        rcall   QABORT
IEXECUTE:
        cbr     FLAGS1, (1<<noclear)
        rcall   EXECUTE
        sbrc    FLAGS1, noclear ;  set by \ and by (
        rjmp    IPARSEWORD
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        rjmp    IPARSEWORD
ICOMPILE_1:
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        rcall   DUP
        rcall   DOLIT
        fdw     ZEROEQUAL       ; Check for 0=, modifies IF and UNTIL to use bnz
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ICOMPILE_2
        sbr     FLAGS1, (1<<izeroeq) ; Mark 0= encountered in compilation
        rjmp    ICOMMAXT
ICOMPILE_2:
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        rcall   DUP
        rcall   DOLIT
        fdw     DUP             ; Check for DUP, modies IF and UNTIl to use DUPZEROSENSE
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ICOMPILE
        sbr     FLAGS1, (1<<idup)    ; Mark DUP encountered during compilation
ICOMPILE:
        sbrs    wflags, 5       ; Inline check
        rjmp    ICOMMAXT
        call    INLINE0
        rjmp    IPARSEWORD
ICOMMAXT:
        rcall   COMMAXT_A
        cbr     FLAGS1, (1<<fTAILC)  ; Allow tailjmp  optimisation
        sbrc    wflags, 4            ; Compile only ?
        sbr     FLAGS1, (1<<fTAILC)  ; Prevent tailjmp  optimisation
        rjmp    IPARSEWORD
INUMBER: 
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        rcall   DROP
        rcall   NUMBERQ
        rcall   DUPZEROSENSE
        breq    IUNKNOWN
        rcall   STATE_
        rcall   ZEROSENSE
        breq    INUMBER1
        mov     t0, tosl
        poptos
        sbrs    t0, 1
        rjmp    ISINGLE
IDOUBLE:
        rcall   SWOP_A
        rcall   LITERAL
ISINGLE:        
        rcall   LITERAL
        rjmp    IPARSEWORD

INUMBER1:
        rcall   DROP
        rjmp    IPARSEWORD

IUNKNOWN:
        rcall   DROP 
        rcall   DP_TO_RAM
        rcall   CFETCHPP
        rcall   TYPE
        rcall   FALSE_
        rcall   QABORTQ         ; Never returns & resets the stacks
INOWORD: 
        jmp     DROP

        .db     NFA|1,"@"
FETCH_A:        
        jmp     FETCH

;;;    bitmask -- 
        fdw     INTERPRET_L
SHB_L:
        .db     NFA|3,"shb"     ; Set header bit
SHB:
        rcall   LATEST_
        rcall   FETCH_A
        rcall   DUP
        rcall   CFETCH_A
        rcall   ROT
        rcall   OR_
        rcall   SWOP_A
        jmp     CSTORE
        
        fdw     SHB_L
IMMEDIATE_L:
        .db     NFA|9,"immediate" ; 
IMMEDIATE:
        rcall   DOLIT
        .dw     IMMED
        jmp     SHB

;***************************************************************
        fdw     IMMEDIATE_L
INLINED_L:
        .db     NFA|7,"inlined" ; 
INLINED:
        rcall   DOLIT
        .dw     INLINE
        jmp     SHB

;; .st ( -- ) output a string with current data section and current base info
;;; : .st base @ dup decimal <#  [char] , hold #s  [char] < hold #> type 
;;;     <# [char] > hold cse @ #s #> type base ! ;
        fdw     INLINED_L
DOTSTATUS_L:
        .db     NFA|3,".st"
DOTSTATUS:
        rcall   DOLIT
        .dw     '<'
        rcall   EMIT
        rcall   DOTBASE
        rcall   EMIT
        rcall   DOLIT
        .dw     ','
        rcall   EMIT
        rcall   MEMQ
        rcall   TYPE
        rcall   DOLIT
        .dw     '>'
        rcall   EMIT
        jmp     DOTS

        .db     NFA|2,">r",0
TOR_A:  jmp     TOR


;;; TEN ( -- n ) Leave decimal 10 on the stack
        .db     NFA|1,"a"
TEN:
        rcall   DOCREATE
        .dw     10

; dp> ( -- ) Copy ini, dps and latest from eeprom to ram
;        .dw     link
; link    set     $
        .db     NFA|3,"dp>"
DP_TO_RAM:
        rcall   DOLIT
        .dw     dp_start
        rcall   INI
        rcall   TEN
        jmp     CMOVE

; >dp ( -- ) Copy only changed turnkey, dp's and latest from ram to eeprom
;        .dw     link
; link    set     $
        .db     NFA|3,">dp"
DP_TO_EEPROM:
        rcall   DOLIT
        .dw     dp_start
        rcall   STORE_P_TO_R
        rcall   INI
        rcall   DOLIT
        .dw     4
        rcall   TOR
DP_TO_EEPROM_0: 
        rcall   FETCHPP
        rcall   DUP
        rcall   PFETCH
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        breq    DP_TO_EEPROM_1
        rcall   PSTORE
        rjmp    DP_TO_EEPROM_2
DP_TO_EEPROM_1:
        rcall   DROP
DP_TO_EEPROM_2:
;        call    CELL
        rcall   PTWOPLUS
DP_TO_EEPROM_3:
        rcall   XNEXT
        brcc    DP_TO_EEPROM_0
        pop     t1
        pop     t0
        rcall   R_TO_P
        jmp     DROP

        fdw     DOTSTATUS_L
FALSE_L:
        .db     NFA|5,"false"
FALSE_:                     ; TOS is 0000 (FALSE)
        pushtos
        clr     tosl
        clr     tosh
        ret

        fdw     FALSE_L
TRUE_L:
        .db     NFA|4,"true",0
TRUE_:                      ; TOS is ffff (TRUE)
        pushtos
        ser     tosl
        ser     tosh
        ret

; QUIT     --    R: i*x --    interpret from kbd
        fdw     TRUE_L
QUIT_L:
        .db     NFA|4,"quit",0
QUIT:
        rcall   RPEMPTY
        rcall   LEFTBRACKET
        rcall   FRAM
QUIT0:  
        rcall   IFLUSH
        ;; Copy INI and DP's from eeprom to ram
        rcall   DP_TO_RAM
QUIT1: 
        rcall   check_sp
        rcall   CR
        rcall   TIB
        rcall   DUP
        rcall   TIBSIZE
        rcall   TEN                 ; Reserve 10 bytes for hold buffer
        rcall   MINUS
        rcall   ACCEPT
        rcall   SPACE_
        rcall   INTERPRET
        rcall   STATE_
        rcall   ZEROSENSE
        brne    QUIT1
        rcall   DP_TO_EEPROM
         
        rcall    XSQUOTE
        .db     3," ok"
        rcall    TYPE
        rcall   PROMPT_
        jmp     QUIT0

        fdw     QUIT_L
PROMPT_L:
        .db     NFA|6,"prompt",0
PROMPT_:
        call    DEFER_DOES
        .dw     prompt

; ABORT    i*x --   R: j*x --   clear stk & QUIT
        fdw     PROMPT_L
ABORT_L:
        .db     NFA|5,"abort"
ABORT:
        rcall   S0
        rcall   FETCH_A
        rcall   SPSTORE
        ;bsf     RCSTA, CREN, A
        jmp     QUIT            ; QUIT never rets

; ?ABORT   f --       abort & print ?
        fdw     ABORT_L
QABORTQ_L:
        .db     NFA|7,"?abort?"
QABORTQ:
        rcall   XSQUOTE
        .db     1,"?"
        jmp     QABORT


; ?ABORT   f c-addr u --       abort & print msg
        fdw     QABORTQ_L
QABORT_L:
        .db     NFA|6,"?abort",0
QABORT:
        rcall   ROT
        rcall   ZEROSENSE
        brne    QABO1
QABORT1:        
        rcall   SPACE_
        rcall   TYPE
        rcall   ABORT  ; ABORT never rets
QABO1:  jmp     TWODROP

; ABORT"  i*x 0  -- i*x   R: j*x -- j*x  x1=0
;         i*x x1 --       R: j*x --      x1<>0
        fdw     QABORT_L
ABORTQUOTE_L:
        .db     NFA|IMMED|COMPILE|6,"abort\"",0
ABORTQUOTE:
        rcall   SQUOTE
        rcall   DOLIT
        fdw     QABORT
        jmp     COMMAXT

;***************************************************
; LIT   -- x    fetch inline 16 bit literal to the stack

DOLIT_L:
        .db     NFA|3, "lit"
DOLIT:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        lpm_    tosl, z+
        lpm_    tosh, z+
        ror     zh
        ror     zl
        ijmp    ; (z)

; DUP must not be reachable from user code with rcall
        fdw     RFETCH_L
DUP_L:
        .db     NFA|INLINE|3, "dup"
DUP:
        pushtos
        ret

        fdw     NOTEQUAL_L
ZEROEQUAL_L:
        .db     NFA|2, "0=",0
ZEROEQUAL:      
        or      tosh, tosl
        brne    FALSE_F
TRUE_F:
        ser     tosh
        ser     tosl
ZEROEQUAL_1:
        ret

        fdw     ZEROEQUAL_L
ZEROLESS_L:
        .db     NFA|2, "0<",0
ZEROLESS:
        tst     tosh
        brmi    TRUE_F
FALSE_F:
        clr     tosh
        clr     tosl
        ret


; '    -- xt             find word in dictionary
        fdw     ABORTQUOTE_L
TICK_L:
        .db     NFA|1,0x27    ; 27h = '
TICK:
        rcall   BL
        rcall   WORD
        rcall   FIND
        jmp     QABORTQ

; CHAR   -- char           parse ASCII character
        fdw     TICK_L
CHAR_L:
        .db     NFA|4,"char",0
CHAR:
        rcall   BL
        rcall   PARSE
        rcall   DROP
        jmp     CFETCH

; (    --                     skip input until )
        fdw     CHAR_L
PAREN_L:
        .db     NFA|IMMED|1,"("
PAREN:
        rcall   DOLIT
        .dw     ')'
        rcall   PARSE
        sbr     FLAGS1, (1<<noclear) ; dont clear flags in case of (
        jmp     TWODROP

; IHERE    -- a-addr    ret Code dictionary ptr
;   IDP @ ;
;;;         .dw     link
;;; link    set     $
        .db     NFA|5,"ihere"
IHERE:
        rcall   IDP
        rjmp    FETCH_A

; [CHAR]   --          compile character DOLITeral
        fdw     PAREN_L
BRACCHAR_L:
        .db     NFA|IMMED|COMPILE|6,"[char]",0
BRACCHAR:
        rcall   CHAR
        jmp     LITERAL

; COMPILE,  xt --         append codefield
        .db     NFA|3,"cf,"
COMMAXT_A:
        jmp     COMMAXT

; CR      --                      output newline
        fdw     BRACCHAR_L
CR_L:
        .db     NFA|2,"cr",0
CR:
        rcall   DOLIT
        .dw     0x0d       ; CR \r
        rcall   EMIT
        rcall   DOLIT
        .dw     0x0a       ; LF \n
        jmp     EMIT

; CREATE   --         create an empty definition
; Create a definition header and append 
; doCREATE and the current data space dictionary pointer
; in FLASH.
;  Examples :   
; : table create 10 cells allot does> swap cells + ;
; ram table table_a     flash table table_b    eeprom table table_c
; ram variable  qqq
; eeprom variable www ram
; flash variable  rrr ram 
; eeprom create calibrationtable 30 allot ram
; 
        fdw     CR_L
CREATE_L:
        .db     NFA|6,"create",0
CREATE:
        rcall   BL
        rcall   WORD            ; Parse a word

        rcall   DUP             ; Remember parsed word at rhere
        rcall   FIND
        rcall   NIP
        rcall   ZEROEQUAL
        rcall   QABORTQ         ; ABORT if word has already been defined
        rcall   DUP             ; Check the word length 
        rcall   CFETCH_A
        rcall   ONE
        rcall   DOLIT
        .dw     16
        rcall   WITHIN
        rcall   QABORTQ          ; Abort if there is no name for create

        rcall   LATEST_
        rcall   FETCH_A
        rcall   ICOMMA          ; Link field
        rcall   CFETCHPP        ; str len
        rcall   IHERE
        rcall   DUP             
        rcall   LATEST_         ; new 'latest' link
        rcall   STORE_A         ; str len ihere
        rcall   PLACE           ; 
        rcall   IHERE           ; ihere
        rcall   CFETCH_A
        rcall   DOLIT
        .dw     NFA
        rcall   SHB
        rcall   ONEPLUS
        rcall   ALIGNED
        rcall   IALLOT          ; The header has now been created
        rcall   DOLIT             
        fdw     DOCREATE        ; compiles the runtime routine to fetch the next dictionary cell to the parameter stack
        rcall   STORECFF1       ; Append an exeution token, CALL !
        rcall   ALIGN
        rcall   HERE            ; compiles the current dataspace dp into the dictionary
        rcall   CSE_
        rcall   ZEROSENSE
        brne    CREATE2
        rcall   TWOPLUS
CREATE2:
        jmp     ICOMMA          ; dp now points to a free cell

;***************************************************************
; POSTPONE
        fdw    CREATE_L
POSTPONE_L:
        .db     NFA|IMMED|COMPILE|8,"postpone",0
POSTPONE:
        rcall   BL
        rcall   WORD
        rcall   FIND
        rcall   DUP
        rcall   QABORTQ
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    POSTPONE1
        rcall   LITERAL
        rcall   DOLIT
        fdw     COMMAXT
POSTPONE1:
        jmp    COMMAXT


IDP_L:
        .db     NFA|3,"idp"
IDP:
        rcall   DOCREATE
        .dw     dpFLASH

;***************************************************************
; (DOES>)  --      run-time action of DOES>
;        .dw    link
;link   set     $
        .db     NFA|7,"(does>)"
XDOES:
        rcall   RFROM
        rcall   LATEST_
        rcall   FETCH_A
        rcall   NFATOCFA
        rcall   IDP
        rcall   FETCH_A
        rcall   TOR_A
        rcall   IDP
        rcall   STORE_A
        lsl     tosl
        rol     tosh
        rcall   STORECFF1 ; Always stores a 4 byte call
        rcall   RFROM
        rcall   IDP
        jmp     STORE


; DOES>    --      change action of latest def'n
        fdw     POSTPONE_L
DOES_L:
        .db     NFA|IMMED|COMPILE|5,"does>"
DOES:   rcall   DOLIT
        fdw     XDOES
        rcall   COMMAXT_A
        rcall   DOLIT
        fdw     DODOES
        jmp     COMMAXT


;*****************************************************************
; [        --      enter interpretive state
        fdw     DOES_L
LEFTBRACKET_L:
        .db     NFA|IMMED|1,"["
LEFTBRACKET:
        cbr     t0, 0xff
        sts     state, t0
        ret


; ]        --      enter compiling state
        fdw     LEFTBRACKET_L
RIGHTBRACKET_L:
        .db     NFA|1,"]"
RIGHTBRACKET:
        sbr     t0, 0xff
        sts     state, t0
        ret

; :        --           begin a colon definition
        fdw     RIGHTBRACKET_L
COLON_L:
        .db     NFA|1,":"
COLON:
        rcall   CREATE
        rcall   RIGHTBRACKET
        jmp     STORCOLON

; :noname        -- a          define headerless forth code
        fdw     COLON_L
NONAME_L:
        .db     NFA|7,":noname"
NONAME:
        rcall   IHERE
        jmp     RIGHTBRACKET

; ;        --             end a colon definition
        fdw     NONAME_L
SEMICOLON_L:
        .db     NFA|IMMED|COMPILE|1,";"
SEMICOLON:
        rcall   LEFTBRACKET
        sbrc    FLAGS1, fTAILC
        rjmp    ADD_RETURN_1
        rcall   IHERE
        rcall   MINUS_FETCH
        movw    t0, tosl
        andi    t1, 0xf0
        subi    t1, 0xd0
        breq    RCALL_TO_JMP
        poptos
        rcall   MINUS_FETCH
        subi    tosl, 0x0e
        sbci    tosh, 0x94
        brne    ADD_RETURN
CALL_TO_JMP:
        ldi     tosl, 0x0c
        ldi     tosh, 0x94
        rcall   SWOP
        jmp     STORE
RCALL_TO_JMP:
        rcall   NIP
        andi    tosh, 0x0f
        sbrc    tosh, 3
        ori     tosh, 0xf0
        rcall   TWOSTAR
        rcall   IHERE
        rcall   PLUS
        rcall   DOLIT
        .dw     -2
        rcall   IALLOT
        rcall   DOLIT
        .dw     0x940c      ; jmp:0x940c
        call    ICOMMA
        sub_pflash_tos
        rampv_to_c
        ror     tosh
        ror     tosl
        jmp     ICOMMA
ADD_RETURN:
        rcall   TWODROP
ADD_RETURN_1:
        rcall   DOLIT   ; Compile a ret
        .dw     0x9508
        jmp    ICOMMA



        fdw     SEMICOLON_L
MINUS_FETCH_L:
        .db     NFA|2,"-@",0
MINUS_FETCH:
        rcall   TWOMINUS
        rcall   DUP
        jmp     FETCH

; [']  --         find word & compile as DOLITeral
        fdw     MINUS_FETCH_L
BRACTICK_L:
        .db     NFA|IMMED|COMPILE|3,"[']"
BRACTICK:
        rcall   TICK       ; get xt of 'xxx'
        jmp     LITERAL

; 2-    n -- n-2
        fdw     BRACTICK_L
TWOMINUS_L:
        .db     NFA|INLINE|2,"2-",0
TWOMINUS:
        sbiw    tosl, 2
        ret

        
; BL      -- char                 an ASCII space
        fdw     TWOMINUS_L
BL_l:
        .db     NFA|2,"bl",0
BL:
        rcall   DOCREATE
        .dw     ' '

; STATE   -- flag                 holds compiler state
        fdw     BL_L
STATE_L:
        .db     NFA|5,"state"
STATE_:
        pushtos
        lds     tosl, state
        lds     tosh, state
        ret

; LATEST    -- a-addr           
        fdw     STATE_L
LATEST_L:
        .db     NFA|6,"latest",0
LATEST_:
        rcall   DOCREATE
        .dw     dpLATEST

; S0       -- a-addr      start of parameter stack
        fdw     LATEST_L
S0_L:
        .db     NFA|2,"s0",0
S0:
        rcall   DOUSER
        .dw     us0
        
; R0       -- a-addr      start of parameter stack
        fdw     S0_L
R0_L:
        .db     NFA|2,"r0",0
R0_:
        rcall   DOUSER
        .dw     ur0
        
; ini -- a-addr       ini variable contains the user-start xt
; In RAM
;        .dw     link
;link    set     $
        .db     NFA|3,"ini"
INI:
        rcall   DOCREATE
        .dw     dpSTART

; ticks  -- u      system ticks (0-ffff) in milliseconds
        fdw     R0_L
TICKS_L:
        .db     NFA|5,"ticks"
TICKS:
        pushtos
        in      t2, SREG
        cli
        lds     tosl, ms_count
        lds     tosh, ms_count+1
        out     SREG, t2
        ret

        
; ms  +n --      Pause for n millisconds
; : ms ( +n -- )     
;   ticks -
;   begin
;     pause dup ticks - 0<
;   until drop ;
;
        fdw     TICKS_L
MS_L:
        .db     NFA|2,"ms",0
MS:
        rcall   TICKS
        rcall   PLUS
MS1:
        call    IDLE    
        rcall   PAUSE
        rcall   DUP
        rcall   TICKS
        rcall   MINUS
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    MS1
        call    BUSY
        jmp     DROP

;  .id ( nfa -- ) 
        fdw     MS_L
DOTID_L:
        .db     NFA|3,".id"
DOTID:
        rcall   CFETCHPP
        rcall   DOLIT
        .dw     0x0f
        rcall   AND_
        rcall   TOR
        rjmp    DOTID3
DOTID1:
        rcall   CFETCHPP
        rcall   TO_PRINTABLE
        call    EMIT
DOTID3:
        rcall   XNEXT
        brcc    DOTID1  
        pop     t1
        pop     t0
        jmp     DROP

 ; >pr   c -- c      Filter a character to printable 7-bit ASCII
        fdw     DOTID_L
TO_PRINTABLE_L:
        .db     NFA|3,">pr"
TO_PRINTABLE:   
        cpi     tosl, 0
        brmi    TO_PRINTABLE1
        cpi     tosl, 0x1f
        brpl    TO_PRINTABLE2
TO_PRINTABLE1:
        ldi     tosl, '.'
TO_PRINTABLE2:
        ret

 ; WORDS    --          list all words in dict.
        fdw     TO_PRINTABLE_L
WORDS_L:
        .db     NFA|5,"words"
        rcall   FALSE_
        rcall   CR
        rcall   LATEST_
        rcall   FETCH_A
        rcall   WDS1
        rcall   FALSE_
        rcall   CR
        rcall   DOLIT
        fdw     kernellink
WDS1:   rcall   DUP
        rcall   DOTID
        rcall   SWOP_A
        rcall   ONEPLUS
        rcall   DUP
        rcall   DOLIT
        .dw     7
        rcall   AND_
        rcall   ZEROSENSE
        breq    WDS2
        rcall   DOLIT
        .dw     9
        call    EMIT
        rjmp    WDS3
WDS2:   
        rcall   CR
WDS3:
        rcall   SWOP_A

        rcall   TWOMINUS
        rcall   FETCH_A
        rcall   DUPZEROSENSE
        brne    WDS1
        jmp     TWODROP

; .S      --           print stack contents
; : .s space sp@ s0 @ 2- begin 2dup < while -@ u. repeat 2drop ;
        fdw     WORDS_L
DOTS_L:
        .db     NFA|2,".s",0
DOTS:
        rcall   SPACE_
        rcall   DUP          ; push tosl:tosh to memory
        call    SPFETCH
        rcall   S0
        rcall   FETCH_A
        rcall   TWOMINUS
DOTS1:
        rcall   TWODUP
        rcall   LESS
        rcall   ZEROSENSE
        breq    DOTS2
        rcall   MINUS_FETCH
        rcall   UDOT
        rjmp    DOTS1
DOTS2:  
        rcall   DROP
        jmp     TWODROP

;   DUMP  ADDR U --       DISPLAY MEMORY
        fdw     DOTS_L
DUMP_L:
        .db     NFA|4,"dump",0
DUMP:
        rcall   DOLIT
        .dw     16
        rcall   USLASH
        rcall   TOR
        rjmp    DUMP7
DUMP1:  
        rcall   CR
        rcall   DUP
        rcall   DOLIT
        .dw     4
        rcall   UDOTR
        rcall   DOLIT
        .dw     ':'
        call    EMIT
        rcall   DOLIT
        .dw     15
        rcall   TOR
DUMP2:
        rcall   CFETCHPP
        rcall   DOLIT
        .dw     2
        rcall   UDOTR
        rcall   XNEXT
        brcc    DUMP2
        pop     t1
        pop     t0

        rcall   DOLIT
        .dw     16
        rcall   MINUS
        rcall   DOLIT
        .dw     15
        rcall   TOR
DUMP4:  
        rcall    CFETCHPP
        rcall   TO_PRINTABLE
        call    EMIT
        rcall   XNEXT
        brcc    DUMP4
        pop     t1
        pop     t0
DUMP7:
        rcall   XNEXT
        brcc    DUMP1
        pop     t1
        pop     t0
        jmp     DROP

; IALLOT   n --    allocate n bytes in ROM
;       .dw     link
;link   set     $
        .db     NFA|1," "
IALLOT:
        rcall   IDP
        jmp     PLUSSTORE
    

;***************************************************************
        fdw     DUMP_L
TO_XA_L:
        .db     NFA|3,">xa"
TO_XA:
        sub_pflash_tos
        rampv_to_c
        ror     tosh
        ror     tosl
        mov     t0, tosh
        mov     tosh, tosl
        mov     tosl, t0
        ret

        fdw     TO_XA_L
XA_FROM_L:
        .db     NFA|3,"xa>"
XA_FROM:
        mov     t0, tosh
        mov     tosh, tosl
        mov     tosl, t0
        lsl     tosl
        rol     tosh
        add_pflash_tos
        ret

;***************************************************************
; check that the relative address is within reach of conditional branch
; instructions and leave the clipped relative address on the stack
; br?   ( rel-addr limit -- clipped-rel-addr)
;       2dup 2/ swap
;       abs > (qabort)
;       and 2/ ;
.if 0
        fdw     XA_FROM_L
BRQ_L:
        .db     NFA|3,"br?"
BRQ:
        rcall   TWODUP
        rcall   TWOSLASH
        rcall   SWOP_A          ; rel-addr limit limit' rel-addr
        rcall   ABS_            ; rel-addr limit limit' rel-addr
        rcall   GREATER
        rcall   XSQUOTE
        .db      3,"BR?"
        rcall   QABORT         ;  ?RANGE ABORT if TRUE
BRQ1:
        rcall   AND_
        jmp     TWOSLASH
.endif
; ,?0=    -- addr  Compile ?0= and make make place for a branch instruction
        .db     NFA|4,",?0=",0    ; Just for see to work !
COMMAZEROSENSE:
        sbrc    FLAGS1, idup
        rjmp    COMMAZEROSENSE1
        rcall   DOLIT
        fdw     ZEROSENSE
        rjmp    COMMAZEROSENSE2
COMMAZEROSENSE1:
        rcall   IDPMINUS
        rcall   DOLIT
        fdw     DUPZEROSENSE
COMMAZEROSENSE2:
        cbr     FLAGS1, (1<<idup)
        rjmp    INLINE0

IDPMINUS:
        rcall   DOLIT
        .dw     -4
        rjmp    IALLOT

;       rjmp, ( rel-addr -- )
RJMPC:
        rcall   TWOSLASH
;        rcall   DOLIT
;        .dw     0x0FFF
;        rcall   AND_
;        rcall   DOLIT
;        .dw     0xc000
;        rcall   OR_
        andi    tosh, 0x0f
        ori     tosh, 0xc0
        jmp     ICOMMA


BRCCC:
        rcall   DOLIT
        .dw     0xf008      ; brcc pc+2
        jmp     ICOMMA
;BREQC:
;        rcall   DOLIT
;        .dw     0xf009      ; breq pc+2
;        sbrc    FLAGS1, izeroeq
;        ori     tosh, 4     ; brne pc+2
;        jmp     ICOMMA
BRNEC:
        rcall   DOLIT
        .dw     0xf409      ; brne pc+2
        sbrc    FLAGS1, izeroeq
        andi    tosh, ~4
        jmp     ICOMMA

; IF       -- adrs   conditional forward branch
; Leaves address of branch instruction 
; and compiles the condition byte
        fdw     XA_FROM_L
IF_L:
        .db     NFA|IMMED|COMPILE|2,"if",0
IF_:
        sbrc    FLAGS1, izeroeq
        rcall   IDPMINUS
        rcall   COMMAZEROSENSE
        rcall   BRNEC
        cbr     FLAGS1, (1<<izeroeq)
        rcall   IHERE
        rcall   FALSE_
        jmp     RJMPC           ; Dummy, replaced by THEN with rjmp 

; ELSE     adrs1 -- adrs2    branch for IF..ELSE
; Leave adrs2 of bra instruction and store bz in adrs1
; Leave adress of branch instruction and FALSE flag on stack
        fdw     IF_L
ELSE_L:
        .db     NFA|IMMED|COMPILE|4,"else",0
ELSE_:
        rcall   IHERE
        rcall   FALSE_
        rcall   RJMPC
        rcall   SWOP_A      ; else-addr  if-addr 
        jmp     THEN_

; THEN     adrs  --        resolve forward branch
        fdw     ELSE_L
THEN_L:
        .db     NFA|IMMED|COMPILE|4,"then",0
THEN_:
        sbr     FLAGS1, (1<<fTAILC)  ; Prevent tailjmp  optimisation
        rcall   IHERE
        rcall   OVER
        rcall   MINUS
        rcall   TWOMINUS
        rcall   TWOSLASH
        rcall   DOLIT
        .dw     0xc000      ;  back-addr mask 
        rcall   OR_
        rcall   SWOP_A
        jmp     STORE

; BEGIN    -- adrs        target for bwd. branch
        fdw     THEN_L
BEGIN_L:
        .db     NFA|IMMED|COMPILE|5,"begin"
BEGIN:
        jmp     IHERE

; UNTIL    adrs --   Branch bakwards if true
        fdw     BEGIN_L
UNTIL_L:
        .db     NFA|IMMED|COMPILE|5,"until"
UNTIL:
;        sbr     FLAGS1, (1<<fTAILC)  ; Prevent tailjmp  optimisation
        sbrc    FLAGS1, izeroeq
        rcall   IDPMINUS
        rcall   COMMAZEROSENSE
        rcall   BRNEC
        cbr     FLAGS1, (1<<izeroeq)
UNTIL1:
        rcall   IHERE
        rcall   MINUS
        rcall   TWOMINUS
        jmp     RJMPC

; AGAIN    adrs --      uncond'l backward branch
;   unconditional backward branch
        fdw     UNTIL_L
AGAIN_L:
        .db     NFA|IMMED|COMPILE|5,"again"
AGAIN_:
        rjmp    UNTIL1

; WHILE    addr1 -- addr2 addr1         branch for WHILE loop
; addr1 : address of BEGIN
; addr2 : address where to store bz instruction
        fdw     AGAIN_L
WHILE_L:
        .db     NFA|IMMED|COMPILE|5,"while"
WHILE_:
        rcall   IF_
        jmp     SWOP

; REPEAT   addr2 addr1 --     resolve WHILE loop
        fdw     WHILE_L
REPEAT_L:
        .db     NFA|IMMED|COMPILE|6,"repeat",0
REPEAT_:
        rcall   AGAIN_
        jmp     THEN_

L_INLINE:
; in, ( addr -- ) begin @+ dup $9508 <> while i, repeat 2drop ;
        fdw      L_INLINE
L_INLINEC:
        .db      NFA|3,"in,"
INLINE0:        
        rcall   FETCHPP
        rcall   DUP
        rcall   DOLIT
        .dw     0x9508
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        breq    INLINE1
        rcall   ICOMMA
        rjmp    INLINE0
INLINE1:
        jmp     TWODROP

; FOR   -- bc-addr bra-addr
        fdw     REPEAT_L
FOR_L:
        .db     NFA|IMMED|COMPILE|3,"for"
FOR:
        rcall   DOLIT
        fdw     TOR
        rcall   COMMAXT_A
        rcall   IHERE
        rcall   FALSE_
        rcall   RJMPC
        rcall   IHERE
        jmp     SWOP

; NEXT bra-addr bc-addr --
        fdw     FOR_L
NEXT_L:
        .db     NFA|IMMED|COMPILE|4,"next", 0
NEXT:
        rcall   THEN_
        rcall   DOLIT
        fdw     XNEXT
        rcall   COMMAXT_A
        rcall   BRCCC

        rcall   UNTIL1

        rcall   DOLIT
        fdw     XNEXT1
        jmp     INLINE0
; (next) decrement top of return stack
XNEXT:  
        pop     zh
        pop     zl
        pop     xh
        pop     xl
        sbiw    xl, 1
        push    xl
        push    xh
        ijmp
        ret
XNEXT1:
        pop     t1
        pop     t0
        ret

; leave clear top of return stack
        fdw     NEXT_L
LEAVE_L:
        .db     NFA|COMPILE|5,"leave"
LEAVE:
        pop     zh
        pop     zl
        pop     t1
        pop     t0
        clr     t0
        clr     t1
        push    t0
        push    t1
        ijmp
;***************************************************
; RDROP compile a pop
        fdw      LEAVE_L
RDROP_L:
        .db      NFA|IMMED|COMPILE|5,"rdrop"
RDROP:
        rcall   DOLIT
        fdw     XNEXT1
        jmp     INLINE0
;***************************************************
        fdw     RDROP_L
STOD_L:
        .db     NFA|3,"s>d"
STOD:
        sbrs    tosh, 7
        rjmp    FALSE_
        rjmp    TRUE_
;***************************************************
        fdw     STOD_L
DNEGATE_L:
        .db     NFA|7,"dnegate"
DNEGATE:
        rcall   DINVERT
        call    ONE
        jmp     MPLUS
;***************************************************
        fdw     DNEGATE_L
QDNEGATE_L:
        .db     NFA|8,"?dnegate",0
QDNEGATE:
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    QDNEGATE1
        rcall   DNEGATE
QDNEGATE1:
        ret

;***************************************************
        fdw     QDNEGATE_L
DABS_L:
        .db     NFA|4,"dabs",0
DABS:
        rcall   DUP
        jmp     QDNEGATE
;***************************************************
        fdw     DABS_L
DPLUS_L:
        .db     NFA|2,"d+",0
DPLUS:
        ld      xl, Y+
        ld      xh, Y+
        ld      t2, Y+
        ld      t3, Y+
        ld      t0, Y+
        ld      t1, Y+
        add     xl, t0
        adc     xh, t1
        adc     tosl, t2
        adc     tosh, t3
        st      -Y, xh
        st      -Y, xl
        ret

;***************************************************
        fdw     DPLUS_L
DMINUS_L:
        .db     NFA|2,"d-",0
DMINUS:
        rcall   DNEGATE
        jmp     DPLUS
;***************************************************
        fdw     DMINUS_L
DTWOSLASH_L:
        .db     NFA|3,"d2/"
        ld      t0, y+
        ld      t1, y+
        asr     tosh
        ror     tosl
        ror     t1
        ror     t0
        st      -y, t1
        st      -y, t0
        ret
;***************************************************
        fdw     DTWOSLASH_L
DTWOSTAR_L:
        .db     NFA|3,"d2*"
        ld      t0, y+
        ld      t1, y+
        lsl     t0
        rol     t1
        rol     tosl
        rol     tosh
        st      -y, t1
        st      -y, t0
        ret
;***************************************************
        fdw     DTWOSTAR_L
DINVERT_L:
        .db     NFA|7,"dinvert"
DINVERT:
        ld      xl, y+
        ld      xh, y+
        com     xl
        com     xh
        com     tosl
        com     tosh
        st      -y, xh
        st      -y, xl
        ret
;***************************************************
        fdw     DINVERT_L
DZEROEQUAL_L:
        .db     NFA|3,"d0="
DZEROEQUAL:
        ld      xl, y+
        ld      xh, y+
        or      tosl, tosh
        or      tosl, xl
        or      tosl, xh
        brne    DZEROLESS_FALSE
DZEROEQUAL_TRUE:
        ser     tosl
        ser     tosh
        ret

;***************************************************
        fdw     DZEROEQUAL_L
DZEROLESS_L:
        .db     NFA|3,"d0<"
DZEROLESS:
        ld      xl, y+
        ld      xh, y+
        cpi     tosh, 0
        brmi    DZEROEQUAL_TRUE
DZEROLESS_FALSE:
        clr     tosl
        clr     tosh
        ret
;***************************************************
        fdw     DZEROLESS_L
DEQUAL_L:
        .db     NFA|2,"d=",0
        rcall   DMINUS
        jmp     DZEROEQUAL
;***************************************************
        fdw     DEQUAL_L
DLESS_L:
        .db     NFA|2,"d<",0
DLESS:
        rcall   DMINUS
        jmp     DZEROLESS
;***************************************************
        fdw     DLESS_L
DGREATER_L:
        .db     NFA|2,"d>",0
DGREATER:
        call    TWOSWAP
        jmp     DLESS
;***************************************************
        fdw     DGREATER_L
UDDOT_L:
        .db     NFA|3,"ud."
        rcall   LESSNUM
        rcall   NUMS
        rcall   NUMGREATER
        call    TYPE
        jmp     SPACE_
;***************************************************
        fdw     UDDOT_L
DDOT_L:
        .db     NFA|2,"d.",0
        rcall   LESSNUM
        call    DUP
        call    TOR
        rcall   DABS
        rcall   NUMS
        call    RFROM
        rcall   SIGN
        rcall   NUMGREATER
        call    TYPE
        jmp     SPACE_
;***************************************************

        fdw      DDOT_L
L_FETCH_P:
        .db      NFA|INLINE|2,"@p", 0
FETCH_P:
        pushtos
        movw    tosl, pl
        ret
;***************************************************
        fdw     L_FETCH_P
L_PCFETCH:
        .db     NFA|3,"pc@" ; ( -- c ) Fetch char from pointer
PCFETCH:
        pushtos
        movw    tosl, pl
        jmp     CFETCH
;***************************************************
        fdw      L_PCFETCH
L_PTWOPLUS:
kernellink:
        .db      NFA|INLINE|3,"p2+" ; ( n -- ) Add 2 to p
PTWOPLUS:
        add     pl, r_two
        adc     ph, zero
        ret

        fdw     WARM_L
VER_L:
        .db     NFA|3,"ver"
VER:
        call    XSQUOTE
         ;      1234567890123456789012345678901234567890
        .db 29,"FlashForth Atmega 15.1.2012",0xd,0xa
        jmp     TYPE

; ei  ( -- )    Enable interrupts
        fdw     VER_L
EI_L:
        .db     NFA|INLINE|2,"ei",0
        sei
        ret
        
; di  ( -- )    Disable interrupts
        fdw     EI_L
DI_L:
        .db     NFA|INLINE|2,"di",0
        cli
        ret
        

;***************************************************
; marker --- name
        .dw     0
L_MARKER:
lastword:
        .db     NFA|6,"marker",0
MARKER:
        call    ROM_
        rcall   CREATE
        rcall   DOLIT
        .dw     dp_start
        call    HERE
        rcall   TEN
        rcall   CMOVE
        rcall   TEN
        call    ALLOT
        call    FRAM
        rcall   XDOES
        call    DODOES
        rcall   INI
        rcall   TEN
        jmp     CMOVE


L_DOTBASE:
        .db      NFA|1," "
DOTBASE:
        rcall   BASE
        rcall   FETCH_A
        cpi     tosl, 0x10
        brne    DOTBASE1
        ldi     tosl,'$'
        rjmp    DOTBASEEND
DOTBASE1:
        cpi     tosl, 0xa
        brne    DOTBASE2
        ldi     tosl, '#'
        rjmp    DOTBASEEND
DOTBASE2:
        cpi     tosl, 0x2
        brne    DOTBASE3
        ldi     tosl, '%'
        rjmp    DOTBASEEND
DOTBASE3:
        ldi     tosl, '?'
DOTBASEEND:
        ret
;;;**************************************
;;; The USB code lib goes here in between
;;;**************************************
;FF_END_CODE code
MEMQADDR_N:
        fdw     ROM_N
        fdw     EROM_N
        fdw     FRAM_N
; M? -- caddr count    current data space string
;        dw      L_DOTBASE
L_MEMQ:
        .db     NFA|1," "
MEMQ:
        call    CSE_
        rcall   DOLIT
        fdw     MEMQADDR_N
        call    PLUS
        rcall   FETCH_A
        rcall   CFETCHPP
        rcall   DOLIT
        .dw     NFAmask
        jmp     AND_
end_of_dict:

;FF_DP code:
dpcode:
;****************************************************
;        org h'f00000'
;        de  h'ff', h'ff'
;        de  dp_user_dictionary&0xff, (dp_user_dictionary>>8)&0xff
;        de  dpeeprom&0xff, (dpeeprom>>8)&0xff
;        de  (dpdata)&0xff, ((dpdata)>>8)&0xff
;        de  lastword_lo, lastword_hi
;        de  DOTSTATUS;&0xff;, (DOTSTATUS>>8)&0xff

; .end
;********************************************************** 
.cseg
.org BOOT_START
RESET_:     jmp  WARM_
.org BOOT_START + 0x02
            rcall FF_ISR
.org BOOT_START + 0x04
            rcall FF_ISR
.org BOOT_START + 0x06
            rcall FF_ISR
.org BOOT_START + 0x08
            rcall FF_ISR
.org BOOT_START + 0x0a
            rcall FF_ISR
.org BOOT_START + 0x0c
            rcall FF_ISR
.org BOOT_START + 0x0e
            rcall FF_ISR
.org BOOT_START + 0x10
            rcall FF_ISR
.org BOOT_START + 0x12
            rcall FF_ISR
.org BOOT_START + 0x14
            rcall FF_ISR
.org BOOT_START + 0x16
            rcall FF_ISR
.org BOOT_START + 0x18
            rcall FF_ISR
.org BOOT_START + 0x1a
            rcall FF_ISR
.org BOOT_START + 0x1c
            rcall FF_ISR
.org BOOT_START + 0x1e
            rcall FF_ISR
.org BOOT_START + 0x20
            rcall FF_ISR
.org BOOT_START + 0x22
            rcall FF_ISR
.org BOOT_START + 0x24
            rcall FF_ISR
.if 0x26 < INT_VECTORS_SIZE
.org BOOT_START + 0x26
            rcall FF_ISR
.endif
.if 0x28 < INT_VECTORS_SIZE
.org BOOT_START + 0x28
            rcall FF_ISR
.endif
.if 0x2a < INT_VECTORS_SIZE
.org BOOT_START + 0x2a
            rcall FF_ISR
.endif
.if 0x2c < INT_VECTORS_SIZE
.org BOOT_START + 0x2c
            rcall FF_ISR
.endif
.if 0x2e < INT_VECTORS_SIZE
.org BOOT_START + 0x2e
            rcall FF_ISR
.endif
.if 0x30 < INT_VECTORS_SIZE
.org BOOT_START + 0x30
            rcall FF_ISR
.endif
.if 0x32 < INT_VECTORS_SIZE
.org BOOT_START + 0x32
            rcall FF_ISR
.endif
.if 0x34 < INT_VECTORS_SIZE
.org BOOT_START + 0x34
            rcall FF_ISR
.endif
.if 0x36 < INT_VECTORS_SIZE
.org BOOT_START + 0x36
            rcall FF_ISR
.endif
.if 0x38 < INT_VECTORS_SIZE
.org BOOT_START + 0x38
            rcall FF_ISR
.endif
.if 0x3a < INT_VECTORS_SIZE
.org BOOT_START + 0x3a
            rcall FF_ISR
.endif
.if 0x3c < INT_VECTORS_SIZE
.org BOOT_START + 0x3c
            rcall FF_ISR
.endif
.if 0x3e < INT_VECTORS_SIZE
.org BOOT_START + 0x3e
            rcall FF_ISR
.endif
.if 0x40 < INT_VECTORS_SIZE
.org BOOT_START + 0x40
            rcall FF_ISR
.endif
.if 0x42 < INT_VECTORS_SIZE
.org BOOT_START + 0x42
            rcall FF_ISR
.endif
.if 0x44 < INT_VECTORS_SIZE
.org BOOT_START + 0x44
            rcall FF_ISR
.endif

.org BOOT_START + INT_VECTORS_SIZE
FF_ISR_EXIT:
        pop     tosh
        pop     tosl
        pop     ph
        pop     pl
        pop     t3
        pop     t2

        pop     t1
        pop     t0
FF_ISR_EXIT2:
        pop     zh
        pop     zl
FF_ISR_EXIT3:
        ld      xl, y+
        ld      xh, y+
        out_    SREG, xh
        ld      xh, y+
        reti

TIMER1_ISR:
        ldi     xl, low(ms_value)
        ldi     xh, high(ms_value)
        out_    TCNT1H, xh
        out_    TCNT1L, xl
        lds     xl, ms_count
        lds     xh, ms_count+1
        adiw    xl, 1
        sts     ms_count, xl
        sts     ms_count+1, xh
        rjmp    FF_ISR_EXIT3

FF_ISR:
        st      -y, xh
        in_     xh, SREG
        st      -y, xh
        st      -y, xl
        pop     xh
        pop     xl

        cpi     xl, low(OVF1addr+1)
        breq    TIMER1_ISR

        push    zl
        push    zh

.ifdef URXC0addr
        cpi     xl, low(URXC0addr+1)
.else
        cpi     xl, low(URXCaddr+1)
.endif
        breq    RX0_ISR
.ifdef URXC1addr
        cpi     xl, low(URXC1addr+1)
        breq    RX1_ISR
.endif

        push    t0
        push    t1

        push    t2
        push    t3
        push    pl
        push    ph
        push    tosl
        push    tosh

        subi    xl, 1
        clr     xh
        ldi     t0, low(ivec)
        ldi     t1, high(ivec)
        add     xl, t0
        adc     xh, t1
        ld      zh, x+  ; >xa dependency !!!!
        ld      zl, x+
        ijmp    ;(z)

RX0_ISR:
        ldi     zl, low(rbuf0)
        ldi     zh, high(rbuf0)
        lds     xl, rbuf0_wr
        add     zl, xl
        adc     zh, zero
        lds     xh, UDR0
.if OPERATOR_UART == 0
        cpi     xh, 0xf
        brne    pc+2
        rjmp    RESET_
.endif
        st      z, xh
        inc     xl
        andi    xl, (RX0_BUF_SIZE-1)
        sts     rbuf0_wr, xl
        lds     xl, rbuf0_lv
        inc     xl
        sts     rbuf0_lv, xl
        cpi     xl, RX0_BUF_SIZE-2
        brne    PC+2
        rcall   RX0_OVF
        cpi     xl, RX0_OFF_FILL
        brmi    RX0_ISR_SKIP_XOFF
.if U0FC_TYPE == 1
        rcall   XXOFF_TX0_1
.endif
.if U0FC_TYPE == 2
        sbi_    U0RTS_PORT, U0RTS_BIT
.endif
RX0_ISR_SKIP_XOFF:
        rjmp    FF_ISR_EXIT2
RX0_OVF:
        ldi     zh, '|'
        rjmp    TX0_SEND
TX0_ISR:
.ifdef UDR1
RX1_ISR:
        ldi     zl, low(rbuf1)
        ldi     zh, high(rbuf1)
        lds     xl, rbuf1_wr
        add     zl, xl
        adc     zh, zero
        lds     xh, UDR1
.if OPERATOR_UART == 1
        cpi     xh, 0xf
        brne    pc+2
        rjmp    RESET_
.endif
        st      z, xh
        inc     xl
        andi    xl, (RX1_BUF_SIZE-1)
        sts     rbuf1_wr, xl
        lds     xl, rbuf1_lv
        inc     xl
        sts     rbuf1_lv, xl
        cpi     xl, RX1_BUF_SIZE-2
        brne    PC+2
        rcall   RX1_OVF
        cpi     xl, RX0_OFF_FILL
        brmi    RX1_ISR_SKIP_XOFF
.if U1FC_TYPE == 1
        rcall   XXOFF_TX1_1
.endif
.if U1FC_TYPE == 2
        sbi_    U1RTS_PORT, U1RTS_BIT
.endif
RX1_ISR_SKIP_XOFF:
        rjmp    FF_ISR_EXIT2
RX1_OVF:
        ldi     zh, '|'
        rjmp    TX1_SEND
TX1_ISR:
.endif
;;; *************************************************
;;; WARM user area data
.equ warmlitsize= 22
WARMLIT:
        .dw      0x0200                ; cse, state
        .dw      usbuf+ussize-4        ; S0
        .dw      urbuf+ursize-2        ; R0
;        fdw      OP_TX_
;        fdw      OP_RX_
;        fdw      OP_RXQ
; wired this in because didn't work with avra 
        .dw      TX0_
        .dw      RX0_
        .dw      RX0Q
        .dw      up0                   ; Task link
        .dw      BASE_DEFAULT          ; BASE
        .dw      utibbuf               ; TIB
        fdw      OPERATOR_AREA         ; TASK
        .dw      0                     ; ustatus & uflg
;;; *************************************************
;;; *************************************
;;; EMPTY dictionary data
.equ coldlitsize=12
;.section user_eedata
COLDLIT:
STARTV: .dw      0
DPC:    .dw      OFLASH
DPE:    .dw      ehere
DPD:    .dw      dpdata
LW:     fdw      lastword
STAT:   fdw      DOTSTATUS

;***************************************************
; TX0   c --    output character to UART 0
        fdw LOAD_L 
TX0_L:
        .db     NFA|3,"tx0"
TX0_:
.if U0FC_TYPE == 1
        cpi     tosl, XON
        breq    XXON_TX0_TOS
        cpi     tosl, XOFF
        breq    XXOFF_TX0_TOS
.endif
TX0_LOOP:
        rcall   PAUSE
        in_     t0, UCSR0A
        sbrs    t0, UDRE0
        rjmp    TX0_LOOP
        out_    UDR0, tosl
        poptos
        ret

.if U0FC_TYPE == 1
XXON_TX0_TOS:
        poptos
        rjmp    XXON_TX0_1
XXON_TX0:
        sbrs    FLAGS2, ixoff_tx0
        ret
XXON_TX0_1:
        cbr     FLAGS2, (1<<ixoff_tx0)
        ldi     zh, XON
        rjmp    TX0_SEND

XXOFF_TX0_TOS:
        poptos
        rjmp    XXOFF_TX0_1
XXOFF_TX0:
        sbrc    FLAGS2, ixoff_tx0
        ret     
XXOFF_TX0_1:
        sbr     FLAGS2, (1<<ixoff_tx0)
        ldi     zh, XOFF
.endif
TX0_SEND:
        in_     zl, UCSR0A
        sbrs    zl, UDRE0
        rjmp    TX0_SEND
        out_    UDR0, zh
        ret
;***************************************************
; RX0    -- c    get character from the UART 0 buffer
        fdw TX0_L 
RX0_L:
        .db     NFA|3,"rx0"
RX0_:
        rcall   PAUSE
        rcall   RX0Q
        call    ZEROSENSE
        breq    RX0_
        pushtos
        ldi     zl, low(rbuf0)
        ldi     zh, high(rbuf0)
        lds     xl, rbuf0_rd
        add     zl, xl
        adc     zh, zero
        ld      tosl, z
        clr     tosh
        in      t2, SREG
        cli
        inc     xl
        andi    xl, (RX0_BUF_SIZE-1)
        sts     rbuf0_rd, xl
        lds     xl, rbuf0_lv
        dec     xl
        sts     rbuf0_lv, xl
        out     SREG, t2
        ret
;***************************************************
; RX0?  -- n    return the number of characters in queue
        fdw     RX0_L
RX0Q_L:
        .db     NFA|4,"rx0?",0
RX0Q:
        call    BUSY
        lds     xl, rbuf0_lv
        cpse    xl, zero
        jmp     TRUE_
        call    IDLE
.if U0FC_TYPE == 1
        rcall   XXON_TX0
.endif
.if U0FC_TYPE == 2
        cbi_    U0RTS_PORT, U0RTS_BIT
.endif
        jmp     FALSE_
;***************************************************
; TX1   c --    output character to UART 1
.ifdef UDR1
        fdw RX0Q_L 
TX1_L:
        .db     NFA|3,"tx1"
TX1_:
        cpi     tosl, XON
        breq    XXON_TX1_TOS
        cpi     tosl, XOFF
        breq    XXOFF_TX1_TOS
TX1_LOOP:
        rcall   PAUSE
        in_     t0, UCSR1A
        sbrs    t0, UDRE1
        rjmp    TX1_LOOP
        out_    UDR1, tosl
        poptos
        ret

XXON_TX1_TOS:
        poptos
        rjmp    XXON_TX1_1
XXON_TX1:
        sbrs    FLAGS2, ixoff_tx1
        ret
XXON_TX1_1:
        cbr     FLAGS2, (1<<ixoff_tx1)
        ldi     zh, XON
        rjmp    TX1_SEND

XXOFF_TX1_TOS:
        poptos
        rjmp    XXOFF_TX1_1
XXOFF_TX1:
        sbrc    FLAGS2, ixoff_tx1
        ret     
XXOFF_TX1_1:
        sbr     FLAGS2, (1<<ixoff_tx1)
        ldi     zh, XOFF
TX1_SEND:
        in_     zl, UCSR1A
        sbrs    zl, UDRE1
        rjmp    TX1_SEND
        out_    UDR1, zh
        ret
;***************************************************
; RX1    -- c    get character from the serial line
        fdw TX1_L 
RX1_L:
        .db     NFA|3,"rx1"
RX1_:
        rcall   PAUSE
        rcall   RX1Q
        call    ZEROSENSE
        breq    RX1_
        pushtos
        ldi     zl, low(rbuf1)
        ldi     zh, high(rbuf1)
        lds     xl, rbuf1_rd
        add     zl, xl
        adc     zh, zero
        ld      tosl, z
        clr     tosh
        in      t2, SREG
        cli
        inc     xl
        andi    xl, (RX1_BUF_SIZE-1)
        sts     rbuf1_rd, xl
        lds     xl, rbuf1_lv
        dec     xl
        sts     rbuf1_lv, xl
        out     SREG, t2
        ret
;***************************************************
; RX1?  -- n    return the number of characters in queue
        fdw     RX1_L
RX1Q_L:
        .db     NFA|4,"rx1?",0
RX1Q:
        call    BUSY
        lds     xl, rbuf1_lv
        cpse    xl, zero
        jmp     TRUE_
        call    IDLE
        rcall   XXON_TX1
        jmp     FALSE_
.endif
 ISTORERR:
        rcall   DOTS
        call    XSQUOTE
        .db     3,"AD?"
        call    TYPE
        rjmp    ABORT
        
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
        mov     t0, iaddrh
        cpi     t0, 0xe0       ; Dont allow kernel writes
        brcc    ISTORERR
        mov     t0, iaddrl
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
        ldi     t0, PAGESIZEB&0xff ; 0x100 max PAGESIZEB
        movw    zl, ibasel
        sub_pflash_z
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IFILL_BUFFER_2:
        lpm_    t1, z+
        st      x+, t1
        dec     t0
        brne    IFILL_BUFFER_2
        ret

IWRITE_BUFFER:
.if OPERATOR_UART == 0
.if U0FC_TYPE == 1
        rcall   DOLIT
        .dw     XOFF
        call    EMIT
.endif
.if U0FC_TYPE == 2
        sbi_    U0RTS_PORT, U0RTS_BIT
.endif
.else  ;; UART1
.if U1FC_TYPE == 1
        rcall   DOLIT
        .dw     XOFF
        call    EMIT
.endif
.if U1FC_TYPE == 2
        sbi_    U1RTS_PORT, U1RTS_BIT
.endif
.endif
        movw    zl, ibasel
        sub_pflash_z
        ldi     t1, (1<<PGERS) | (1<<SPMEN) ; Page erase
        rcall   DO_SPM
        ldi     t1, (1<<RWWSRE) | (1<<SPMEN); re-enable the RWW section
        rcall   DO_SPM

        ; transfer data from RAM to Flash page buffer
        ldi     t0, low(PAGESIZEB);init loop variable
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IWRITE_BUFFER1:
        ld      r0, x+
        ld      r1, x+
        ldi     t1, (1<<SPMEN)
        rcall   DO_SPM
        adiw    zl, 2
        subi    t0, 2
        brne    IWRITE_BUFFER1

        ; execute page write
        subi    zl, low(PAGESIZEB) ;restore pointer
        sbci    zh, high(PAGESIZEB)
        ldi     t1, (1<<PGWRT) | (1<<SPMEN)
        rcall   DO_SPM
        ; re-enable the RWW section
        rcall   IWRITE_BUFFER3
.if 1
        ; read back and check, optional
        ldi     t0, low(PAGESIZEB);init loop variable
        subi    xl, low(PAGESIZEB) ;restore pointer
        sbci    xh, high(PAGESIZEB)
IWRITE_BUFFER2:
        lpm_    r0, z+
        ld      r1, x+
        cpse    r0, r1
        rjmp    VERIFY_ERROR     ; emit ^ and reset.
        subi    t0, 1
        brne    IWRITE_BUFFER2
.endif
        clr     ibaseh
        cbr     FLAGS1, (1<<idirty)
        ; reenable interrupts
.if OPERATOR_UART == 0
.if U0FC_TYPE == 1
        rcall   DOLIT
        .dw     XON
        call    EMIT
.endif
.if U0FC_TYPE == 2
        cbi_    U0RTS_PORT, U0RTS_BIT
.endif
.else
.if U1FC_TYPE == 1
        rcall   DOLIT
        .dw     XON
        call    EMIT
.endif
.if U1FC_TYPE == 2
        cbi_    U1RTS_PORT, U1RTS_BIT
.endif
.endif
         ret
        ; ret to RWW section
        ; verify that RWW section is safe to read
IWRITE_BUFFER3:
        in_     t8, SPMCSR
        sbrs    t8, RWWSB ; If RWWSB is set, the RWW section is not ready yet
        ret
        ; re-enable the RWW section
        ldi     t1, (1<<RWWSRE) | (1<<SPMEN)
        rcall   DO_SPM
        rjmp    IWRITE_BUFFER3

DO_SPM:
        in_     t8, SPMCSR
        sbrc    t8, SPMEN
        rjmp    DO_SPM       ; Wait for previous write to complete
        out_    SPMCSR, t1
        spm
        ret

VERIFY_ERROR:
        rcall   DOLIT
        .dw     '^'
        call    EMIT
        rjmp    WARM_
                
        fdw     PAUSE_L
IFLUSH_L:
        .db     NFA|6,"iflush",0
IFLUSH:
        sbrc    FLAGS1, idirty
        rjmp    IWRITE_BUFFER
        ret

;***************************************************
.ifdef UDR1
        fdw     RX1Q_L
.else
        fdw     RX0Q_L
.endif
EMPTY_L:
        .db     NFA|5,"empty"
EMPTY:
        rcall   DOLIT
        fdw     COLDLIT
        rcall   DOLIT
        .dw     dp_start
        rcall   DOLIT
        .dw     coldlitsize
        call    CMOVE
        jmp     DP_TO_RAM
        
;*******************************************************
        fdw     EMPTY_L
WARM_L:
        .db     NFA|4,"warm",0
WARM_:
; Zero memory
        cli           ; Disable interrupts
        clr     xl
        clr     xh
        ldi     yl, 25
        ldi     yh, 0
WARM_1:
        st      x+, yh
        subi    yl, 1
        brne    WARM_1

        ldi     xl, 0x1C  ; clear ram from y register upwards
WARM_2:
        st      x+, zero
        cpi     xh, 0x10  ; to 0xfff, 4 Kbytes 
        brne    WARM_2
        ldi     yl, 1
        mov     r_one, yl
        ldi     yl, 2
        mov     r_two, yl
        ldi     yl, 4
        mov     r_four, yl
; Init Stack pointer
        ldi     yl, low(usbuf+ussize-4)
        ldi     yh, high(usbuf+ussize-4)

; Init Return stack pointer
        ldi     t0, low(urbuf+ursize-2)
        ldi     t1, high(urbuf+ursize-2)
        out     spl, t0
        out     sph, t1
; Init user pointer
        ldi     t0, low(up0)
        ldi     t1, high(up0)
        movw    upl, t0
; Set RAMPZ for correct flash addressing
.ifdef RAMPZ
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
.endif
; init warm literals
        rcall   DOLIT
        fdw     WARMLIT
        rcall   DOLIT
        .dw     cse
        rcall   DOLIT
        .dw     warmlitsize
        call    CMOVE
; init cold data to eeprom
        rcall   DOLIT
        .dw     dp_start
        rcall   FETCH
        rcall   TRUE_
        call    EQUAL
        call    ZEROSENSE
        breq    WARM_3  
        rcall   EMPTY
WARM_3:
; Move interrupts to boot flash section
        ldi     t0, (1<<IVCE)
        out_    MCUCR, r16
        ldi     t0, (1<<IVSEL)
        out_    MCUCR, r16

; Init ms timer
        ldi     t0, 1
        out_    TCCR1B, t0
.ifdef TIMSK
        ldi     t0, (1<<TOIE1)
        out_    TIMSK, t0
.endif
.ifdef TIMSK1
        ldi     t0, (1<<TOIE1)
        out_    TIMSK1, t0
.endif

; Init UART 0
.ifdef UBRR0L
        ; Set baud rate
;        out_    UBRR0H, zero
        ldi     t0, ubrr0val
        out_    UBRR0L, t0
        ; Enable receiver and transmitter, rx1 interrupts
        ldi     t0, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
        out_    UCSR0B,t0
        ; Set frame format: 8data, 1stop bit
        ldi     t0, (1<<USBS0)|(3<<UCSZ00)
        out_    UCSR0C,t0
.if U0FC_TYPE == 1
        sbr     FLAGS2, (1<<ixoff_tx0)
.endif
.if U0FC_TYPE == 2
        sbi_    U0RTS_DDR, U0RTS_BIT
.endif
.endif

; Init UART 1
.ifdef UBRR1L
        ; Set baud rate
;        out_    UBRR1H, zero
        ldi     t0, ubrr1val
        out_    UBRR1L, t0
        ; Enable receiver and transmitter, rx1 interrupts
        ldi     t0, (1<<RXEN1)|(1<<TXEN1)|(1<<RXCIE1)
        out_    UCSR1B,t0
        ; Set frame format: 8data, 1stop bit
        ldi     t0, (1<<USBS1)|(3<<UCSZ10)
        out_    UCSR1C,t0
.if U1FC_TYPE == 1
        sbr     FLAGS2, (1<<ixoff_tx1)
.endif
.if U1FC_TYPE == 2
        sbi_    U1RTS_DDR, U1RTS_BIT
.endif
.endif
        rcall   DP_TO_RAM
        sei

        rcall   VER
; Turnkey ?
        rcall   TURNKEY
        call    ZEROSENSE
        breq    STARTQ2
        call    XSQUOTE
        .db     3,"ESC"
        call    TYPE
        rcall   DOLIT
        .dw     TURNKEY_DELAY
        rcall   MS
        call    KEYQ
        call    ZEROSENSE
        breq    STARTQ1
        call    KEY
        rcall   DOLIT
        .dw     0x1b
        call    EQUAL
        call    ZEROSENSE
        brne    STARTQ2
STARTQ1:
        rcall   TURNKEY
        call    EXECUTE
STARTQ2:
        jmp     ABORT

;*******************************************************
; ;i  ( -- )    End definition of user interrupt routine
        fdw     DI_L
IRQ_SEMI_L:
        .db     NFA|IMMED|2,";i",0
IRQ_SEMI:
        rcall   DOLIT
        .dw     0x940C     ; jmp
        rcall   ICOMMA
        rcall   DOLIT
        .dw     FF_ISR_EXIT
        rcall   ICOMMA
        jmp     LEFTBRACKET


; int!  ( addr n  --  )   store interrupt vector
        fdw     IRQ_SEMI_L
IRQ_V_L:
        .db     NFA|4,"int!",0
        rcall   DOLIT
        .dw     ivec
        call    PLUS
        jmp     STORE

; DOLITERAL  x --           compile DOLITeral x as native code
        fdw     IRQ_V_L
LITERAL_L:
        .db     NFA|IMMED|7,"literal"
LITERAL:
        rcall   DOLIT
        .dw     0x939a          ; st      -Y, tosh
        rcall   ICOMMA
        rcall   DOLIT
        .dw     0x938a          ; st      -Y, tosl
        rcall   ICOMMA
        call    DUP
        mov     tosh, tosl
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x80
        rcall   ICOMMA
        mov     tosl, tosh
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x90
        jmp     ICOMMA

.if 0
LITERALruntime:
        st      -Y, tosh    ; 0x939a
        st      -Y, tosl    ; 0x938a
        ldi     tosl, 0x12  ; 0xe1r2 r=8 (r24)
        ldi     tosh, 0x34  ; 0xe3r4 r=9 (r25)
.endif

;*****************************************************************
ISTORE:
        rcall   LOCKEDQ
        movw    iaddrl, tosl
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, (PAGESIZEB-1)
        add     xl, t0
        st      x+, tosl
        st      x+, tosh
        poptos
        sbr     FLAGS1, (1<<idirty)
        ret

        fdw     LITERAL_L
STORE_L:
        .db     NFA|1, "!"
STORE:
        cpi     tosh, high(PEEPROM)
        brcc    STORE1
STORE_RAM:
        movw    zl, tosl
        poptos
        std     Z+1, tosh
        std     Z+0, tosl
        poptos
        ret
STORE1:
        cpi     tosh, high(OFLASH)
        brcc    ISTORE
ESTORE:
        rcall   LOCKEDQ
        sbic    eecr, eewe
        rjmp    ESTORE
        subi    tosh, high(PEEPROM)
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

        out     eedr, tosh
        sbi     eecr, eemwe
        sbi     eecr, eewe

        poptos
        ret
LOCKEDQ:
        sbrs    FLAGS1, fLOCK
        ret
        rcall   DOTS
        call    XSQUOTE
        .db     3,"AD?"
        call    TYPE
        rjmp    STARTQ2        ; goto    ABORT
        
;***********************************************************
IFETCH:
        movw    r31:r30, tosl ; z
        cpse    zh, ibaseh
        rjmp    IIFETCH
        mov     t0, zl
        andi    t0, ~(PAGESIZEB-1)
        cp      t0, ibasel
        brne    IIFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zl, (PAGESIZEB-1)
        add     xl, zl
        ld      tosl, x+
        ld      tosh, x+
        ret
IIFETCH:
        sub_pflash_z
        lpm_    tosl, z+     ; Fetch from Flash directly
        lpm_    tosh, z+
.ifdef RAMPZ
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
.endif
        ret
                
        fdw     STORE_L
FETCH_L:
        .db     NFA|1, "@"
FETCH:
        cpi     tosh, high(PEEPROM)
        brcc    FETCH1
FETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        ld      tosh, z+
        ret
FETCH1:
        cpi     tosh, high(OFLASH)
        brcc    IFETCH
EFETCH:
        sbic    eecr, eewe
        rjmp    EFETCH
        subi    tosh, high(PEEPROM)
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
        movw    r31:r30, tosl ; z
        cpse    zh, ibaseh
        rjmp    IICFETCH
        mov     t0, zl
        andi    t0, ~(PAGESIZEB-1)
        cp      t0, ibasel
        brne    IICFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zl, (PAGESIZEB-1)
        add     xl, zl
        ld      tosl, x+
        clr     tosh
        ret
IICFETCH:
        sub_pflash_z
        lpm_    tosl, z+     ; Fetch from Flash directly
        clr     tosh
.ifdef RAMPZ
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
.endif
        ret

        fdw     FETCH_L
CFETCH_L:
        .db     NFA|2, "c@",0
CFETCH:
        cpi     tosh, high(PEEPROM)
        brcc    CFETCH1
CFETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        clr     tosh
        ret
CFETCH1:
        cpi     tosh, high(OFLASH)
        brcc    ICFETCH
ECFETCH:
        sbic    eecr, eewe
        rjmp    ECFETCH
        subi    tosh, high(PEEPROM)
        out     eearl, tosl
        out     eearh, tosh
        sbi     eecr, eere
        in      tosl, eedr
        clr     tosh
        ret

ICSTORE:
        rcall   LOCKEDQ
        movw    iaddrl, tosl
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, (PAGESIZEB-1)
        add     xl, t0
        st      x+, tosl
        poptos
        sbr     FLAGS1, (1<<idirty)
        ret

        fdw     CFETCH_L
CSTORE_L:
        .db     NFA|2, "c!",0
CSTORE:
        cpi     tosh, high(PEEPROM)
        brcc    CSTORE1
CSTORE_RAM:
        movw zl, tosl
        poptos
        std Z+0, tosl
        poptos
        ret
CSTORE1:
        cpi     tosh, high(OFLASH)
        brcc    ICSTORE
ECSTORE:
        rcall   LOCKEDQ
        sbic    eecr, eewe
        rjmp    ECSTORE
        subi    tosh, high(PEEPROM)
        out     eearl, tosl
        out     eearh, tosh
        poptos
        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe
        poptos
        ret

;;; Disable writes to flash and eeprom
        fdw     CSTORE_L
FLOCK_L:
        .db     NFA|3,"fl-"
        sbr     FLAGS1, (1<<fLOCK)
        ret

;;; Enable writes to flash and eeprom
        fdw     FLOCK_L
FUNLOCK_L:
        .db     NFA|3,"fl+"
        cbr     FLAGS1, (1<<fLOCK)
        ret

;;; Enable flow control
        fdw     FUNLOCK_L
FCON_L:
        .db     NFA|3,"u1+"
        cbr     FLAGS2, (1<<fFC_tx1)
        ret

;;; Disable flow control
        fdw     FCON_L
FCOFF_L:
        .db     NFA|3,"u1-"
        sbr     FLAGS2, (1<<fFC_tx1)
        ret

;;; Clear watchdog timer
        fdw     FCOFF_L
CWD_L:
        .db     NFA|INLINE|3,"cwd"
        wdr
        ret

        fdw     CWD_L
VALUE_L:
        .db     NFA|5,"value"
VALUE:
        rcall   CREATE
        call    COMMA
        rcall   XDOES
VALUE_DOES:
        call    DODOES
        jmp     FETCH

        fdw     VALUE_L
DEFER_L:
        .db     NFA|5,"defer"
DEFER:
        rcall   CREATE
        call    DOLIT
        fdw     ABORT
        call    COMMA
        rcall   XDOES
DEFER_DOES:
        call    DODOES
        jmp     FEXECUTE

        fdw     DEFER_L
IS_L:
        .db     NFA|2,"is",0
IS:
        rcall   TICK
        call    TWOPLUS
        call    TWOPLUS
        rcall   FETCH
        rcall   STATE_
        call    ZEROSENSE
        breq    IS1
        rcall   LITERAL
        call    DOLIT
        fdw     STORE
        call    COMMAXT
        rjmp    IS2
IS1:
        rcall   STORE
IS2:
        ret

        fdw     IS_L
TO_L:
        .db     NFA|2,"to",0
TO:
        jmp     IS

        fdw     TO_L
TURNKEY_L:
        .db     NFA|7,"turnkey"
TURNKEY:
        call    VALUE_DOES      ; Must be call for IS to work.
        .dw     dpSTART


;;; *******************************************************
; PAUSE  --     switch task
        fdw     TURNKEY_L
PAUSE_L:
        .db     NFA|5,"pause"
PAUSE:
        lds     t0, status
        cpi     t0, 0
        brne    PAUSE1
.if CPU_LOAD_LED == 1
        sbi_    CPU_LOAD_DDR, CPU_LOAD_BIT
.if CPU_LOAD_LED_POLARITY == 1
        cbi_    CPU_LOAD_PORT, CPU_LOAD_BIT
.else
        sbi_    CPU_LOAD_PORT, CPU_LOAD_BIT
.endif
.endif
.if IDLE_MODE == 1
.ifdef SMCR
        ldi     t0, (1<<SE)
        out_    SMCR, t0
.else
        in_     t0, MCUCR
        sbr     t0, (1<<SE)
        out_    MCUCR, t0
.endif
        sleep               ; IDLE mode
.ifdef SMCR
        out_    SMCR, zero
.else
        in_     t0, MCUCR
        cbr     t0, (1<<SE)
        out_    MCUCR, zero
.endif
.endif
.if CPU_LOAD_LED == 1
.if CPU_LOAD_LED_POLARITY == 1
        sbi_    CPU_LOAD_PORT, CPU_LOAD_BIT
.else
        cbi_    CPU_LOAD_PORT, CPU_LOAD_BIT
.endif
.endif
PAUSE1:
        in      t2, SREG
        cli
        push    tosl
        push    tosh
        movw    zl, upl
        sbiw    zl, -ursave
        in      t0, spl
        st      z+, t0
        in      t0, sph
        st      z+, t0
        st      z+, yl
        st      z+, yh
        st      z+, pl
        st      z+, ph
        sbiw    zl, (usource-ulink)
        ld      xl, z+
        ld      xh, z+
        movw    upl, xl
        sbiw    xl, -ursave
        ld      t0, x+
        out     spl, t0
        ld      t0, x+
        out     sph, t0
        pop     tosh
        pop     tosl
        ld      yl, x+
        ld      yh, x+
        ld      pl, x+
        ld      ph, x+
        out     SREG, t2
        ret


        fdw     IFLUSH_L
OPERATOR_L:
        .db     NFA|8,"operator",0
OPERATOR:
        call    DOCREATE
        fdw     OPERATOR_AREA
OPERATOR_AREA:
        .dw     up0
        .db     uaddsize, ursize
        .db     ussize, utibsize

        fdw     OPERATOR_L
ICOMMA_L:
        .db     NFA|2, "i,",0
ICOMMA:
        rcall   IHERE
        rcall   STORE
        call    CELL
        jmp     IALLOT


;   IHERE ! 1 CHARS IALLOT ;
        fdw     ICOMMA_L
ICCOMMA_L:
        .db     NFA|3,"ic,"
ICCOMMA:
        rcall   IHERE
        rcall   CSTORE
        call    ONE
        jmp     IALLOT


;*******************************************************************
; BOOT sector END **************************************************

KERNEL_END:
