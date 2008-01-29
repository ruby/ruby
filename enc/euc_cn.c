#include <ruby/ruby.h>
#include <ruby/encoding.h>
#include "regenc.h"

void
Init_euc_cn(void)
{
    rb_enc_register("EUC-CN", rb_enc_find("EUC-KR"));
}

ENC_ALIAS("eucCN", "EUC-CN");
ENC_ALIAS("GB2312", "EUC-CN");
