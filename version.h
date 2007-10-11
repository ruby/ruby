#define RUBY_VERSION "1.8.6"
#define RUBY_RELEASE_DATE "2007-10-11"
#define RUBY_VERSION_CODE 186
#define RUBY_RELEASE_CODE 20071011
#define RUBY_PATCHLEVEL 5000

#define RUBY_VERSION_MAJOR 1
#define RUBY_VERSION_MINOR 8
#define RUBY_VERSION_TEENY 6
#define RUBY_RELEASE_YEAR 2007
#define RUBY_RELEASE_MONTH 10
#define RUBY_RELEASE_DAY 11

#ifdef RUBY_EXTERN
RUBY_EXTERN const char ruby_version[];
RUBY_EXTERN const char ruby_release_date[];
RUBY_EXTERN const char ruby_platform[];
RUBY_EXTERN const int ruby_patchlevel;
#endif
