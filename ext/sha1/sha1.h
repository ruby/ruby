#ifndef _SHA1_H
#define _SHA1_H

#include "config.h"

#ifdef HAVE_PROTOTYPES
#define PROTOTYPES 1
#endif
#ifndef PROTOTYPES
#define PROTOTYPES 0
#endif

#if PROTOTYPES
#define __P(x) x
#else
#define __P(x) ()
#endif

#include <stdio.h>
#include <string.h>

typedef struct {
    unsigned long state[5];
    unsigned long count[2];
    unsigned char buffer[64];
} SHA1_CTX;

void SHA1Transform __P((unsigned long state[5], unsigned char buffer[64]));
void SHA1Init __P((SHA1_CTX* context));
void SHA1Update __P((SHA1_CTX* context, unsigned char* data, unsigned int len));
void SHA1Final __P((unsigned char digest[20], SHA1_CTX* context));

#endif /* _SHA1_H */
