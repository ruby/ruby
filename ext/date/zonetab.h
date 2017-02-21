/* C code produced by gperf version 3.0.4 */
/* Command-line: gperf -E -C -c -P -p -j1 -i 1 -g -o -t -N zonetab zonetab.list  */
/* Computed positions: -k'1-4,$' */

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

#line 1 "zonetab.list"

struct zone {
    int name;
    int offset;
};
static const struct zone *zonetab();
#line 9 "zonetab.list"
struct zone;
/* maximum key range = 434, duplicates = 0 */

#if (defined (__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || defined(__cplusplus) || defined(__GNUC_STDC_INLINE__)
inline
#elif defined(__GNUC__)
__inline
#endif
static unsigned int
hash (str, len)
     register const char *str;
     register unsigned int len;
{
  static const unsigned short asso_values[] =
    {
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439,  19, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439,   2,   4, 439, 439, 439,
      439, 439,   8,   6,   3, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439,   7,  63,  53,
        2,   4,  32, 110,  88,  78,  90,  68,  47, 108,
       10,  73,  81, 124,   3,   1,   4,  77, 116,  88,
       15,  96,  45,   5, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439, 439, 439, 439,
      439, 439, 439, 439, 439, 439, 439
    };
  register int hval = len;

  switch (hval)
    {
      default:
        hval += asso_values[(unsigned char)str[3]];
      /*FALLTHROUGH*/
      case 3:
        hval += asso_values[(unsigned char)str[2]];
      /*FALLTHROUGH*/
      case 2:
        hval += asso_values[(unsigned char)str[1]];
      /*FALLTHROUGH*/
      case 1:
        hval += asso_values[(unsigned char)str[0]+1];
        break;
    }
  return hval + asso_values[(unsigned char)str[len - 1]];
}

struct stringpool_t
  {
    char stringpool_str5[sizeof("r")];
    char stringpool_str6[sizeof("s")];
    char stringpool_str7[sizeof("d")];
    char stringpool_str14[sizeof("cst")];
    char stringpool_str15[sizeof("cdt")];
    char stringpool_str16[sizeof("sst")];
    char stringpool_str17[sizeof("cet")];
    char stringpool_str18[sizeof("msd")];
    char stringpool_str19[sizeof("cest")];
    char stringpool_str20[sizeof("cat")];
    char stringpool_str22[sizeof("mst")];
    char stringpool_str23[sizeof("mdt")];
    char stringpool_str24[sizeof("sast")];
    char stringpool_str25[sizeof("met")];
    char stringpool_str27[sizeof("mest")];
    char stringpool_str30[sizeof("wet")];
    char stringpool_str31[sizeof("dateline")];
    char stringpool_str32[sizeof("west")];
    char stringpool_str33[sizeof("wat")];
    char stringpool_str35[sizeof("wast")];
    char stringpool_str36[sizeof("wadt")];
    char stringpool_str37[sizeof("e")];
    char stringpool_str38[sizeof("central europe")];
    char stringpool_str39[sizeof("central asia")];
    char stringpool_str40[sizeof("west asia")];
    char stringpool_str41[sizeof("cen. australia")];
    char stringpool_str42[sizeof("central america")];
    char stringpool_str44[sizeof("est")];
    char stringpool_str45[sizeof("edt")];
    char stringpool_str46[sizeof("central european")];
    char stringpool_str47[sizeof("eet")];
    char stringpool_str48[sizeof("se asia")];
    char stringpool_str49[sizeof("eest")];
    char stringpool_str50[sizeof("eat")];
    char stringpool_str51[sizeof("z")];
    char stringpool_str52[sizeof("east")];
    char stringpool_str53[sizeof("eadt")];
    char stringpool_str54[sizeof("sa eastern")];
    char stringpool_str55[sizeof("w. europe")];
    char stringpool_str56[sizeof("c")];
    char stringpool_str57[sizeof("yst")];
    char stringpool_str58[sizeof("ydt")];
    char stringpool_str59[sizeof("kst")];
    char stringpool_str60[sizeof("clt")];
    char stringpool_str61[sizeof("eastern")];
    char stringpool_str62[sizeof("clst")];
    char stringpool_str63[sizeof("bt")];
    char stringpool_str64[sizeof("w. australia")];
    char stringpool_str65[sizeof("bst")];
    char stringpool_str66[sizeof("cct")];
    char stringpool_str67[sizeof("brt")];
    char stringpool_str69[sizeof("brst")];
    char stringpool_str71[sizeof("a")];
    char stringpool_str72[sizeof("e. europe")];
    char stringpool_str73[sizeof("at")];
    char stringpool_str74[sizeof("central")];
    char stringpool_str75[sizeof("ast")];
    char stringpool_str76[sizeof("adt")];
    char stringpool_str77[sizeof("art")];
    char stringpool_str78[sizeof("e. africa")];
    char stringpool_str79[sizeof("e. south america")];
    char stringpool_str80[sizeof("jst")];
    char stringpool_str81[sizeof("e. australia")];
    char stringpool_str82[sizeof("t")];
    char stringpool_str83[sizeof("nt")];
    char stringpool_str84[sizeof("n")];
    char stringpool_str85[sizeof("nst")];
    char stringpool_str86[sizeof("ndt")];
    char stringpool_str87[sizeof("canada central")];
    char stringpool_str88[sizeof("central pacific")];
    char stringpool_str89[sizeof("west pacific")];
    char stringpool_str90[sizeof("hst")];
    char stringpool_str91[sizeof("hdt")];
    char stringpool_str93[sizeof("malay peninsula")];
    char stringpool_str95[sizeof("zp6")];
    char stringpool_str97[sizeof("russian")];
    char stringpool_str98[sizeof("hast")];
    char stringpool_str99[sizeof("hadt")];
    char stringpool_str100[sizeof("gst")];
    char stringpool_str101[sizeof("zp5")];
    char stringpool_str102[sizeof("ist")];
    char stringpool_str103[sizeof("swt")];
    char stringpool_str104[sizeof("w")];
    char stringpool_str105[sizeof("zp4")];
    char stringpool_str107[sizeof("mez")];
    char stringpool_str108[sizeof("cape verde")];
    char stringpool_str109[sizeof("mesz")];
    char stringpool_str110[sizeof("greenland")];
    char stringpool_str112[sizeof("x")];
    char stringpool_str114[sizeof("mewt")];
    char stringpool_str115[sizeof("w. central africa")];
    char stringpool_str116[sizeof("k")];
    char stringpool_str117[sizeof("b")];
    char stringpool_str119[sizeof("m")];
    char stringpool_str120[sizeof("sri lanka")];
    char stringpool_str122[sizeof("fst")];
    char stringpool_str124[sizeof("iran")];
    char stringpool_str125[sizeof("sgt")];
    char stringpool_str126[sizeof("ut")];
    char stringpool_str128[sizeof("q")];
    char stringpool_str129[sizeof("nzt")];
    char stringpool_str131[sizeof("nzst")];
    char stringpool_str132[sizeof("nzdt")];
    char stringpool_str133[sizeof("myanmar")];
    char stringpool_str135[sizeof("alaskan")];
    char stringpool_str136[sizeof("pst")];
    char stringpool_str137[sizeof("pdt")];
    char stringpool_str138[sizeof("sa western")];
    char stringpool_str139[sizeof("korea")];
    char stringpool_str142[sizeof("y")];
    char stringpool_str143[sizeof("f")];
    char stringpool_str144[sizeof("akst")];
    char stringpool_str145[sizeof("akdt")];
    char stringpool_str148[sizeof("caucasus")];
    char stringpool_str150[sizeof("msk")];
    char stringpool_str151[sizeof("idle")];
    char stringpool_str153[sizeof("arabian")];
    char stringpool_str155[sizeof("o")];
    char stringpool_str156[sizeof("l")];
    char stringpool_str157[sizeof("mid-atlantic")];
    char stringpool_str160[sizeof("us eastern")];
    char stringpool_str164[sizeof("ahst")];
    char stringpool_str167[sizeof("h")];
    char stringpool_str168[sizeof("fle")];
    char stringpool_str169[sizeof("i")];
    char stringpool_str170[sizeof("north asia")];
    char stringpool_str171[sizeof("n. central asia")];
    char stringpool_str172[sizeof("north asia east")];
    char stringpool_str174[sizeof("sa pacific")];
    char stringpool_str177[sizeof("south africa")];
    char stringpool_str181[sizeof("aus eastern")];
    char stringpool_str182[sizeof("atlantic")];
    char stringpool_str186[sizeof("mexico")];
    char stringpool_str188[sizeof("mountain")];
    char stringpool_str190[sizeof("china")];
    char stringpool_str191[sizeof("azores")];
    char stringpool_str192[sizeof("india")];
    char stringpool_str194[sizeof("u")];
    char stringpool_str195[sizeof("arabic")];
    char stringpool_str196[sizeof("greenwich")];
    char stringpool_str197[sizeof("new zealand")];
    char stringpool_str198[sizeof("hawaiian")];
    char stringpool_str199[sizeof("g")];
    char stringpool_str200[sizeof("romance")];
    char stringpool_str203[sizeof("arab")];
    char stringpool_str204[sizeof("samoa")];
    char stringpool_str205[sizeof("v")];
    char stringpool_str206[sizeof("p")];
    char stringpool_str207[sizeof("gmt")];
    char stringpool_str208[sizeof("tasmania")];
    char stringpool_str209[sizeof("fwt")];
    char stringpool_str211[sizeof("newfoundland")];
    char stringpool_str217[sizeof("nepal")];
    char stringpool_str218[sizeof("aus central")];
    char stringpool_str221[sizeof("gtb")];
    char stringpool_str223[sizeof("vladivostok")];
    char stringpool_str229[sizeof("utc")];
    char stringpool_str233[sizeof("ekaterinburg")];
    char stringpool_str265[sizeof("us mountain")];
    char stringpool_str269[sizeof("jerusalem")];
    char stringpool_str272[sizeof("yakutsk")];
    char stringpool_str279[sizeof("pacific sa")];
    char stringpool_str282[sizeof("tonga")];
    char stringpool_str314[sizeof("afghanistan")];
    char stringpool_str319[sizeof("idlw")];
    char stringpool_str322[sizeof("pacific")];
    char stringpool_str327[sizeof("taipei")];
    char stringpool_str328[sizeof("egypt")];
    char stringpool_str392[sizeof("tokyo")];
    char stringpool_str438[sizeof("fiji")];
  };
static const struct stringpool_t stringpool_contents =
  {
    "r",
    "s",
    "d",
    "cst",
    "cdt",
    "sst",
    "cet",
    "msd",
    "cest",
    "cat",
    "mst",
    "mdt",
    "sast",
    "met",
    "mest",
    "wet",
    "dateline",
    "west",
    "wat",
    "wast",
    "wadt",
    "e",
    "central europe",
    "central asia",
    "west asia",
    "cen. australia",
    "central america",
    "est",
    "edt",
    "central european",
    "eet",
    "se asia",
    "eest",
    "eat",
    "z",
    "east",
    "eadt",
    "sa eastern",
    "w. europe",
    "c",
    "yst",
    "ydt",
    "kst",
    "clt",
    "eastern",
    "clst",
    "bt",
    "w. australia",
    "bst",
    "cct",
    "brt",
    "brst",
    "a",
    "e. europe",
    "at",
    "central",
    "ast",
    "adt",
    "art",
    "e. africa",
    "e. south america",
    "jst",
    "e. australia",
    "t",
    "nt",
    "n",
    "nst",
    "ndt",
    "canada central",
    "central pacific",
    "west pacific",
    "hst",
    "hdt",
    "malay peninsula",
    "zp6",
    "russian",
    "hast",
    "hadt",
    "gst",
    "zp5",
    "ist",
    "swt",
    "w",
    "zp4",
    "mez",
    "cape verde",
    "mesz",
    "greenland",
    "x",
    "mewt",
    "w. central africa",
    "k",
    "b",
    "m",
    "sri lanka",
    "fst",
    "iran",
    "sgt",
    "ut",
    "q",
    "nzt",
    "nzst",
    "nzdt",
    "myanmar",
    "alaskan",
    "pst",
    "pdt",
    "sa western",
    "korea",
    "y",
    "f",
    "akst",
    "akdt",
    "caucasus",
    "msk",
    "idle",
    "arabian",
    "o",
    "l",
    "mid-atlantic",
    "us eastern",
    "ahst",
    "h",
    "fle",
    "i",
    "north asia",
    "n. central asia",
    "north asia east",
    "sa pacific",
    "south africa",
    "aus eastern",
    "atlantic",
    "mexico",
    "mountain",
    "china",
    "azores",
    "india",
    "u",
    "arabic",
    "greenwich",
    "new zealand",
    "hawaiian",
    "g",
    "romance",
    "arab",
    "samoa",
    "v",
    "p",
    "gmt",
    "tasmania",
    "fwt",
    "newfoundland",
    "nepal",
    "aus central",
    "gtb",
    "vladivostok",
    "utc",
    "ekaterinburg",
    "us mountain",
    "jerusalem",
    "yakutsk",
    "pacific sa",
    "tonga",
    "afghanistan",
    "idlw",
    "pacific",
    "taipei",
    "egypt",
    "tokyo",
    "fiji"
  };
#define stringpool ((const char *) &stringpool_contents)
#ifdef __GNUC__
__inline
#if defined __GNUC_STDC_INLINE__ || defined __GNUC_GNU_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif
const struct zone *
zonetab (str, len)
     register const char *str;
     register unsigned int len;
{
  enum
    {
      TOTAL_KEYWORDS = 170,
      MIN_WORD_LENGTH = 1,
      MAX_WORD_LENGTH = 17,
      MIN_HASH_VALUE = 5,
      MAX_HASH_VALUE = 438
    };

  static const struct zone wordlist[] =
    {
      {-1}, {-1}, {-1}, {-1}, {-1},
#line 37 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str5),   -5*3600},
#line 38 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str6),   -6*3600},
#line 24 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str7),    4*3600},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 15 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str14), -6*3600},
#line 16 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str15), -5*3600},
#line 85 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str16),  2*3600},
#line 71 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str17),  1*3600},
#line 90 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str18),  4*3600},
#line 79 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str19), 2*3600},
#line 65 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str20),-10*3600},
      {-1},
#line 17 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str22), -7*3600},
#line 18 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str23), -6*3600},
#line 84 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str24), 2*3600},
#line 73 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str25),  1*3600},
      {-1},
#line 82 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str27), 2*3600},
      {-1}, {-1},
#line 47 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str30),  0*3600},
#line 128 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str31),               -43200},
#line 78 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str32), 1*3600},
#line 77 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str33),  1*3600},
      {-1},
#line 95 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str35), 7*3600},
#line 98 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str36), 8*3600},
#line 25 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str37),    5*3600},
#line 123 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str38),           3600},
#line 122 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str39),            21600},
#line 178 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str40),               18000},
#line 120 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str41),          34200},
#line 121 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str42),        -21600},
      {-1},
#line 13 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str44), -5*3600},
#line 14 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str45), -4*3600},
#line 124 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str46),         3600},
#line 80 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str47),  2*3600},
#line 164 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str48),                 25200},
#line 88 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str49), 3*3600},
#line 87 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str50),  3*3600},
#line 45 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str51),    0*3600},
#line 101 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str52),10*3600},
#line 103 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str53),11*3600},
#line 160 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str54),             -10800},
#line 177 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str55),                3600},
#line 23 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str56),    3*3600},
#line 63 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str57), -9*3600},
#line 59 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str58), -8*3600},
#line 100 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str59),  9*3600},
#line 57 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str60), -4*3600},
#line 133 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str61),                -18000},
#line 54 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str62),-3*3600},
#line 86 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str63),   3*3600},
#line 175 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str64),            28800},
#line 70 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str65),  1*3600},
#line 96 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str66),  8*3600},
#line 53 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str67), -3*3600},
      {-1},
#line 49 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str69),-2*3600},
      {-1},
#line 21 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str71),    1*3600},
#line 131 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str72),                7200},
#line 48 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str73),  -2*3600},
#line 126 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str74),                -21600},
#line 56 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str75), -4*3600},
#line 52 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str76), -3*3600},
#line 51 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str77), -3*3600},
#line 129 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str78),               10800},
#line 132 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str79),       -10800},
#line 99 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str80),  9*3600},
#line 130 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str81),            36000},
#line 39 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str82),   -7*3600},
#line 68 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str83),  -11*3600},
#line 33 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str84),   -1*3600},
#line 55 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str85), -(3*3600+1800)},
#line 50 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str86), -(2*3600+1800)},
#line 117 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str87),         -21600},
#line 125 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str88),         39600},
#line 179 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str89),            36000},
#line 67 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str90),-10*3600},
#line 62 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str91), -9*3600},
      {-1},
#line 165 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str93),         28800},
      {-1},
#line 94 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str95),  6*3600},
      {-1},
#line 159 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str97),                 10800},
#line 66 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str98),-10*3600},
#line 61 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str99),-9*3600},
#line 102 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str100), 10*3600},
#line 92 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str101),  5*3600},
#line 93 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str102),  (5*3600+1800)},
#line 76 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str103),  1*3600},
#line 42 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str104),  -10*3600},
#line 91 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str105),  4*3600},
      {-1},
#line 75 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str107),  1*3600},
#line 118 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str108),              -3600},
#line 83 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str109), 2*3600},
#line 138 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str110),              -10800},
      {-1},
#line 43 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str112),  -11*3600},
      {-1},
#line 74 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str114), 1*3600},
#line 176 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str115),        3600},
#line 30 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str116),   10*3600},
#line 22 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str117),    2*3600},
      {-1},
#line 32 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str119),   12*3600},
#line 167 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str120),               21600},
      {-1},
#line 81 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str122),  2*3600},
      {-1},
#line 143 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str124),                    12600},
#line 97 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str125),  8*3600},
#line 11 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str126),   0*3600},
      {-1},
#line 36 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str128),   -4*3600},
#line 106 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str129), 12*3600},
      {-1},
#line 105 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str131),12*3600},
#line 107 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str132),13*3600},
#line 149 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str133),                 23400},
      {-1},
#line 109 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str135),                -32400},
#line 19 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str136), -8*3600},
#line 20 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str137), -7*3600},
#line 162 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str138),             -14400},
#line 145 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str139),                   32400},
      {-1}, {-1},
#line 44 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str142),  -12*3600},
#line 26 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str143),    6*3600},
#line 60 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str144),-9*3600},
#line 58 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str145),-8*3600},
      {-1}, {-1},
#line 119 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str148),                14400},
      {-1},
#line 89 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str150),  3*3600},
#line 104 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str151),12*3600},
      {-1},
#line 111 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str153),                 14400},
      {-1},
#line 34 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str155),   -2*3600},
#line 31 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str156),   11*3600},
#line 147 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str157),            -7200},
      {-1}, {-1},
#line 172 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str160),             -18000},
      {-1}, {-1}, {-1},
#line 64 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str164),-10*3600},
      {-1}, {-1},
#line 28 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str167),    8*3600},
#line 137 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str168),                      7200},
#line 29 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str169),    9*3600},
#line 155 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str170),              25200},
#line 150 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str171),         21600},
#line 154 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str172),         28800},
      {-1},
#line 161 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str174),             -18000},
      {-1}, {-1},
#line 166 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str177),             7200},
      {-1}, {-1}, {-1},
#line 115 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str181),             36000},
#line 113 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str182),               -14400},
      {-1}, {-1}, {-1},
#line 146 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str186),                 -21600},
      {-1},
#line 148 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str188),               -25200},
      {-1},
#line 127 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str190),                   28800},
#line 116 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str191),                  -3600},
#line 142 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str192),                   19800},
      {-1},
#line 40 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str194),   -8*3600},
#line 112 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str195),                  10800},
#line 139 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str196),                   0},
#line 152 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str197),             43200},
#line 141 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str198),               -36000},
#line 27 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str199),    7*3600},
#line 158 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str200),                  3600},
      {-1}, {-1},
#line 110 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str203),                    10800},
#line 163 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str204),                  -39600},
#line 41 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str205),   -9*3600},
#line 35 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str206),   -3*3600},
#line 12 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str207),  0*3600},
#line 169 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str208),                36000},
#line 72 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str209),  1*3600},
      {-1},
#line 153 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str211),           -12600},
      {-1}, {-1}, {-1}, {-1}, {-1},
#line 151 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str217),                   20700},
#line 114 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str218),             34200},
      {-1}, {-1},
#line 140 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str221),                      7200},
      {-1},
#line 174 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str223),             36000},
      {-1}, {-1}, {-1}, {-1}, {-1},
#line 46 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str229),  0*3600},
      {-1}, {-1}, {-1},
#line 135 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str233),            18000},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1},
#line 173 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str265),            -25200},
      {-1}, {-1}, {-1},
#line 144 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str269),                7200},
      {-1}, {-1},
#line 180 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str272),                 32400},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 156 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str279),             -14400},
      {-1}, {-1},
#line 171 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str282),                   46800},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1},
#line 108 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str314),             16200},
      {-1}, {-1}, {-1}, {-1},
#line 69 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str319),-12*3600},
      {-1}, {-1},
#line 157 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str322),                -28800},
      {-1}, {-1}, {-1}, {-1},
#line 168 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str327),                  28800},
#line 134 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str328),                    7200},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 170 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str392),                   32400},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 136 "zonetab.list"
      {offsetof(struct stringpool_t, stringpool_str438),                    43200}
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register int key = hash (str, len);

      if (key <= MAX_HASH_VALUE && key >= 0)
        {
          register int o = wordlist[key].name;
          if (o >= 0)
            {
              register const char *s = o + stringpool;

              if (*str == *s && !strncmp (str + 1, s + 1, len - 1) && s[len] == '\0')
                return &wordlist[key];
            }
        }
    }
  return 0;
}
#line 181 "zonetab.list"

