/************************************************

  ident.h -

  $Author: matz $
  $Revision: 1.1.1.1 $
  $Date: 1994/06/17 14:23:49 $
  created at: Mon Jan 31 16:23:19 JST 1994

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#ifndef IDENT_H
#define IDENT_H

#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x00
#define ID_ATTRSET  0x04
#define ID_INSTANCE 0x02
#define ID_GLOBAL   0x03
#define ID_CONST    0x06
#define ID_VARMASK  0x02

#endif
