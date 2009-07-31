/* C code produced by gperf version 3.0.3 */
/* Command-line: gperf -C -p -j1 -i 1 -g -o -t -N rb_reserved_word -k'1,3,$' keywords  */

#if !((' ' == 32) && ('!' == 33) && ('"' == 34) && ('#' == 35) \
      && ('%' == 37) && ('&' == 38) && ('\'' == 39) && ('(' == 40) \
      && (')' == 41) && ('*' == 42) && ('+' == 43) && (',' == 44) \
      && ('-' == 45) && ('.' == 46) && ('/' == 47) && ('0' == 48) \
      && ('1' == 49) && ('2' == 50) && ('3' == 51) && ('4' == 52) \
      && ('5' == 53) && ('6' == 54) && ('7' == 55) && ('8' == 56) \
      && ('9' == 57) && (':' == 58) && (';' == 59) && ('<' == 60) \
      && ('=' == 61) && ('>' == 62) && ('?' == 63) && ('A' == 65) \
      && ('B' == 66) && ('C' == 67) && ('D' == 68) && ('E' == 69) \
      && ('F' == 70) && ('G' == 71) && ('H' == 72) && ('I' == 73) \
      && ('J' == 74) && ('K' == 75) && ('L' == 76) && ('M' == 77) \
      && ('N' == 78) && ('O' == 79) && ('P' == 80) && ('Q' == 81) \
      && ('R' == 82) && ('S' == 83) && ('T' == 84) && ('U' == 85) \
      && ('V' == 86) && ('W' == 87) && ('X' == 88) && ('Y' == 89) \
      && ('Z' == 90) && ('[' == 91) && ('\\' == 92) && (']' == 93) \
      && ('^' == 94) && ('_' == 95) && ('a' == 97) && ('b' == 98) \
      && ('c' == 99) && ('d' == 100) && ('e' == 101) && ('f' == 102) \
      && ('g' == 103) && ('h' == 104) && ('i' == 105) && ('j' == 106) \
      && ('k' == 107) && ('l' == 108) && ('m' == 109) && ('n' == 110) \
      && ('o' == 111) && ('p' == 112) && ('q' == 113) && ('r' == 114) \
      && ('s' == 115) && ('t' == 116) && ('u' == 117) && ('v' == 118) \
      && ('w' == 119) && ('x' == 120) && ('y' == 121) && ('z' == 122) \
      && ('{' == 123) && ('|' == 124) && ('}' == 125) && ('~' == 126))
/* The character set is not based on ISO-646.  */
error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf@gnu.org>."
#endif

#line 1 "keywords"
struct kwtable {const char *name; int id[2]; enum lex_state state;};

#define TOTAL_KEYWORDS 40
#define MIN_WORD_LENGTH 2
#define MAX_WORD_LENGTH 8
#define MIN_HASH_VALUE 6
#define MAX_HASH_VALUE 50
/* maximum key range = 45, duplicates = 0 */

#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif
static unsigned int
hash (str, len)
     register const char *str;
     register unsigned int len;
{
  static const unsigned char asso_values[] =
    {
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 23, 51, 51, 13, 51,  1,  1,
      11, 12, 51, 51, 51, 51, 10, 51, 12, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 11, 51, 13,  1, 26,
       4,  1,  8, 28, 51, 23, 51,  1,  1, 27,
       5, 19, 21, 51,  8,  3,  3, 11, 51, 21,
      24, 16, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51, 51, 51, 51, 51,
      51, 51, 51, 51, 51, 51
    };
  register int hval = len;

  switch (hval)
    {
      default:
        hval += asso_values[(unsigned char)str[2]];
      /*FALLTHROUGH*/
      case 2:
      case 1:
        hval += asso_values[(unsigned char)str[0]];
        break;
    }
  return hval + asso_values[(unsigned char)str[len - 1]];
}

#ifdef __GNUC__
__inline
#ifdef __GNUC_STDC_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif
const struct kwtable *
rb_reserved_word (str, len)
     register const char *str;
     register unsigned int len;
{
  static const struct kwtable wordlist[] =
    {
      {""}, {""}, {""}, {""}, {""}, {""},
#line 6 "keywords"
      {"END", {klEND, klEND}, EXPR_END},
      {""},
#line 10 "keywords"
      {"break", {kBREAK, kBREAK}, EXPR_MID},
#line 16 "keywords"
      {"else", {kELSE, kELSE}, EXPR_BEG},
#line 26 "keywords"
      {"nil", {kNIL, kNIL}, EXPR_END},
#line 19 "keywords"
      {"ensure", {kENSURE, kENSURE}, EXPR_BEG},
#line 18 "keywords"
      {"end", {kEND, kEND}, EXPR_END},
#line 35 "keywords"
      {"then", {kTHEN, kTHEN}, EXPR_BEG},
#line 27 "keywords"
      {"not", {kNOT, kNOT}, EXPR_BEG},
#line 20 "keywords"
      {"false", {kFALSE, kFALSE}, EXPR_END},
#line 33 "keywords"
      {"self", {kSELF, kSELF}, EXPR_END},
#line 17 "keywords"
      {"elsif", {kELSIF, kELSIF}, EXPR_VALUE},
#line 30 "keywords"
      {"rescue", {kRESCUE, kRESCUE_MOD}, EXPR_MID},
#line 36 "keywords"
      {"true", {kTRUE, kTRUE}, EXPR_END},
#line 39 "keywords"
      {"until", {kUNTIL, kUNTIL_MOD}, EXPR_VALUE},
#line 38 "keywords"
      {"unless", {kUNLESS, kUNLESS_MOD}, EXPR_VALUE},
#line 32 "keywords"
      {"return", {kRETURN, kRETURN}, EXPR_MID},
#line 13 "keywords"
      {"def", {kDEF, kDEF}, EXPR_FNAME},
#line 8 "keywords"
      {"and", {kAND, kAND}, EXPR_VALUE},
#line 15 "keywords"
      {"do", {kDO, kDO}, EXPR_BEG},
#line 42 "keywords"
      {"yield", {kYIELD, kYIELD}, EXPR_ARG},
#line 21 "keywords"
      {"for", {kFOR, kFOR}, EXPR_VALUE},
#line 37 "keywords"
      {"undef", {kUNDEF, kUNDEF}, EXPR_FNAME},
#line 28 "keywords"
      {"or", {kOR, kOR}, EXPR_VALUE},
#line 23 "keywords"
      {"in", {kIN, kIN}, EXPR_VALUE},
#line 40 "keywords"
      {"when", {kWHEN, kWHEN}, EXPR_VALUE},
#line 31 "keywords"
      {"retry", {kRETRY, kRETRY}, EXPR_END},
#line 22 "keywords"
      {"if", {kIF, kIF_MOD}, EXPR_VALUE},
#line 11 "keywords"
      {"case", {kCASE, kCASE}, EXPR_VALUE},
#line 29 "keywords"
      {"redo", {kREDO, kREDO}, EXPR_END},
#line 25 "keywords"
      {"next", {kNEXT, kNEXT}, EXPR_MID},
#line 34 "keywords"
      {"super", {kSUPER, kSUPER}, EXPR_ARG},
#line 24 "keywords"
      {"module", {kMODULE, kMODULE}, EXPR_VALUE},
#line 9 "keywords"
      {"begin", {kBEGIN, kBEGIN}, EXPR_BEG},
#line 3 "keywords"
      {"__LINE__", {k__LINE__, k__LINE__}, EXPR_END},
#line 4 "keywords"
      {"__FILE__", {k__FILE__, k__FILE__}, EXPR_END},
#line 5 "keywords"
      {"BEGIN", {klBEGIN, klBEGIN}, EXPR_END},
#line 14 "keywords"
      {"defined?", {kDEFINED, kDEFINED}, EXPR_ARG},
#line 7 "keywords"
      {"alias", {kALIAS, kALIAS}, EXPR_FNAME},
      {""}, {""},
#line 12 "keywords"
      {"class", {kCLASS, kCLASS}, EXPR_CLASS},
      {""}, {""},
#line 41 "keywords"
      {"while", {kWHILE, kWHILE_MOD}, EXPR_VALUE}
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register int key = hash (str, len);

      if (key <= MAX_HASH_VALUE && key >= 0)
        {
          register const char *s = wordlist[key].name;

          if (*str == *s && !strcmp (str + 1, s + 1))
            return &wordlist[key];
        }
    }
  return 0;
}
