/* C code produced by gperf version 2.7.2 */
/* Command-line: gperf -p -j1 -i 1 -g -o -t -N rb_reserved_word -k'1,3,$' ./keywords  */
struct kwtable {char *name; int id[2]; enum lex_state state;};

#define TOTAL_KEYWORDS 40
#define MIN_WORD_LENGTH 2
#define MAX_WORD_LENGTH 8
#define MIN_HASH_VALUE 6
#define MAX_HASH_VALUE 55
/* maximum key range = 50, duplicates = 0 */

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
  static unsigned char asso_values[] =
    {
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 11, 56, 56, 36, 56,  1, 37,
      31,  1, 56, 56, 56, 56, 29, 56,  1, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56,  1, 56, 32,  1,  2,
       1,  1,  4, 23, 56, 17, 56, 20,  9,  2,
       9, 26, 14, 56,  5,  1,  1, 16, 56, 21,
      20,  9, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56, 56, 56, 56, 56,
      56, 56, 56, 56, 56, 56
    };
  register int hval = len;

  switch (hval)
    {
      default:
      case 3:
        hval += asso_values[(unsigned char)str[2]];
      case 2:
      case 1:
        hval += asso_values[(unsigned char)str[0]];
        break;
    }
  return hval + asso_values[(unsigned char)str[len - 1]];
}

static
#ifdef __GNUC__
__inline
#endif
struct kwtable *
rb_reserved_word (str, len)
     register const char *str;
     register unsigned int len;
{
  static struct kwtable wordlist[] =
    {
      {""}, {""}, {""}, {""}, {""}, {""},
      {"end", kEND, kEND, EXPR_END},
      {"else", kELSE, kELSE, EXPR_BEG},
      {"case", kCASE, kCASE, EXPR_BEG},
      {"ensure", kENSURE, kENSURE, EXPR_BEG},
      {"module", kMODULE, kMODULE, EXPR_BEG},
      {"elsif", kELSIF, kELSIF, EXPR_BEG},
      {"def", kDEF, kDEF, EXPR_FNAME},
      {"rescue", kRESCUE, kRESCUE_MOD, EXPR_MID},
      {"not", kNOT, kNOT, EXPR_BEG},
      {"then", kTHEN, kTHEN, EXPR_BEG},
      {"yield", kYIELD, kYIELD, EXPR_ARG},
      {"for", kFOR, kFOR, EXPR_BEG},
      {"self", kSELF, kSELF, EXPR_END},
      {"false", kFALSE, kFALSE, EXPR_END},
      {"retry", kRETRY, kRETRY, EXPR_END},
      {"return", kRETURN, kRETURN, EXPR_MID},
      {"true", kTRUE, kTRUE, EXPR_END},
      {"if", kIF, kIF_MOD, EXPR_BEG},
      {"defined?", kDEFINED, kDEFINED, EXPR_ARG},
      {"super", kSUPER, kSUPER, EXPR_ARG},
      {"undef", kUNDEF, kUNDEF, EXPR_FNAME},
      {"break", kBREAK, kBREAK, EXPR_END},
      {"in", kIN, kIN, EXPR_BEG},
      {"do", kDO, kDO, EXPR_BEG},
      {"nil", kNIL, kNIL, EXPR_END},
      {"until", kUNTIL, kUNTIL_MOD, EXPR_BEG},
      {"unless", kUNLESS, kUNLESS_MOD, EXPR_BEG},
      {"or", kOR, kOR, EXPR_BEG},
      {"next", kNEXT, kNEXT, EXPR_END},
      {"when", kWHEN, kWHEN, EXPR_BEG},
      {"redo", kREDO, kREDO, EXPR_END},
      {"and", kAND, kAND, EXPR_BEG},
      {"begin", kBEGIN, kBEGIN, EXPR_BEG},
      {"__LINE__", k__LINE__, k__LINE__, EXPR_END},
      {"class", kCLASS, kCLASS, EXPR_CLASS},
      {"__FILE__", k__FILE__, k__FILE__, EXPR_END},
      {"END", klEND, klEND, EXPR_END},
      {"BEGIN", klBEGIN, klBEGIN, EXPR_END},
      {"while", kWHILE, kWHILE_MOD, EXPR_BEG},
      {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""}, {""},
      {""},
      {"alias", kALIAS, kALIAS, EXPR_FNAME}
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
