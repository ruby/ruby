/* Copyright (C) 1991 Free Software Foundation, Inc.
This file is part of the GNU C Library.

The GNU C Library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

The GNU C Library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU Library General Public
License along with the GNU C Library; see the file COPYING.LIB.  If
not, write to the Free Software Foundation, Inc., 675 Mass Ave,
Cambridge, MA 02139, USA.  */

#include "config.h"
#include <errno.h>
#include "fnmatch.h"

#ifdef USE_CWGUSI
#include <sys/errno.h>
#endif

#if !defined (__GNU_LIBRARY__) && !defined (STDC_HEADERS)
#  if !defined (errno)
extern int errno;
#  endif /* !errno */
#endif

/* Match STRING against the filename pattern PATTERN, returning zero if
   it matches, FNM_NOMATCH if not.  */
int
fnmatch (pattern, string, flags)
     char *pattern;
     char *string;
     int flags;
{
  register char *p = pattern, *n = string;
  register char c;

  if ((flags & ~__FNM_FLAGS) != 0)
    {
      errno = EINVAL;
      return (-1);
    }

  while ((c = *p++) != '\0')
    {
      switch (c)
	{
	case '?':
	  if (*n == '\0')
	    return (FNM_NOMATCH);
	  else if ((flags & FNM_PATHNAME) && *n == '/')
	    return (FNM_NOMATCH);
	  else if ((flags & FNM_PERIOD) && *n == '.' &&
		   (n == string || ((flags & FNM_PATHNAME) && n[-1] == '/')))
	    return (FNM_NOMATCH);
	  break;

	case '\\':
	  if (!(flags & FNM_NOESCAPE))
	    c = *p++;
	  if (*n != c)
	    return (FNM_NOMATCH);
	  break;

	case '*':
	  if ((flags & FNM_PERIOD) && *n == '.' &&
	      (n == string || ((flags & FNM_PATHNAME) && n[-1] == '/')))
	    return (FNM_NOMATCH);

	  for (c = *p++; c == '?' || c == '*'; c = *p++, ++n)
	    if (((flags & FNM_PATHNAME) && *n == '/') ||
		(c == '?' && *n == '\0'))
	      return (FNM_NOMATCH);

	  if (c == '\0')
	    return (0);

	  {
	    char c1 = (!(flags & FNM_NOESCAPE) && c == '\\') ? *p : c;
	    for (--p; *n != '\0'; ++n)
	      if ((c == '[' || *n == c1) &&
		  fnmatch (p, n, flags & ~FNM_PERIOD) == 0)
		return (0);
	    return (FNM_NOMATCH);
	  }

	case '[':
	  {
	    /* Nonzero if the sense of the character class is inverted.  */
	    register int not;

	    if (*n == '\0')
	      return (FNM_NOMATCH);

	    if ((flags & FNM_PERIOD) && *n == '.' &&
		(n == string || ((flags & FNM_PATHNAME) && n[-1] == '/')))
	      return (FNM_NOMATCH);

	    /* Make sure there is a closing `]'.  If there isn't, the `['
	       is just a character to be matched. */
	    {
	      register char *np;

	      for (np = p; np && *np && *np != ']'; np++);

	      if (np && !*np)
		{
		  if (*n != '[')
		    return (FNM_NOMATCH);
		  goto next_char;
		}
	    }
	      
	    not = (*p == '!' || *p == '^');
	    if (not)
	      ++p;

	    c = *p++;
	    for (;;)
	      {
		register char cstart = c, cend = c;

		if (!(flags & FNM_NOESCAPE) && c == '\\')
		  cstart = cend = *p++;

		if (c == '\0')
		  /* [ (unterminated) loses.  */
		  return (FNM_NOMATCH);

		c = *p++;

		if ((flags & FNM_PATHNAME) && c == '/')
		  /* [/] can never match.  */
		  return (FNM_NOMATCH);

		if (c == '-' && *p != ']')
		  {
		    cend = *p++;
		    if (!(flags & FNM_NOESCAPE) && cend == '\\')
		      cend = *p++;
		    if (cend == '\0')
		      return (FNM_NOMATCH);
		    c = *p++;
		  }

		if (*n >= cstart && *n <= cend)
		  goto matched;

		if (c == ']')
		  break;
	      }
	    if (!not)
	      return (FNM_NOMATCH);

	  next_char:
	    break;

	  matched:
	    /* Skip the rest of the [...] that already matched.  */
	    while (c != ']')
	      {
		if (c == '\0')
		  /* [... (unterminated) loses.  */
		  return (FNM_NOMATCH);

		c = *p++;
		if (!(flags & FNM_NOESCAPE) && c == '\\')
		  /* 1003.2d11 is unclear if this is right.  %%% */
		  ++p;
	      }
	    if (not)
	      return (FNM_NOMATCH);
	  }
	  break;

	default:
	  if (c != *n)
	    return (FNM_NOMATCH);
	}

      ++n;
    }

  if (*n == '\0')
    return (0);

  return (FNM_NOMATCH);
}
