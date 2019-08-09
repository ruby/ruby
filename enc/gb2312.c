#include "regenc.h"

void
Init_gb2312(void)
{
}

ENC_REPLICATE("GB2312", "EUC-KR")
ENC_ALIAS("EUC-CN", "GB2312")
ENC_ALIAS("eucCN", "GB2312")
ENC_REPLICATE("GB12345", "GB2312")
