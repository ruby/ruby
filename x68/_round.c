/*
 * PROJECT C Library, X68000 PROGRAMMING INTERFACE DEFINITION
 * --------------------------------------------------------------------
 * This file is written by the Project C Library Group,  and completely
 * in public domain. You can freely use, copy, modify, and redistribute
 * the whole contents, without this notice.
 * --------------------------------------------------------------------
 * $Id$
 */
/* changed 1997.2.2 by K.Okabe */

/* System headers */
#include <stdlib.h>
#include <sys/xstdlib.h>

/* Functions */
int _round (char *top, char *cur, int undig)
{
    char *ptr;

    /* �Ǹ夬5̤���ʤ�ݤ��ɬ�פʤ� */
    if (undig < '5')
	return 0;

    /* �ݥ������� */
    ptr = cur - 1;

    /* ��Ƭ�ޤ����ʤ���ݤ���� */
    while (ptr >= top) {

	/* ����夬��ʤ���Ф���ǽ���� */
	if (++(*ptr) <= '9')
	    return 0;

	/* ���η��0���᤹ */
	*ptr-- = '0';

    }

    /* ��Ƭ��1�ˤ��� */
    *++ptr = '1';

    /* ����夬��򤷤餻�� */
    return 1;
}
