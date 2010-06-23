#define RUBY_VERSION "1.8.7"
#define RUBY_RELEASE_DATE "2010-06-23"
#define RUBY_VERSION_CODE 187
#define RUBY_RELEASE_CODE 20100623
#define RUBY_PATCHLEVEL 299

#define RUBY_VERSION_MAJOR 1
#define RUBY_VERSION_MINOR 8
#define RUBY_VERSION_TEENY 7
#define RUBY_RELEASE_YEAR 2010
#define RUBY_RELEASE_MONTH 6
#define RUBY_RELEASE_DAY 23

#ifdef RUBY_EXTERN
RUBY_EXTERN const char ruby_version[];
RUBY_EXTERN const char ruby_release_date[];
RUBY_EXTERN const char ruby_platform[];
RUBY_EXTERN const int ruby_patchlevel;
RUBY_EXTERN const char *ruby_description;
RUBY_EXTERN const char *ruby_copyright;
#endif

#define RUBY_AUTHOR "Yukihiro Matsumoto"
#define RUBY_BIRTH_YEAR 1993
#define RUBY_BIRTH_MONTH 2
#define RUBY_BIRTH_DAY 24

#define RUBY_RELEASE_STR "patchlevel"
#define RUBY_RELEASE_NUM RUBY_PATCHLEVEL
