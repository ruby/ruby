#ifndef MISSING_CRT_EXTERNS_H
#define MISSING_CRT_EXTERNS_H

char ***_NSGetEnviron();
#undef environ
#define environ (*_NSGetEnviron())

#endif
