;**********************************************************************
;                                                                     *
;    Filename:      ff30.inc                                          *
;    Date:          14.11.2010                                        *
;    File Version:  4.7                                               *
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
.ifdecl    __dsPIC33F  
  .include "p33Fxxxx.inc"  
  .include "p33_config.inc"
.endif  
 
.ifdecl    __PIC24H  
  .include "p24Hxxxx.inc"  
  .include "p24hj_config.inc"
.endif  
 
.ifdecl    __PIC24FK  
  .include "p24Fxxxx.inc"
  .include "p24f16ka_config.inc"
.endif  
 
.ifdecl    __PIC24FJ
  .include "p24Fxxxx.inc"  
  .include "p24fj_config.inc"
.endif  

.ifdecl    __PIC24F
  .include "p24Fxxxx.inc"  
  .include "p24f_config.inc"
.endif  

.ifdecl    __dsPIC30F  
  .include "p30Fxxxx.inc"  
  .include "p30f_config.inc"
.endif

