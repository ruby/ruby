#ifndef DIRECT_H
#define DIRECT_H 1


#ifdef __cplusplus
extern "C" {
#endif

char *getcwd(char* buffer, int maxlen);
int _chdir(const char * dirname);
int _rmdir(const char * dir);
int _mkdir(const char * dir);

#ifdef __cplusplus
};
#endif

#define chdir      _chdir
#define rmdir      _rmdir
#define mkdir      _mkdir

#endif
