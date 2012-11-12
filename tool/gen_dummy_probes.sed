
# upper case everything
y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/

# remove the pragma declarations
s/^#PRAGMA.*$//

# replace the provider section with the start of the header file
s/PROVIDER RUBY {/#ifndef	_PROBES_H\
#define	_PROBES_H/

# finish up the #ifndef sandwich
s/};/#endif	\/* _PROBES_H *\//

s/__/_/g

s/([^,)]\{1,\})/(arg0)/
s/([^,)]\{1,\},[^,)]\{1,\})/(arg0, arg1)/
s/([^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\})/(arg0, arg1, arg2)/
s/([^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\})/(arg0, arg1, arg2, arg3)/
s/([^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\},[^,)]\{1,\})/(arg0, arg1, arg2, arg3, arg4)/

s/[ ]*PROBE[ ]\([^\(]*\)\(([^\)]*)\);/#define RUBY_DTRACE_\1_ENABLED() 0\
#define RUBY_DTRACE_\1\2\ do \{ \} while\(0\)/
