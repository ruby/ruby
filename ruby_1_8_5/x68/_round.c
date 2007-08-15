/*
 * PROJECT C Library, X68000 PROGRAMMING INTERFACE DEFINITION
 * --------------------------------------------------------------------
 * This file is written by the Project C Library Group,  and completely
 * in public domain. You can freely use, copy, modify, and redistribute
 * the whole contents, without this notice.
 * --------------------------------------------------------------------
 * $Id: _round.c,v 1.1.1.2 1999/01/20 04:59:39 matz Exp $
 */
/* changed 1997.2.2 by K.Okabe */

/* System headers */
#include <stdlib.h>
#include <sys/xstdlib.h>

/* Functions */
int _round (char *top, char *cur, int undig)
{
    char *ptr;

    /* 最後が5未満なら丸めは必要ない */
    if (undig < '5')
	return 0;

    /* ポインタ設定 */
    ptr = cur - 1;

    /* 先頭まで戻りながら丸め処理 */
    while (ptr >= top) {

	/* 繰り上がらなければそれで終わり */
	if (++(*ptr) <= '9')
	    return 0;

	/* その桁を0に戻す */
	*ptr-- = '0';

    }

    /* 先頭を1にする */
    *++ptr = '1';

    /* 繰り上がりをしらせる */
    return 1;
}
