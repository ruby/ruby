/************************************************

  ident.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:29 $
  created at: Mon Jan 31 16:23:19 JST 1994

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#ifndef IDENT_H
#define IDENT_H

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x00
#define ID_INSTANCE 0x01
#define ID_GLOBAL   0x02
#define ID_ATTRSET  0x03
#define ID_CONST    0x04
#define ID_NTHREF   0x05

#endif
