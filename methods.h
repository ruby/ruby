/************************************************

  methods.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:38 $
  created at: Fri Jul 29 14:43:03 JST 1994

************************************************/
#ifndef METHOD_H
#define METHOD_H

struct SMethod {
    struct node *node;
    struct RClass *origin;
    ID id;
    int count;
    int undef;
};

#endif
