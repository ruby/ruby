#ifndef RUBY_THREAD_LOCAL_H
#define RUBY_THREAD_LOCAL_H
/**********************************************************************

  thread_local.h -

  This introduces `thread_local` compatibility for different compilers.

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#ifndef thread_local
	#if __STDC_VERSION__ >= 201112
		#define thread_local _Thread_local
	#elif defined(__GNUC__)
		/* note that ICC (linux) and Clang are covered by __GNUC__ */
		#define thread_local __thread
	#elif defined(_WIN32)
		#define thread_local __declspec(thread)
	#else
		#error "Cannot define thread_local!"
	#endif
#endif

#endif /* RUBY_THREAD_LOCAL_H */
