/* File-name wildcard pattern matching for GNU.
   Copyright (C) 1985, 1988, 1989 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 1, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.  */

/* To whomever it may concern: I have never seen the code which most
   Unix programs use to perform this function.  I wrote this from scratch
   based on specifications for the pattern matching.  --RMS.  */

#include <config.h>

#if !defined (__GNUC__) && !defined (HAVE_ALLOCA_H) && defined (_AIX)
  #pragma alloca
#endif /* _AIX && RISC6000 && !__GNUC__ */

#if defined (HAVE_ALLOCA_H)
#  include <alloca.h>
#endif

#if defined (HAVE_UNISTD_H)
#  include <unistd.h>
#endif

#if defined (HAVE_STDLIB_H)
#  include <stdlib.h>
#else
#  if defined (SHELL)
#    include "ansi_stdlib.h"
#  endif /* SHELL */
#endif

#include <sys/types.h>

#if defined (HAVE_DIRENT_H)
#  include <dirent.h>
#  define D_NAMLEN(d) strlen ((d)->d_name)
#else /* !HAVE_DIRENT_H */
#  define D_NAMLEN(d) ((d)->d_namlen)
#  if defined (HAVE_SYS_NDIR_H)
#    include <sys/ndir.h>
#  endif
#  if defined (HAVE_SYS_DIR_H)
#    include <sys/dir.h>
#  endif /* HAVE_SYS_DIR_H */
#  if defined (HAVE_NDIR_H)
#    include <ndir.h>
#  endif
#  if !defined (dirent)
#    define dirent direct
#  endif
#endif /* !HAVE_DIRENT_H */

#if defined (_POSIX_SOURCE) || defined(DJGPP) || defined(USE_CWGUSI)
/* Posix does not require that the d_ino field be present, and some
   systems do not provide it. */
#  define REAL_DIR_ENTRY(dp) 1
#else
#  define REAL_DIR_ENTRY(dp) (dp->d_ino != 0)
#endif /* _POSIX_SOURCE */

#if defined (HAVE_STRING_H)
#  include <string.h>
#else /* !HAVE_STRING_H */
#  include <strings.h>
#endif /* !HAVE_STRING_H */

#if !defined (HAVE_BCOPY) && !defined (bcopy)
#  define bcopy(s, d, n) ((void) memcpy ((d), (s), (n)))
#endif /* !HAVE_BCOPY */

/* If the opendir () on your system lets you open non-directory files,
   then we consider that not robust. */
#if defined (OPENDIR_NOT_ROBUST)
#  if defined (SHELL)
#    include "posixstat.h"
#  else /* !SHELL */
#    include <sys/stat.h>
#  endif /* !SHELL */
#endif /* OPENDIR_NOT_ROBUST */

#include "fnmatch.h"

extern void *xmalloc (), *xrealloc ();
#if !defined (HAVE_STDLIB_H)
extern void free ();
#endif /* !HAVE_STDLIB_H */

#if !defined (NULL)
#  if defined (__STDC__)
#    define NULL ((void *) 0)
#  else
#    define NULL 0x0
#  endif /* __STDC__ */
#endif /* !NULL */

#if defined (SHELL)
extern void throw_to_top_level ();

extern int interrupt_state;
#endif /* SHELL */

/* Global variable which controls whether or not * matches .*.
   Non-zero means don't match .*.  */
int noglob_dot_filenames = 1;

/* Global variable to return to signify an error in globbing. */
char *glob_error_return;

/* Return nonzero if PATTERN has any special globbing chars in it.  */
int
glob_pattern_p (pattern)
     char *pattern;
{
  register char *p = pattern;
  register char c;
  int open = 0;

  while ((c = *p++) != '\0')
    switch (c)
      {
      case '?':
      case '*':
	return (1);

      case '[':		/* Only accept an open brace if there is a close */
	open++;		/* brace to match it.  Bracket expressions must be */
	continue;	/* complete, according to Posix.2 */
      case ']':
	if (open)
	  return (1);
	continue;      

      case '\\':
	if (*p++ == '\0')
	  return (0);
      }

  return (0);
}

/* Remove backslashes quoting characters in PATHNAME by modifying PATHNAME. */
static void
dequote_pathname (pathname)
     char *pathname;
{
  register int i, j;

  for (i = j = 0; pathname && pathname[i]; )
    {
      if (pathname[i] == '\\')
	i++;

      pathname[j++] = pathname[i++];

      if (!pathname[i - 1])
	break;
    }
  pathname[j] = '\0';
}


/* Return a vector of names of files in directory DIR
   whose names match glob pattern PAT.
   The names are not in any particular order.
   Wildcards at the beginning of PAT do not match an initial period.

   The vector is terminated by an element that is a null pointer.

   To free the space allocated, first free the vector's elements,
   then free the vector.

   Return 0 if cannot get enough memory to hold the pointer
   and the names.

   Return -1 if cannot access directory DIR.
   Look in errno for more information.  */

char **
glob_vector (pat, dir)
     char *pat;
     char *dir;
{
  struct globval
    {
      struct globval *next;
      char *name;
    };

  DIR *d;
  register struct dirent *dp;
  struct globval *lastlink;
  register struct globval *nextlink;
  register char *nextname;
  unsigned int count;
  int lose, skip;
  register char **name_vector;
  register unsigned int i;
#if defined (OPENDIR_NOT_ROBUST)
  struct stat finfo;

  if (stat (dir, &finfo) < 0)
    return ((char **) &glob_error_return);

  if (!S_ISDIR (finfo.st_mode))
    return ((char **) &glob_error_return);
#endif /* OPENDIR_NOT_ROBUST */

  d = opendir (dir);
  if (d == NULL)
    return ((char **) &glob_error_return);

  lastlink = 0;
  count = 0;
  lose = 0;
  skip = 0;

  /* If PAT is empty, skip the loop, but return one (empty) filename. */
  if (!pat || !*pat)
    {
      nextlink = (struct globval *)alloca (sizeof (struct globval));
      nextlink->next = lastlink;
      nextname = (char *) xmalloc (1);
      if (!nextname)
	lose = 1;
      else
	{
	  lastlink = nextlink;
	  nextlink->name = nextname;
	  nextname[0] = '\0';
	  count++;
	}
      skip = 1;
    }

  /* Scan the directory, finding all names that match.
     For each name that matches, allocate a struct globval
     on the stack and store the name in it.
     Chain those structs together; lastlink is the front of the chain.  */
  while (!skip)
    {
      int flags;		/* Flags passed to fnmatch (). */
#if defined (SHELL)
      /* Make globbing interruptible in the bash shell. */
      if (interrupt_state)
	{
	  closedir (d);
	  lose = 1;
	  goto lost;
	}
#endif /* SHELL */
	  
      dp = readdir (d);
      if (dp == NULL)
	break;

      /* If this directory entry is not to be used, try again. */
      if (!REAL_DIR_ENTRY (dp))
	continue;

      /* If a dot must be explicity matched, check to see if they do. */
      if (noglob_dot_filenames && dp->d_name[0] == '.' && pat[0] != '.' &&
	    (pat[0] != '\\' || pat[1] != '.'))
	continue;

      flags = (noglob_dot_filenames ? FNM_PERIOD : 0) | FNM_PATHNAME;

      if (fnmatch (pat, dp->d_name, flags) != FNM_NOMATCH)
	{
	  nextlink = (struct globval *) alloca (sizeof (struct globval));
	  nextlink->next = lastlink;
	  nextname = (char *) xmalloc (D_NAMLEN (dp) + 1);
	  if (nextname == NULL)
	    {
	      lose = 1;
	      break;
	    }
	  lastlink = nextlink;
	  nextlink->name = nextname;
	  bcopy (dp->d_name, nextname, D_NAMLEN (dp) + 1);
	  ++count;
	}
    }
  (void) closedir (d);

  if (!lose)
    {
      name_vector = (char **) xmalloc ((count + 1) * sizeof (char *));
      lose |= name_vector == NULL;
    }

  /* Have we run out of memory?	 */
#if defined (SHELL)
 lost:
#endif
  if (lose)
    {
      /* Here free the strings we have got.  */
      while (lastlink)
	{
	  free (lastlink->name);
	  lastlink = lastlink->next;
	}
#if defined (SHELL)
      if (interrupt_state)
	throw_to_top_level ();
#endif /* SHELL */
      return (NULL);
    }

  /* Copy the name pointers from the linked list into the vector.  */
  for (i = 0; i < count; ++i)
    {
      name_vector[i] = lastlink->name;
      lastlink = lastlink->next;
    }

  name_vector[count] = NULL;
  return (name_vector);
}

/* Return a new array which is the concatenation of each string in ARRAY
   to DIR.  This function expects you to pass in an allocated ARRAY, and
   it takes care of free()ing that array.  Thus, you might think of this
   function as side-effecting ARRAY. */
static char **
glob_dir_to_array (dir, array)
     char *dir, **array;
{
  register unsigned int i, l;
  int add_slash;
  char **result;

  l = strlen (dir);
  if (l == 0)
    return (array);

  add_slash = dir[l - 1] != '/';

  i = 0;
  while (array[i] != NULL)
    ++i;

  result = (char **) xmalloc ((i + 1) * sizeof (char *));
  if (result == NULL)
    return (NULL);

  for (i = 0; array[i] != NULL; i++)
    {
      result[i] = (char *) xmalloc (l + (add_slash ? 1 : 0)
				   + strlen (array[i]) + 1);
      if (result[i] == NULL)
	return (NULL);
#if 1
      strcpy (result[i], dir);
      if (add_slash)
        result[i][l] = '/';
      strcpy (result[i] + l + add_slash, array[i]);
#else
      (void)sprintf (result[i], "%s%s%s", dir, add_slash ? "/" : "", array[i]);
#endif
    }
  result[i] = NULL;

  /* Free the input array.  */
  for (i = 0; array[i] != NULL; i++)
    free (array[i]);
  free ((char *) array);

  return (result);
}

/* Do globbing on PATHNAME.  Return an array of pathnames that match,
   marking the end of the array with a null-pointer as an element.
   If no pathnames match, then the array is empty (first element is null).
   If there isn't enough memory, then return NULL.
   If a file system error occurs, return -1; `errno' has the error code.  */
char **
glob_filename (pathname)
     char *pathname;
{
#ifndef strrchr
  char *strrchr();
#endif

  char **result;
  unsigned int result_size;
  char *directory_name, *filename;
  unsigned int directory_len;

  result = (char **) xmalloc (sizeof (char *));
  result_size = 1;
  if (result == NULL)
    return (NULL);

  result[0] = NULL;

  /* Find the filename.  */
  filename = strrchr (pathname, '/');
  if (filename == NULL)
    {
      filename = pathname;
      directory_name = "";
      directory_len = 0;
    }
  else
    {
      directory_len = (filename - pathname) + 1;
      directory_name = (char *) alloca (directory_len + 1);

      bcopy (pathname, directory_name, directory_len);
      directory_name[directory_len] = '\0';
      ++filename;
    }

  /* If directory_name contains globbing characters, then we
     have to expand the previous levels.  Just recurse. */
  if (glob_pattern_p (directory_name))
    {
      char **directories;
      register unsigned int i;

      if (directory_name[directory_len - 1] == '/')
	directory_name[directory_len - 1] = '\0';

      directories = glob_filename (directory_name);

      if (directories == NULL)
	goto memory_error;
      else if (directories == (char **)&glob_error_return)
	{
	  free ((char *) result);
	  return ((char **) &glob_error_return);
	}
      else if (*directories == NULL)
	{
	  free ((char *) directories);
	  free ((char *) result);
	  return ((char **) &glob_error_return);
	}

      /* We have successfully globbed the preceding directory name.
	 For each name in DIRECTORIES, call glob_vector on it and
	 FILENAME.  Concatenate the results together.  */
      for (i = 0; directories[i] != NULL; ++i)
	{
	  char **temp_results;

	  /* Scan directory even on a NULL pathname.  That way, `*h/'
	     returns only directories ending in `h', instead of all
	     files ending in `h' with a `/' appended. */
	  temp_results = glob_vector (filename, directories[i]);

	  /* Handle error cases. */
	  if (temp_results == NULL)
	    goto memory_error;
	  else if (temp_results == (char **)&glob_error_return)
	    /* This filename is probably not a directory.  Ignore it.  */
	    ;
	  else
	    {
	      char **array;
	      register unsigned int l;

	      array = glob_dir_to_array (directories[i], temp_results);
	      l = 0;
	      while (array[l] != NULL)
		++l;

	      result =
		(char **)xrealloc(result, (result_size + l) * sizeof (char *));

	      if (result == NULL)
		goto memory_error;

	      for (l = 0; array[l] != NULL; ++l)
		result[result_size++ - 1] = array[l];

	      result[result_size - 1] = NULL;

	      /* Note that the elements of ARRAY are not freed.  */
	      free ((char *) array);
	    }
	}
      /* Free the directories.  */
      for (i = 0; directories[i]; i++)
	free (directories[i]);

      free ((char *) directories);

      return (result);
    }

  /* If there is only a directory name, return it. */
  if (*filename == '\0')
    {
      result = (char **) xrealloc ((char *) result, 2 * sizeof (char *));
      if (result == NULL)
	return (NULL);
      result[0] = (char *) xmalloc (directory_len + 1);
      if (result[0] == NULL)
	goto memory_error;
      bcopy (directory_name, result[0], directory_len + 1);
      result[1] = NULL;
      return (result);
    }
  else
    {
      char **temp_results;

      /* There are no unquoted globbing characters in DIRECTORY_NAME.
	 Dequote it before we try to open the directory since there may
	 be quoted globbing characters which should be treated verbatim. */
      if (directory_len > 0)
	dequote_pathname (directory_name);

      /* We allocated a small array called RESULT, which we won't be using.
	 Free that memory now. */
      free (result);

      /* Just return what glob_vector () returns appended to the
	 directory name. */
      temp_results =
	glob_vector (filename, (directory_len == 0 ? "." : directory_name));

      if (temp_results == NULL || temp_results == (char **)&glob_error_return)
	return (temp_results);

      return (glob_dir_to_array (directory_name, temp_results));
    }

  /* We get to memory_error if the program has run out of memory, or
     if this is the shell, and we have been interrupted. */
 memory_error:
  if (result != NULL)
    {
      register unsigned int i;
      for (i = 0; result[i] != NULL; ++i)
	free (result[i]);
      free ((char *) result);
    }
#if defined (SHELL)
  if (interrupt_state)
    throw_to_top_level ();
#endif /* SHELL */
  return (NULL);
}

#if defined (TEST)

main (argc, argv)
     int argc;
     char **argv;
{
  unsigned int i;

  for (i = 1; i < argc; ++i)
    {
      char **value = glob_filename (argv[i]);
      if (value == NULL)
	puts ("Out of memory.");
      else if (value == &glob_error_return)
	perror (argv[i]);
      else
	for (i = 0; value[i] != NULL; i++)
	  puts (value[i]);
    }

  exit (0);
}
#endif	/* TEST.  */
