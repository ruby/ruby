/* C code produced by gperf version 2.5 (GNU C++ version) */
/* Command-line: gperf -p -j1 -i 1 -g -o -t -N rb_reserved_word -k1,3,$ keywords  */
struct kwtable {char *name; int id[2]; enum lex_state state;};

#define TOTAL_KEYWORDS 38
#define MIN_WORD_LENGTH 2
#define MAX_WORD_LENGTH 8
#define MIN_HASH_VALUE 6
#define MAX_HASH_VALUE 52
/* maximum key range = 47, duplicates = 0 */

#ifdef __GNUC__
inline
#endif
static unsigned int
hash (str, len)
     register char *str;
     register int unsigned len;
{
  static unsigned char asso_values[] =
    {
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 11, 53, 53, 34, 53,  1, 35,
     53,  1, 53, 53, 53, 53, 53, 53,  1, 53,
     53, 53, 53, 53, 53, 53, 53, 53, 53, 53,
     53, 53, 53, 53, 53, 53, 53, 29,  1,  2,
      1,  1,  4, 24, 53, 17, 53, 20,  9,  2,
      9, 26, 14, 53,  5,  1,  1, 16, 53, 21,
     24,  9, 53, 53, 53, 53, 53, 53,
    };
  register int hval = len;

  switch (hval)
    {
      default:
      case 3:
        hval += asso_values[str[2]];
      case 2:
      case 1:
        hval += asso_values[str[0]];
        break;
    }
  return hval + asso_values[str[len - 1]];
}

#ifdef __GNUC__
inline
#endif
struct kwtable *
rb_reserved_word (str, len)
     register char *str;
     register unsigned int len;
{
  static struct kwtable wordlist[] =
    {
      {"",}, {"",}, {"",}, {"",}, {"",}, {"",}, 
      {"end",  kEND, kEND, EXPR_END},
      {"else",  kELSE, kELSE, EXPR_BEG},
      {"case",  kCASE, kCASE, EXPR_BEG},
      {"ensure",  kENSURE, kENSURE, EXPR_BEG},
      {"module",  kMODULE, kMODULE, EXPR_BEG},
      {"elsif",  kELSIF, kELSIF, EXPR_BEG},
      {"def",  kDEF, kDEF, EXPR_FNAME},
      {"rescue",  kRESCUE, kRESCUE, EXPR_MID},
      {"not",  kNOT, kNOT, EXPR_BEG},
      {"then",  kTHEN, kTHEN, EXPR_BEG},
      {"yield",  kYIELD, kYIELD, EXPR_END},
      {"for",  kFOR, kFOR, EXPR_BEG},
      {"self",  kSELF, kSELF, EXPR_END},
      {"false",  kFALSE, kFALSE, EXPR_END},
      {"retry",  kRETRY, kRETRY, EXPR_END},
      {"return",  kRETURN, kRETURN, EXPR_MID},
      {"true",  kTRUE, kTRUE, EXPR_END},
      {"if",  kIF, kIF_MOD, EXPR_BEG},
      {"defined?",  kDEFINED, kDEFINED, EXPR_END},
      {"super",  kSUPER, kSUPER, EXPR_END},
      {"undef",  kUNDEF, kUNDEF, EXPR_FNAME},
      {"break",  kBREAK, kBREAK, EXPR_END},
      {"in",  kIN, kIN, EXPR_BEG},
      {"do",  kDO, kDO, EXPR_BEG},
      {"nil",  kNIL, kNIL, EXPR_END},
      {"until",  kUNTIL, kUNTIL_MOD, EXPR_BEG},
      {"unless",  kUNLESS, kUNLESS_MOD, EXPR_BEG},
      {"or",  kOR, kOR, EXPR_BEG},
      {"and",  kAND, kAND, EXPR_BEG},
      {"when",  kWHEN, kWHEN, EXPR_BEG},
      {"redo",  kREDO, kREDO, EXPR_END},
      {"class",  kCLASS, kCLASS, EXPR_CLASS},
      {"next",  kNEXT, kNEXT, EXPR_END},
      {"begin",  kBEGIN, kBEGIN, EXPR_BEG},
      {"END",  klEND, klEND, EXPR_END},
      {"BEGIN",  klBEGIN, klBEGIN, EXPR_END},
      {"",}, {"",}, 
      {"while",  kWHILE, kWHILE_MOD, EXPR_BEG},
      {"",}, {"",}, {"",}, {"",}, {"",}, {"",}, {"",}, 
      {"alias",  kALIAS, kALIAS, EXPR_FNAME},
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register int key = hash (str, len);

      if (key <= MAX_HASH_VALUE && key >= 0)
        {
          register char *s = wordlist[key].name;

          if (*s == *str && !strcmp (str + 1, s + 1))
            return &wordlist[key];
        }
    }
  return 0;
}
