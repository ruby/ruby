/*
 * PROJECT C Library, X68000 PROGRAMMING INTERFACE DEFINITION
 * --------------------------------------------------------------------
 * This file is written by the Project C Library Group,  and completely
 * in public domain. You can freely use, copy, modify, and redistribute
 * the whole contents, without this notice.
 * --------------------------------------------------------------------
 * $Id$
 */
/* changed 1997.2.3 by K.Okabe */

/* System headers */
#include <stdlib.h>
#include <sys/xstdlib.h>

/* Functions */
char *fconvert (double x, int ndigit, int *decpt, int *sign, char *buffer)
{
    int pos, n;
    char *src, *dst;
    char string[24];
    int figup;

    /* 18���ʸ������Ѵ� */
    _dtos18 (x, decpt, sign, string);

    /* ���ԡ������ɥ쥹������ */
    src = string;

    /* ���ԡ��襢�ɥ쥹������ */
    dst = buffer;

    /* ���������֤����� */
    pos = *decpt;

    /* ���������֤���ʤ� */
    if (pos < 0) {

	/* ��������׻� */
	n = min (-pos, ndigit);

	/* ��Ƭ��0������ */
	while (n-- > 0)
	    *dst++ = '0';

	/* ���������֤�0�ˤʤ� */
	*decpt = 0;

    }

    /* �Ĥ�Υ��ԡ���� */
    n = ndigit + pos;

    /* ��Ǽ��˥��ԡ� */
    while (n-- > 0) {

	/* ­��ʤ���ʬ��0������ */
	if (*src == '\0') {
	    while (n-- >= 0)
		*dst++ = '0';
	    break;
	}

	/* �Ѵ�ʸ���󤫤饳�ԡ� */
	*dst++ = *src++;

    }

    /* �ݤ�� */
    *decpt += (figup = _round (buffer, dst, *src));

    /* ����夬�꤬�����������0���ɲä��� */
    if (figup)
	*dst++ = '0';

    /* ��ü�� NUL ���Ǥ� */
    *dst = '\0';

    /* ���ɥ쥹���֤� */
    return buffer;
}
