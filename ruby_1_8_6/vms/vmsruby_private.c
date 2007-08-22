#include "vmsruby_private.h"
#include <stdio.h>
#include <stdlib.h>

void _vmsruby_init(void)
{
    _vmsruby_set_switch("DECC$WLS", "TRUE");
}


#include <starlet.h>
#include <string.h>
#include <descrip.h>
#include <lnmdef.h>

struct item_list_3 {
    short buflen;
    short itmcod;
    void *bufadr;
    void *retlen;
};

long _vmsruby_set_switch(char *name, char *value)
{
    long status;
    struct item_list_3 itemlist[20];
    int i;

    i = 0;
    itemlist[i].itmcod = LNM$_STRING;
    itemlist[i].buflen = strlen(value);
    itemlist[i].bufadr = value;
    itemlist[i].retlen = NULL;
    i++;
    itemlist[i].itmcod = 0;
    itemlist[i].buflen = 0;

    $DESCRIPTOR(TABLE_d, "LNM$PROCESS");
    $DESCRIPTOR(lognam_d, "");

    lognam_d.dsc$a_pointer = name;
    lognam_d.dsc$w_length  = strlen(name);

    status = sys$crelnm (
             	 0, 
             	 &TABLE_d, 
             	 &lognam_d, 
             	 0,  /* usermode */
             	 itemlist);

    return status;
}
