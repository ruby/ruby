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

#ifndef	_FNMATCH_H

#define	_FNMATCH_H	1

/* Bits set in the FLAGS argument to `fnmatch'.  */
#define	FNM_PATHNAME	(1 << 0)/* No wildcard can ever match `/'.  */
#define	FNM_NOESCAPE	(1 << 1)/* Backslashes don't quote special chars.  */
#define	FNM_PERIOD	(1 << 2)/* Leading `.' is matched only explicitly.  */
#define	__FNM_FLAGS	(FNM_PATHNAME|FNM_NOESCAPE|FNM_PERIOD)

/* Value returned by `fnmatch' if STRING does not match PATTERN.  */
#define	FNM_NOMATCH	1

/* Match STRING against the filename pattern PATTERN,
   returning zero if it matches, FNM_NOMATCH if not.  */
extern int fnmatch();

#endif /* fnmatch.h */
