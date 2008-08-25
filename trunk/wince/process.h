#ifndef PROCESS_H
#define PROCESS_H 1


#define _P_WAIT         0
#define _P_NOWAIT       1
#define _P_OVERLAY      2
#define _P_DETACH       4

#define P_WAIT          _P_WAIT
#define P_NOWAIT        _P_NOWAIT
#define P_DETACH        _P_DETACH
#define P_OVERLAY       _P_OVERLAY

#ifndef _INTPTR_T_DEFINED
typedef int            intptr_t;
#define _INTPTR_T_DEFINED
#endif

#ifdef __cplusplus
extern "C" {
#endif

int _getpid(void);

int _cwait(int *, int, int);
void abort(void);

int _execl(const char *, const char *, ...);
//int _execv(const char *, const char * const *);
int execv(const char *path, char *const argv[]);

intptr_t _spawnle(int, const char *, const char *, ...);
intptr_t _spawnvpe(int, const char *, const char * const *,
	      const char * const *);

#ifdef __cplusplus
};
#endif

//#define getpid	   _getpid
#define execl	   _execl
#define execv	   _execv


#endif
