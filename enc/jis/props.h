/* C code produced by gperf version 3.0.4 */
/* Command-line: gperf -k1,3 -7 -c -j1 -i1 -t -C -P -t --ignore-case -H onig_jis_property_hash -Q onig_jis_property_pool -N onig_jis_property enc/jis/props.kwd  */

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

#line 1 "enc/jis/props.kwd"
/* -*- c -*- */
#define GPERF_DOWNCASE 1
#define GPERF_CASE_STRNCMP 1

static inline int
gperf_case_strncmp(const char *s1, const char *s2, unsigned int n)
{
    const UChar *str = (const UChar *)s1;
    const UChar *s = (const UChar *)s2;
    return onigenc_with_ascii_strnicmp(ONIG_ENCODING_ASCII, str, str + n, s, n);
}

enum onigenc_jis_ctype {
    onigenc_jis_min = ONIGENC_MAX_STD_CTYPE,
    onigenc_jis_hiragana,
    onigenc_jis_katakana,
    onigenc_jis_han,
    onigenc_jis_latin,
    onigenc_jis_greek,
    onigenc_jis_cyrillic,
    onigenc_jis_max
};

enum {PropertyListNum = onigenc_jis_max - onigenc_jis_min - 1};

static const OnigCodePoint* const PropertyList[PropertyListNum] = {
    CR_Hiragana,
    CR_Katakana,
    CR_Han,
    CR_Latin,
    CR_Greek,
    CR_Cyrillic,
};

struct enc_property {
    signed char name;
    unsigned char ctype;
};

static const struct enc_property *onig_jis_property(const char *str, unsigned int len);
#line 43 "enc/jis/props.kwd"
struct enc_property;

#define TOTAL_KEYWORDS 6
#define MIN_WORD_LENGTH 3
#define MAX_WORD_LENGTH 8
#define MIN_HASH_VALUE 5
#define MAX_HASH_VALUE 12
/* maximum key range = 8, duplicates = 0 */

#ifndef GPERF_DOWNCASE
#define GPERF_DOWNCASE 1
static unsigned char gperf_downcase[256] =
  {
      0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,
     15,  16,  17,  18,  19,  20,  21,  22,  23,  24,  25,  26,  27,  28,  29,
     30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,
     45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,
     60,  61,  62,  63,  64,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106,
    107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
    122,  91,  92,  93,  94,  95,  96,  97,  98,  99, 100, 101, 102, 103, 104,
    105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
    120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
    150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164,
    165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179,
    180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194,
    195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209,
    210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
    225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
    240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254,
    255
  };
#endif

#ifndef GPERF_CASE_STRNCMP
#define GPERF_CASE_STRNCMP 1
static int
gperf_case_strncmp (s1, s2, n)
     register const char *s1;
     register const char *s2;
     register unsigned int n;
{
  for (; n > 0;)
    {
      unsigned char c1 = gperf_downcase[(unsigned char)*s1++];
      unsigned char c2 = gperf_downcase[(unsigned char)*s2++];
      if (c1 != 0 && c1 == c2)
        {
          n--;
          continue;
        }
      return (int)c1 - (int)c2;
    }
  return 0;
}
#endif

#if (defined (__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || defined(__cplusplus) || defined(__GNUC_STDC_INLINE__)
inline
#elif defined(__GNUC__)
__inline
#endif
static unsigned int
onig_jis_property_hash (str, len)
     register const char *str;
     register unsigned int len;
{
  static const unsigned char asso_values[] =
    {
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13,  3, 13,  2,
      13,  1,  1, 13, 13,  2,  1, 13,  1, 13,
      13, 13,  1, 13,  1, 13, 13, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13, 13,  3,
      13,  2, 13,  1,  1, 13, 13,  2,  1, 13,
       1, 13, 13, 13,  1, 13,  1, 13, 13, 13,
      13, 13, 13, 13, 13, 13, 13, 13
    };
  return len + asso_values[(unsigned char)str[2]] + asso_values[(unsigned char)str[0]];
}

struct onig_jis_property_pool_t
  {
    char onig_jis_property_pool_str5[sizeof("han")];
    char onig_jis_property_pool_str7[sizeof("latin")];
    char onig_jis_property_pool_str8[sizeof("greek")];
    char onig_jis_property_pool_str10[sizeof("hiragana")];
    char onig_jis_property_pool_str11[sizeof("katakana")];
    char onig_jis_property_pool_str12[sizeof("cyrillic")];
  };
static const struct onig_jis_property_pool_t onig_jis_property_pool_contents =
  {
    "han",
    "latin",
    "greek",
    "hiragana",
    "katakana",
    "cyrillic"
  };
#define onig_jis_property_pool ((const char *) &onig_jis_property_pool_contents)
#ifdef __GNUC__
__inline
#if defined __GNUC_STDC_INLINE__ || defined __GNUC_GNU_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif
const struct enc_property *
onig_jis_property (str, len)
     register const char *str;
     register unsigned int len;
{
  static const struct enc_property wordlist[] =
    {
      {-1}, {-1}, {-1}, {-1}, {-1},
#line 48 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str5),      onigenc_jis_han},
      {-1},
#line 49 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str7),    onigenc_jis_latin},
#line 50 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str8),    onigenc_jis_greek},
      {-1},
#line 46 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str10), onigenc_jis_hiragana},
#line 47 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str11), onigenc_jis_katakana},
#line 51 "enc/jis/props.kwd"
      {(char)offsetof(struct onig_jis_property_pool_t, onig_jis_property_pool_str12), onigenc_jis_cyrillic}
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register int key = onig_jis_property_hash (str, len);

      if (key <= MAX_HASH_VALUE && key >= 0)
        {
          register int o = wordlist[key].name;
          if (o >= 0)
            {
              register const char *s = o + onig_jis_property_pool;

              if ((((unsigned char)*str ^ (unsigned char)*s) & ~32) == 0 && !gperf_case_strncmp (str, s, len) && s[len] == '\0')
                return &wordlist[key];
            }
        }
    }
  return 0;
}
#line 52 "enc/jis/props.kwd"

