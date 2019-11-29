#ifndef INTERNAL_ENC_H /* -*- C -*- */
#define INTERNAL_ENC_H
/**
 * @file
 * @brief      Internal header for Encoding.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */


/* us_ascii.c */
#ifdef RUBY_ENCODING_H
extern rb_encoding OnigEncodingUS_ASCII;
#endif

/* utf_8.c */
#ifdef RUBY_ENCODING_H
extern rb_encoding OnigEncodingUTF_8;
#endif

#endif /* INTERNAL_ENC_H */
