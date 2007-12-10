#define TRANSCODE_DATA
#include "transcode_data.h"

static const unsigned char
from_ISO_8859_1_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_1_infos[129] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC2','\xA1'), output2('\xC2','\xA2'),
     output2('\xC2','\xA3'), output2('\xC2','\xA4'),
     output2('\xC2','\xA5'), output2('\xC2','\xA6'),
     output2('\xC2','\xA7'), output2('\xC2','\xA8'),
     output2('\xC2','\xA9'), output2('\xC2','\xAA'),
     output2('\xC2','\xAB'), output2('\xC2','\xAC'),
     output2('\xC2','\xAD'), output2('\xC2','\xAE'),
     output2('\xC2','\xAF'), output2('\xC2','\xB0'),
     output2('\xC2','\xB1'), output2('\xC2','\xB2'),
     output2('\xC2','\xB3'), output2('\xC2','\xB4'),
     output2('\xC2','\xB5'), output2('\xC2','\xB6'),
     output2('\xC2','\xB7'), output2('\xC2','\xB8'),
     output2('\xC2','\xB9'), output2('\xC2','\xBA'),
     output2('\xC2','\xBB'), output2('\xC2','\xBC'),
     output2('\xC2','\xBD'), output2('\xC2','\xBE'),
     output2('\xC2','\xBF'), output2('\xC3','\x80'),
     output2('\xC3','\x81'), output2('\xC3','\x82'),
     output2('\xC3','\x83'), output2('\xC3','\x84'),
     output2('\xC3','\x85'), output2('\xC3','\x86'),
     output2('\xC3','\x87'), output2('\xC3','\x88'),
     output2('\xC3','\x89'), output2('\xC3','\x8A'),
     output2('\xC3','\x8B'), output2('\xC3','\x8C'),
     output2('\xC3','\x8D'), output2('\xC3','\x8E'),
     output2('\xC3','\x8F'), output2('\xC3','\x90'),
     output2('\xC3','\x91'), output2('\xC3','\x92'),
     output2('\xC3','\x93'), output2('\xC3','\x94'),
     output2('\xC3','\x95'), output2('\xC3','\x96'),
     output2('\xC3','\x97'), output2('\xC3','\x98'),
     output2('\xC3','\x99'), output2('\xC3','\x9A'),
     output2('\xC3','\x9B'), output2('\xC3','\x9C'),
     output2('\xC3','\x9D'), output2('\xC3','\x9E'),
     output2('\xC3','\x9F'), output2('\xC3','\xA0'),
     output2('\xC3','\xA1'), output2('\xC3','\xA2'),
     output2('\xC3','\xA3'), output2('\xC3','\xA4'),
     output2('\xC3','\xA5'), output2('\xC3','\xA6'),
     output2('\xC3','\xA7'), output2('\xC3','\xA8'),
     output2('\xC3','\xA9'), output2('\xC3','\xAA'),
     output2('\xC3','\xAB'), output2('\xC3','\xAC'),
     output2('\xC3','\xAD'), output2('\xC3','\xAE'),
     output2('\xC3','\xAF'), output2('\xC3','\xB0'),
     output2('\xC3','\xB1'), output2('\xC3','\xB2'),
     output2('\xC3','\xB3'), output2('\xC3','\xB4'),
     output2('\xC3','\xB5'), output2('\xC3','\xB6'),
     output2('\xC3','\xB7'), output2('\xC3','\xB8'),
     output2('\xC3','\xB9'), output2('\xC3','\xBA'),
     output2('\xC3','\xBB'), output2('\xC3','\xBC'),
     output2('\xC3','\xBD'), output2('\xC3','\xBE'),
     output2('\xC3','\xBF'),
};
const BYTE_LOOKUP
from_ISO_8859_1 = {
    from_ISO_8859_1_offsets,
    from_ISO_8859_1_infos
};

static const unsigned char
to_ISO_8859_1_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39,   40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, 63,
};
static const void* const
to_ISO_8859_1_C2_infos[64] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA1'), output1('\xA2'), output1('\xA3'),
     output1('\xA4'), output1('\xA5'), output1('\xA6'), output1('\xA7'),
     output1('\xA8'), output1('\xA9'), output1('\xAA'), output1('\xAB'),
     output1('\xAC'), output1('\xAD'), output1('\xAE'), output1('\xAF'),
     output1('\xB0'), output1('\xB1'), output1('\xB2'), output1('\xB3'),
     output1('\xB4'), output1('\xB5'), output1('\xB6'), output1('\xB7'),
     output1('\xB8'), output1('\xB9'), output1('\xBA'), output1('\xBB'),
     output1('\xBC'), output1('\xBD'), output1('\xBE'), output1('\xBF'),
};
static const BYTE_LOOKUP
to_ISO_8859_1_C2 = {
    to_ISO_8859_1_C2_offsets,
    to_ISO_8859_1_C2_infos
};

static const unsigned char
to_ISO_8859_1_C3_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39,   40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, 63,
};
static const void* const
to_ISO_8859_1_C3_infos[64] = {
     output1('\xC0'), output1('\xC1'), output1('\xC2'), output1('\xC3'),
     output1('\xC4'), output1('\xC5'), output1('\xC6'), output1('\xC7'),
     output1('\xC8'), output1('\xC9'), output1('\xCA'), output1('\xCB'),
     output1('\xCC'), output1('\xCD'), output1('\xCE'), output1('\xCF'),
     output1('\xD0'), output1('\xD1'), output1('\xD2'), output1('\xD3'),
     output1('\xD4'), output1('\xD5'), output1('\xD6'), output1('\xD7'),
     output1('\xD8'), output1('\xD9'), output1('\xDA'), output1('\xDB'),
     output1('\xDC'), output1('\xDD'), output1('\xDE'), output1('\xDF'),
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF0'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'), output1('\xFB'),
     output1('\xFC'), output1('\xFD'), output1('\xFE'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_1_C3 = {
    to_ISO_8859_1_C3_offsets,
    to_ISO_8859_1_C3_infos
};

static const unsigned char
to_ISO_8859_1_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_1_infos[3] = {
                 NOMAP, &to_ISO_8859_1_C2, &to_ISO_8859_1_C3,
};
const BYTE_LOOKUP
to_ISO_8859_1 = {
    to_ISO_8859_1_offsets,
    to_ISO_8859_1_infos
};

static const unsigned char
from_ISO_8859_2_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_2_infos[129] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC4','\x84'), output2('\xCB','\x98'),
     output2('\xC5','\x81'), output2('\xC2','\xA4'),
     output2('\xC4','\xBD'), output2('\xC5','\x9A'),
     output2('\xC2','\xA7'), output2('\xC2','\xA8'),
     output2('\xC5','\xA0'), output2('\xC5','\x9E'),
     output2('\xC5','\xA4'), output2('\xC5','\xB9'),
     output2('\xC2','\xAD'), output2('\xC5','\xBD'),
     output2('\xC5','\xBB'), output2('\xC2','\xB0'),
     output2('\xC4','\x85'), output2('\xCB','\x9B'),
     output2('\xC5','\x82'), output2('\xC2','\xB4'),
     output2('\xC4','\xBE'), output2('\xC5','\x9B'),
     output2('\xCB','\x87'), output2('\xC2','\xB8'),
     output2('\xC5','\xA1'), output2('\xC5','\x9F'),
     output2('\xC5','\xA5'), output2('\xC5','\xBA'),
     output2('\xCB','\x9D'), output2('\xC5','\xBE'),
     output2('\xC5','\xBC'), output2('\xC5','\x94'),
     output2('\xC3','\x81'), output2('\xC3','\x82'),
     output2('\xC4','\x82'), output2('\xC3','\x84'),
     output2('\xC4','\xB9'), output2('\xC4','\x86'),
     output2('\xC3','\x87'), output2('\xC4','\x8C'),
     output2('\xC3','\x89'), output2('\xC4','\x98'),
     output2('\xC3','\x8B'), output2('\xC4','\x9A'),
     output2('\xC3','\x8D'), output2('\xC3','\x8E'),
     output2('\xC4','\x8E'), output2('\xC4','\x90'),
     output2('\xC5','\x83'), output2('\xC5','\x87'),
     output2('\xC3','\x93'), output2('\xC3','\x94'),
     output2('\xC5','\x90'), output2('\xC3','\x96'),
     output2('\xC3','\x97'), output2('\xC5','\x98'),
     output2('\xC5','\xAE'), output2('\xC3','\x9A'),
     output2('\xC5','\xB0'), output2('\xC3','\x9C'),
     output2('\xC3','\x9D'), output2('\xC5','\xA2'),
     output2('\xC3','\x9F'), output2('\xC5','\x95'),
     output2('\xC3','\xA1'), output2('\xC3','\xA2'),
     output2('\xC4','\x83'), output2('\xC3','\xA4'),
     output2('\xC4','\xBA'), output2('\xC4','\x87'),
     output2('\xC3','\xA7'), output2('\xC4','\x8D'),
     output2('\xC3','\xA9'), output2('\xC4','\x99'),
     output2('\xC3','\xAB'), output2('\xC4','\x9B'),
     output2('\xC3','\xAD'), output2('\xC3','\xAE'),
     output2('\xC4','\x8F'), output2('\xC4','\x91'),
     output2('\xC5','\x84'), output2('\xC5','\x88'),
     output2('\xC3','\xB3'), output2('\xC3','\xB4'),
     output2('\xC5','\x91'), output2('\xC3','\xB6'),
     output2('\xC3','\xB7'), output2('\xC5','\x99'),
     output2('\xC5','\xAF'), output2('\xC3','\xBA'),
     output2('\xC5','\xB1'), output2('\xC3','\xBC'),
     output2('\xC3','\xBD'), output2('\xC5','\xA3'),
     output2('\xCB','\x99'),
};
const BYTE_LOOKUP
from_ISO_8859_2 = {
    from_ISO_8859_2_offsets,
    from_ISO_8859_2_infos
};

static const unsigned char
to_ISO_8859_2_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, 33, -1, -1, 34,   35, -1, -1, -1, -1, 36, -1, -1,
     37, -1, -1, -1, 38, -1, -1, -1,   39, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_2_C2_infos[40] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA4'), output1('\xA7'), output1('\xA8'),
     output1('\xAD'), output1('\xB0'), output1('\xB4'), output1('\xB8'),
};
static const BYTE_LOOKUP
to_ISO_8859_2_C2 = {
    to_ISO_8859_2_C2_offsets,
    to_ISO_8859_2_C2_infos
};

static const unsigned char
to_ISO_8859_2_C3_offsets[64] = {
     -1,  0,  1, -1,  2, -1, -1,  3,   -1,  4, -1,  5, -1,  6,  7, -1,
     -1, -1, -1,  8,  9, -1, 10, 11,   -1, -1, 12, -1, 13, 14, -1, 15,
     -1, 16, 17, -1, 18, -1, -1, 19,   -1, 20, -1, 21, -1, 22, 23, -1,
     -1, -1, -1, 24, 25, -1, 26, 27,   -1, -1, 28, -1, 29, 30, -1, -1,
};
static const void* const
to_ISO_8859_2_C3_infos[31] = {
     output1('\xC1'), output1('\xC2'), output1('\xC4'), output1('\xC7'),
     output1('\xC9'), output1('\xCB'), output1('\xCD'), output1('\xCE'),
     output1('\xD3'), output1('\xD4'), output1('\xD6'), output1('\xD7'),
     output1('\xDA'), output1('\xDC'), output1('\xDD'), output1('\xDF'),
     output1('\xE1'), output1('\xE2'), output1('\xE4'), output1('\xE7'),
     output1('\xE9'), output1('\xEB'), output1('\xED'), output1('\xEE'),
     output1('\xF3'), output1('\xF4'), output1('\xF6'), output1('\xF7'),
     output1('\xFA'), output1('\xFC'), output1('\xFD'),
};
static const BYTE_LOOKUP
to_ISO_8859_2_C3 = {
    to_ISO_8859_2_C3_offsets,
    to_ISO_8859_2_C3_infos
};

static const unsigned char
to_ISO_8859_2_C4_offsets[64] = {
     -1, -1,  0,  1,  2,  3,  4,  5,   -1, -1, -1, -1,  6,  7,  8,  9,
     10, 11, -1, -1, -1, -1, -1, -1,   12, 13, 14, 15, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, 16, 17, -1, -1, 18, 19, -1,
};
static const void* const
to_ISO_8859_2_C4_infos[20] = {
     output1('\xC3'), output1('\xE3'), output1('\xA1'), output1('\xB1'),
     output1('\xC6'), output1('\xE6'), output1('\xC8'), output1('\xE8'),
     output1('\xCF'), output1('\xEF'), output1('\xD0'), output1('\xF0'),
     output1('\xCA'), output1('\xEA'), output1('\xCC'), output1('\xEC'),
     output1('\xC5'), output1('\xE5'), output1('\xA5'), output1('\xB5'),
};
static const BYTE_LOOKUP
to_ISO_8859_2_C4 = {
    to_ISO_8859_2_C4_offsets,
    to_ISO_8859_2_C4_infos
};

static const unsigned char
to_ISO_8859_2_C5_offsets[64] = {
     -1,  0,  1,  2,  3, -1, -1,  4,    5, -1, -1, -1, -1, -1, -1, -1,
      6,  7, -1, -1,  8,  9, -1, -1,   10, 11, 12, 13, -1, -1, 14, 15,
     16, 17, 18, 19, 20, 21, -1, -1,   -1, -1, -1, -1, -1, -1, 22, 23,
     24, 25, -1, -1, -1, -1, -1, -1,   -1, 26, 27, 28, 29, 30, 31, -1,
};
static const void* const
to_ISO_8859_2_C5_infos[32] = {
     output1('\xA3'), output1('\xB3'), output1('\xD1'), output1('\xF1'),
     output1('\xD2'), output1('\xF2'), output1('\xD5'), output1('\xF5'),
     output1('\xC0'), output1('\xE0'), output1('\xD8'), output1('\xF8'),
     output1('\xA6'), output1('\xB6'), output1('\xAA'), output1('\xBA'),
     output1('\xA9'), output1('\xB9'), output1('\xDE'), output1('\xFE'),
     output1('\xAB'), output1('\xBB'), output1('\xD9'), output1('\xF9'),
     output1('\xDB'), output1('\xFB'), output1('\xAC'), output1('\xBC'),
     output1('\xAF'), output1('\xBF'), output1('\xAE'), output1('\xBE'),
};
static const BYTE_LOOKUP
to_ISO_8859_2_C5 = {
    to_ISO_8859_2_C5_offsets,
    to_ISO_8859_2_C5_infos
};

static const unsigned char
to_ISO_8859_2_CB_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1,  0,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    1,  2, -1,  3, -1,  4, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_2_CB_infos[5] = {
     output1('\xB7'), output1('\xA2'), output1('\xFF'), output1('\xB2'),
     output1('\xBD'),
};
static const BYTE_LOOKUP
to_ISO_8859_2_CB = {
    to_ISO_8859_2_CB_offsets,
    to_ISO_8859_2_CB_infos
};

static const unsigned char
to_ISO_8859_2_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1,  5, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_2_infos[6] = {
                 NOMAP, &to_ISO_8859_2_C2, &to_ISO_8859_2_C3, &to_ISO_8859_2_C4,
     &to_ISO_8859_2_C5, &to_ISO_8859_2_CB,
};
const BYTE_LOOKUP
to_ISO_8859_2 = {
    to_ISO_8859_2_offsets,
    to_ISO_8859_2_infos
};

static const unsigned char
from_ISO_8859_3_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, -1, 38, 39,   40, 41, 42, 43, 44, 45, -1, 46,
     47, 48, 49, 50, 51, 52, 53, 54,   55, 56, 57, 58, 59, 60, -1, 61,
     62, 63, 64, -1, 65, 66, 67, 68,   69, 70, 71, 72, 73, 74, 75, 76,
     -1, 77, 78, 79, 80, 81, 82, 83,   84, 85, 86, 87, 88, 89, 90, 91,
     92, 93, 94, -1, 95, 96, 97, 98,   99,100,101,102,103,104,105,106,
     -1,107,108,109,110,111,112,113,  114,115,116,117,118,119,120,121,
};
static const void* const
from_ISO_8859_3_infos[122] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC4','\xA6'), output2('\xCB','\x98'),
     output2('\xC2','\xA3'), output2('\xC2','\xA4'),
     output2('\xC4','\xA4'), output2('\xC2','\xA7'),
     output2('\xC2','\xA8'), output2('\xC4','\xB0'),
     output2('\xC5','\x9E'), output2('\xC4','\x9E'),
     output2('\xC4','\xB4'), output2('\xC2','\xAD'),
     output2('\xC5','\xBB'), output2('\xC2','\xB0'),
     output2('\xC4','\xA7'), output2('\xC2','\xB2'),
     output2('\xC2','\xB3'), output2('\xC2','\xB4'),
     output2('\xC2','\xB5'), output2('\xC4','\xA5'),
     output2('\xC2','\xB7'), output2('\xC2','\xB8'),
     output2('\xC4','\xB1'), output2('\xC5','\x9F'),
     output2('\xC4','\x9F'), output2('\xC4','\xB5'),
     output2('\xC2','\xBD'), output2('\xC5','\xBC'),
     output2('\xC3','\x80'), output2('\xC3','\x81'),
     output2('\xC3','\x82'), output2('\xC3','\x84'),
     output2('\xC4','\x8A'), output2('\xC4','\x88'),
     output2('\xC3','\x87'), output2('\xC3','\x88'),
     output2('\xC3','\x89'), output2('\xC3','\x8A'),
     output2('\xC3','\x8B'), output2('\xC3','\x8C'),
     output2('\xC3','\x8D'), output2('\xC3','\x8E'),
     output2('\xC3','\x8F'), output2('\xC3','\x91'),
     output2('\xC3','\x92'), output2('\xC3','\x93'),
     output2('\xC3','\x94'), output2('\xC4','\xA0'),
     output2('\xC3','\x96'), output2('\xC3','\x97'),
     output2('\xC4','\x9C'), output2('\xC3','\x99'),
     output2('\xC3','\x9A'), output2('\xC3','\x9B'),
     output2('\xC3','\x9C'), output2('\xC5','\xAC'),
     output2('\xC5','\x9C'), output2('\xC3','\x9F'),
     output2('\xC3','\xA0'), output2('\xC3','\xA1'),
     output2('\xC3','\xA2'), output2('\xC3','\xA4'),
     output2('\xC4','\x8B'), output2('\xC4','\x89'),
     output2('\xC3','\xA7'), output2('\xC3','\xA8'),
     output2('\xC3','\xA9'), output2('\xC3','\xAA'),
     output2('\xC3','\xAB'), output2('\xC3','\xAC'),
     output2('\xC3','\xAD'), output2('\xC3','\xAE'),
     output2('\xC3','\xAF'), output2('\xC3','\xB1'),
     output2('\xC3','\xB2'), output2('\xC3','\xB3'),
     output2('\xC3','\xB4'), output2('\xC4','\xA1'),
     output2('\xC3','\xB6'), output2('\xC3','\xB7'),
     output2('\xC4','\x9D'), output2('\xC3','\xB9'),
     output2('\xC3','\xBA'), output2('\xC3','\xBB'),
     output2('\xC3','\xBC'), output2('\xC5','\xAD'),
     output2('\xC5','\x9D'), output2('\xCB','\x99'),
};
const BYTE_LOOKUP
from_ISO_8859_3 = {
    from_ISO_8859_3_offsets,
    from_ISO_8859_3_infos
};

static const unsigned char
to_ISO_8859_3_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, 33, 34, -1, -1, 35,   36, -1, -1, -1, -1, 37, -1, -1,
     38, -1, 39, 40, 41, 42, -1, 43,   44, -1, -1, -1, -1, 45, -1, -1,
};
static const void* const
to_ISO_8859_3_C2_infos[46] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA3'), output1('\xA4'), output1('\xA7'),
     output1('\xA8'), output1('\xAD'), output1('\xB0'), output1('\xB2'),
     output1('\xB3'), output1('\xB4'), output1('\xB5'), output1('\xB7'),
     output1('\xB8'), output1('\xBD'),
};
static const BYTE_LOOKUP
to_ISO_8859_3_C2 = {
    to_ISO_8859_3_C2_offsets,
    to_ISO_8859_3_C2_infos
};

static const unsigned char
to_ISO_8859_3_C3_offsets[64] = {
      0,  1,  2, -1,  3, -1, -1,  4,    5,  6,  7,  8,  9, 10, 11, 12,
     -1, 13, 14, 15, 16, -1, 17, 18,   -1, 19, 20, 21, 22, -1, -1, 23,
     24, 25, 26, -1, 27, -1, -1, 28,   29, 30, 31, 32, 33, 34, 35, 36,
     -1, 37, 38, 39, 40, -1, 41, 42,   -1, 43, 44, 45, 46, -1, -1, -1,
};
static const void* const
to_ISO_8859_3_C3_infos[47] = {
     output1('\xC0'), output1('\xC1'), output1('\xC2'), output1('\xC4'),
     output1('\xC7'), output1('\xC8'), output1('\xC9'), output1('\xCA'),
     output1('\xCB'), output1('\xCC'), output1('\xCD'), output1('\xCE'),
     output1('\xCF'), output1('\xD1'), output1('\xD2'), output1('\xD3'),
     output1('\xD4'), output1('\xD6'), output1('\xD7'), output1('\xD9'),
     output1('\xDA'), output1('\xDB'), output1('\xDC'), output1('\xDF'),
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE4'),
     output1('\xE7'), output1('\xE8'), output1('\xE9'), output1('\xEA'),
     output1('\xEB'), output1('\xEC'), output1('\xED'), output1('\xEE'),
     output1('\xEF'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF6'), output1('\xF7'), output1('\xF9'),
     output1('\xFA'), output1('\xFB'), output1('\xFC'),
};
static const BYTE_LOOKUP
to_ISO_8859_3_C3 = {
    to_ISO_8859_3_C3_offsets,
    to_ISO_8859_3_C3_infos
};

static const unsigned char
to_ISO_8859_3_C4_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,    0,  1,  2,  3, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  4,  5,  6,  7,
      8,  9, -1, -1, 10, 11, 12, 13,   -1, -1, -1, -1, -1, -1, -1, -1,
     14, 15, -1, -1, 16, 17, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_3_C4_infos[18] = {
     output1('\xC6'), output1('\xE6'), output1('\xC5'), output1('\xE5'),
     output1('\xD8'), output1('\xF8'), output1('\xAB'), output1('\xBB'),
     output1('\xD5'), output1('\xF5'), output1('\xA6'), output1('\xB6'),
     output1('\xA1'), output1('\xB1'), output1('\xA9'), output1('\xB9'),
     output1('\xAC'), output1('\xBC'),
};
static const BYTE_LOOKUP
to_ISO_8859_3_C4 = {
    to_ISO_8859_3_C4_offsets,
    to_ISO_8859_3_C4_infos
};

static const unsigned char
to_ISO_8859_3_C5_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  0,  1,  2,  3,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  4,  5, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1,  6,  7, -1, -1, -1,
};
static const void* const
to_ISO_8859_3_C5_infos[8] = {
     output1('\xDE'), output1('\xFE'), output1('\xAA'), output1('\xBA'),
     output1('\xDD'), output1('\xFD'), output1('\xAF'), output1('\xBF'),
};
static const BYTE_LOOKUP
to_ISO_8859_3_C5 = {
    to_ISO_8859_3_C5_offsets,
    to_ISO_8859_3_C5_infos
};

static const unsigned char
to_ISO_8859_3_CB_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    0,  1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_3_CB_infos[2] = {
     output1('\xA2'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_3_CB = {
    to_ISO_8859_3_CB_offsets,
    to_ISO_8859_3_CB_infos
};

static const unsigned char
to_ISO_8859_3_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1,  5, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_3_infos[6] = {
                 NOMAP, &to_ISO_8859_3_C2, &to_ISO_8859_3_C3, &to_ISO_8859_3_C4,
     &to_ISO_8859_3_C5, &to_ISO_8859_3_CB,
};
const BYTE_LOOKUP
to_ISO_8859_3 = {
    to_ISO_8859_3_offsets,
    to_ISO_8859_3_infos
};

static const unsigned char
from_ISO_8859_4_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_4_infos[129] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC4','\x84'), output2('\xC4','\xB8'),
     output2('\xC5','\x96'), output2('\xC2','\xA4'),
     output2('\xC4','\xA8'), output2('\xC4','\xBB'),
     output2('\xC2','\xA7'), output2('\xC2','\xA8'),
     output2('\xC5','\xA0'), output2('\xC4','\x92'),
     output2('\xC4','\xA2'), output2('\xC5','\xA6'),
     output2('\xC2','\xAD'), output2('\xC5','\xBD'),
     output2('\xC2','\xAF'), output2('\xC2','\xB0'),
     output2('\xC4','\x85'), output2('\xCB','\x9B'),
     output2('\xC5','\x97'), output2('\xC2','\xB4'),
     output2('\xC4','\xA9'), output2('\xC4','\xBC'),
     output2('\xCB','\x87'), output2('\xC2','\xB8'),
     output2('\xC5','\xA1'), output2('\xC4','\x93'),
     output2('\xC4','\xA3'), output2('\xC5','\xA7'),
     output2('\xC5','\x8A'), output2('\xC5','\xBE'),
     output2('\xC5','\x8B'), output2('\xC4','\x80'),
     output2('\xC3','\x81'), output2('\xC3','\x82'),
     output2('\xC3','\x83'), output2('\xC3','\x84'),
     output2('\xC3','\x85'), output2('\xC3','\x86'),
     output2('\xC4','\xAE'), output2('\xC4','\x8C'),
     output2('\xC3','\x89'), output2('\xC4','\x98'),
     output2('\xC3','\x8B'), output2('\xC4','\x96'),
     output2('\xC3','\x8D'), output2('\xC3','\x8E'),
     output2('\xC4','\xAA'), output2('\xC4','\x90'),
     output2('\xC5','\x85'), output2('\xC5','\x8C'),
     output2('\xC4','\xB6'), output2('\xC3','\x94'),
     output2('\xC3','\x95'), output2('\xC3','\x96'),
     output2('\xC3','\x97'), output2('\xC3','\x98'),
     output2('\xC5','\xB2'), output2('\xC3','\x9A'),
     output2('\xC3','\x9B'), output2('\xC3','\x9C'),
     output2('\xC5','\xA8'), output2('\xC5','\xAA'),
     output2('\xC3','\x9F'), output2('\xC4','\x81'),
     output2('\xC3','\xA1'), output2('\xC3','\xA2'),
     output2('\xC3','\xA3'), output2('\xC3','\xA4'),
     output2('\xC3','\xA5'), output2('\xC3','\xA6'),
     output2('\xC4','\xAF'), output2('\xC4','\x8D'),
     output2('\xC3','\xA9'), output2('\xC4','\x99'),
     output2('\xC3','\xAB'), output2('\xC4','\x97'),
     output2('\xC3','\xAD'), output2('\xC3','\xAE'),
     output2('\xC4','\xAB'), output2('\xC4','\x91'),
     output2('\xC5','\x86'), output2('\xC5','\x8D'),
     output2('\xC4','\xB7'), output2('\xC3','\xB4'),
     output2('\xC3','\xB5'), output2('\xC3','\xB6'),
     output2('\xC3','\xB7'), output2('\xC3','\xB8'),
     output2('\xC5','\xB3'), output2('\xC3','\xBA'),
     output2('\xC3','\xBB'), output2('\xC3','\xBC'),
     output2('\xC5','\xA9'), output2('\xC5','\xAB'),
     output2('\xCB','\x99'),
};
const BYTE_LOOKUP
from_ISO_8859_4 = {
    from_ISO_8859_4_offsets,
    from_ISO_8859_4_infos
};

static const unsigned char
to_ISO_8859_4_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, 33, -1, -1, 34,   35, -1, -1, -1, -1, 36, -1, 37,
     38, -1, -1, -1, 39, -1, -1, -1,   40, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_4_C2_infos[41] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA4'), output1('\xA7'), output1('\xA8'),
     output1('\xAD'), output1('\xAF'), output1('\xB0'), output1('\xB4'),
     output1('\xB8'),
};
static const BYTE_LOOKUP
to_ISO_8859_4_C2 = {
    to_ISO_8859_4_C2_offsets,
    to_ISO_8859_4_C2_infos
};

static const unsigned char
to_ISO_8859_4_C3_offsets[64] = {
     -1,  0,  1,  2,  3,  4,  5, -1,   -1,  6, -1,  7, -1,  8,  9, -1,
     -1, -1, -1, -1, 10, 11, 12, 13,   14, -1, 15, 16, 17, -1, -1, 18,
     -1, 19, 20, 21, 22, 23, 24, -1,   -1, 25, -1, 26, -1, 27, 28, -1,
     -1, -1, -1, -1, 29, 30, 31, 32,   33, -1, 34, 35, 36, -1, -1, -1,
};
static const void* const
to_ISO_8859_4_C3_infos[37] = {
     output1('\xC1'), output1('\xC2'), output1('\xC3'), output1('\xC4'),
     output1('\xC5'), output1('\xC6'), output1('\xC9'), output1('\xCB'),
     output1('\xCD'), output1('\xCE'), output1('\xD4'), output1('\xD5'),
     output1('\xD6'), output1('\xD7'), output1('\xD8'), output1('\xDA'),
     output1('\xDB'), output1('\xDC'), output1('\xDF'), output1('\xE1'),
     output1('\xE2'), output1('\xE3'), output1('\xE4'), output1('\xE5'),
     output1('\xE6'), output1('\xE9'), output1('\xEB'), output1('\xED'),
     output1('\xEE'), output1('\xF4'), output1('\xF5'), output1('\xF6'),
     output1('\xF7'), output1('\xF8'), output1('\xFA'), output1('\xFB'),
     output1('\xFC'),
};
static const BYTE_LOOKUP
to_ISO_8859_4_C3 = {
    to_ISO_8859_4_C3_offsets,
    to_ISO_8859_4_C3_infos
};

static const unsigned char
to_ISO_8859_4_C4_offsets[64] = {
      0,  1, -1, -1,  2,  3, -1, -1,   -1, -1, -1, -1,  4,  5, -1, -1,
      6,  7,  8,  9, -1, -1, 10, 11,   12, 13, -1, -1, -1, -1, -1, -1,
     -1, -1, 14, 15, -1, -1, -1, -1,   16, 17, 18, 19, -1, -1, 20, 21,
     -1, -1, -1, -1, -1, -1, 22, 23,   24, -1, -1, 25, 26, -1, -1, -1,
};
static const void* const
to_ISO_8859_4_C4_infos[27] = {
     output1('\xC0'), output1('\xE0'), output1('\xA1'), output1('\xB1'),
     output1('\xC8'), output1('\xE8'), output1('\xD0'), output1('\xF0'),
     output1('\xAA'), output1('\xBA'), output1('\xCC'), output1('\xEC'),
     output1('\xCA'), output1('\xEA'), output1('\xAB'), output1('\xBB'),
     output1('\xA5'), output1('\xB5'), output1('\xCF'), output1('\xEF'),
     output1('\xC7'), output1('\xE7'), output1('\xD3'), output1('\xF3'),
     output1('\xA2'), output1('\xA6'), output1('\xB6'),
};
static const BYTE_LOOKUP
to_ISO_8859_4_C4 = {
    to_ISO_8859_4_C4_offsets,
    to_ISO_8859_4_C4_infos
};

static const unsigned char
to_ISO_8859_4_C5_offsets[64] = {
     -1, -1, -1, -1, -1,  0,  1, -1,   -1, -1,  2,  3,  4,  5, -1, -1,
     -1, -1, -1, -1, -1, -1,  6,  7,   -1, -1, -1, -1, -1, -1, -1, -1,
      8,  9, -1, -1, -1, -1, 10, 11,   12, 13, 14, 15, -1, -1, -1, -1,
     -1, -1, 16, 17, -1, -1, -1, -1,   -1, -1, -1, -1, -1, 18, 19, -1,
};
static const void* const
to_ISO_8859_4_C5_infos[20] = {
     output1('\xD1'), output1('\xF1'), output1('\xBD'), output1('\xBF'),
     output1('\xD2'), output1('\xF2'), output1('\xA3'), output1('\xB3'),
     output1('\xA9'), output1('\xB9'), output1('\xAC'), output1('\xBC'),
     output1('\xDD'), output1('\xFD'), output1('\xDE'), output1('\xFE'),
     output1('\xD9'), output1('\xF9'), output1('\xAE'), output1('\xBE'),
};
static const BYTE_LOOKUP
to_ISO_8859_4_C5 = {
    to_ISO_8859_4_C5_offsets,
    to_ISO_8859_4_C5_infos
};

static const unsigned char
to_ISO_8859_4_CB_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1,  0,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1,  1, -1,  2, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_4_CB_infos[3] = {
     output1('\xB7'), output1('\xFF'), output1('\xB2'),
};
static const BYTE_LOOKUP
to_ISO_8859_4_CB = {
    to_ISO_8859_4_CB_offsets,
    to_ISO_8859_4_CB_infos
};

static const unsigned char
to_ISO_8859_4_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1,  5, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_4_infos[6] = {
                 NOMAP, &to_ISO_8859_4_C2, &to_ISO_8859_4_C3, &to_ISO_8859_4_C4,
     &to_ISO_8859_4_C5, &to_ISO_8859_4_CB,
};
const BYTE_LOOKUP
to_ISO_8859_4 = {
    to_ISO_8859_4_offsets,
    to_ISO_8859_4_infos
};

static const unsigned char
from_ISO_8859_5_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_5_infos[129] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
            output2('\xD0','\x81'),        output2('\xD0','\x82'),
            output2('\xD0','\x83'),        output2('\xD0','\x84'),
            output2('\xD0','\x85'),        output2('\xD0','\x86'),
            output2('\xD0','\x87'),        output2('\xD0','\x88'),
            output2('\xD0','\x89'),        output2('\xD0','\x8A'),
            output2('\xD0','\x8B'),        output2('\xD0','\x8C'),
            output2('\xC2','\xAD'),        output2('\xD0','\x8E'),
            output2('\xD0','\x8F'),        output2('\xD0','\x90'),
            output2('\xD0','\x91'),        output2('\xD0','\x92'),
            output2('\xD0','\x93'),        output2('\xD0','\x94'),
            output2('\xD0','\x95'),        output2('\xD0','\x96'),
            output2('\xD0','\x97'),        output2('\xD0','\x98'),
            output2('\xD0','\x99'),        output2('\xD0','\x9A'),
            output2('\xD0','\x9B'),        output2('\xD0','\x9C'),
            output2('\xD0','\x9D'),        output2('\xD0','\x9E'),
            output2('\xD0','\x9F'),        output2('\xD0','\xA0'),
            output2('\xD0','\xA1'),        output2('\xD0','\xA2'),
            output2('\xD0','\xA3'),        output2('\xD0','\xA4'),
            output2('\xD0','\xA5'),        output2('\xD0','\xA6'),
            output2('\xD0','\xA7'),        output2('\xD0','\xA8'),
            output2('\xD0','\xA9'),        output2('\xD0','\xAA'),
            output2('\xD0','\xAB'),        output2('\xD0','\xAC'),
            output2('\xD0','\xAD'),        output2('\xD0','\xAE'),
            output2('\xD0','\xAF'),        output2('\xD0','\xB0'),
            output2('\xD0','\xB1'),        output2('\xD0','\xB2'),
            output2('\xD0','\xB3'),        output2('\xD0','\xB4'),
            output2('\xD0','\xB5'),        output2('\xD0','\xB6'),
            output2('\xD0','\xB7'),        output2('\xD0','\xB8'),
            output2('\xD0','\xB9'),        output2('\xD0','\xBA'),
            output2('\xD0','\xBB'),        output2('\xD0','\xBC'),
            output2('\xD0','\xBD'),        output2('\xD0','\xBE'),
            output2('\xD0','\xBF'),        output2('\xD1','\x80'),
            output2('\xD1','\x81'),        output2('\xD1','\x82'),
            output2('\xD1','\x83'),        output2('\xD1','\x84'),
            output2('\xD1','\x85'),        output2('\xD1','\x86'),
            output2('\xD1','\x87'),        output2('\xD1','\x88'),
            output2('\xD1','\x89'),        output2('\xD1','\x8A'),
            output2('\xD1','\x8B'),        output2('\xD1','\x8C'),
            output2('\xD1','\x8D'),        output2('\xD1','\x8E'),
            output2('\xD1','\x8F'), output3('\xE2','\x84','\x96'),
            output2('\xD1','\x91'),        output2('\xD1','\x92'),
            output2('\xD1','\x93'),        output2('\xD1','\x94'),
            output2('\xD1','\x95'),        output2('\xD1','\x96'),
            output2('\xD1','\x97'),        output2('\xD1','\x98'),
            output2('\xD1','\x99'),        output2('\xD1','\x9A'),
            output2('\xD1','\x9B'),        output2('\xD1','\x9C'),
            output2('\xC2','\xA7'),        output2('\xD1','\x9E'),
            output2('\xD1','\x9F'),
};
const BYTE_LOOKUP
from_ISO_8859_5 = {
    from_ISO_8859_5_offsets,
    from_ISO_8859_5_infos
};

static const unsigned char
to_ISO_8859_5_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, -1, -1, -1, 33,   -1, -1, -1, -1, -1, 34, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_5_C2_infos[35] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xFD'), output1('\xAD'),
};
static const BYTE_LOOKUP
to_ISO_8859_5_C2 = {
    to_ISO_8859_5_C2_offsets,
    to_ISO_8859_5_C2_infos
};

static const unsigned char
to_ISO_8859_5_D0_offsets[64] = {
     -1,  0,  1,  2,  3,  4,  5,  6,    7,  8,  9, 10, 11, -1, 12, 13,
     14, 15, 16, 17, 18, 19, 20, 21,   22, 23, 24, 25, 26, 27, 28, 29,
     30, 31, 32, 33, 34, 35, 36, 37,   38, 39, 40, 41, 42, 43, 44, 45,
     46, 47, 48, 49, 50, 51, 52, 53,   54, 55, 56, 57, 58, 59, 60, 61,
};
static const void* const
to_ISO_8859_5_D0_infos[62] = {
     output1('\xA1'), output1('\xA2'), output1('\xA3'), output1('\xA4'),
     output1('\xA5'), output1('\xA6'), output1('\xA7'), output1('\xA8'),
     output1('\xA9'), output1('\xAA'), output1('\xAB'), output1('\xAC'),
     output1('\xAE'), output1('\xAF'), output1('\xB0'), output1('\xB1'),
     output1('\xB2'), output1('\xB3'), output1('\xB4'), output1('\xB5'),
     output1('\xB6'), output1('\xB7'), output1('\xB8'), output1('\xB9'),
     output1('\xBA'), output1('\xBB'), output1('\xBC'), output1('\xBD'),
     output1('\xBE'), output1('\xBF'), output1('\xC0'), output1('\xC1'),
     output1('\xC2'), output1('\xC3'), output1('\xC4'), output1('\xC5'),
     output1('\xC6'), output1('\xC7'), output1('\xC8'), output1('\xC9'),
     output1('\xCA'), output1('\xCB'), output1('\xCC'), output1('\xCD'),
     output1('\xCE'), output1('\xCF'), output1('\xD0'), output1('\xD1'),
     output1('\xD2'), output1('\xD3'), output1('\xD4'), output1('\xD5'),
     output1('\xD6'), output1('\xD7'), output1('\xD8'), output1('\xD9'),
     output1('\xDA'), output1('\xDB'), output1('\xDC'), output1('\xDD'),
     output1('\xDE'), output1('\xDF'),
};
static const BYTE_LOOKUP
to_ISO_8859_5_D0 = {
    to_ISO_8859_5_D0_offsets,
    to_ISO_8859_5_D0_infos
};

static const unsigned char
to_ISO_8859_5_D1_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     -1, 16, 17, 18, 19, 20, 21, 22,   23, 24, 25, 26, 27, -1, 28, 29,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_5_D1_infos[30] = {
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF1'), output1('\xF2'), output1('\xF3'), output1('\xF4'),
     output1('\xF5'), output1('\xF6'), output1('\xF7'), output1('\xF8'),
     output1('\xF9'), output1('\xFA'), output1('\xFB'), output1('\xFC'),
     output1('\xFE'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_5_D1 = {
    to_ISO_8859_5_D1_offsets,
    to_ISO_8859_5_D1_infos
};

static const unsigned char
to_ISO_8859_5_E2_84_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1,  0, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_5_E2_84_infos[1] = {
     output1('\xF0'),
};
static const BYTE_LOOKUP
to_ISO_8859_5_E2_84 = {
    to_ISO_8859_5_E2_84_offsets,
    to_ISO_8859_5_E2_84_infos
};

static const unsigned char
to_ISO_8859_5_E2_offsets[64] = {
     -1, -1, -1, -1,  0, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_5_E2_infos[1] = {
     &to_ISO_8859_5_E2_84,
};
static const BYTE_LOOKUP
to_ISO_8859_5_E2 = {
    to_ISO_8859_5_E2_offsets,
    to_ISO_8859_5_E2_infos
};

static const unsigned char
to_ISO_8859_5_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      2,  3, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  4, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_5_infos[5] = {
                 NOMAP, &to_ISO_8859_5_C2, &to_ISO_8859_5_D0, &to_ISO_8859_5_D1,
     &to_ISO_8859_5_E2,
};
const BYTE_LOOKUP
to_ISO_8859_5 = {
    to_ISO_8859_5_offsets,
    to_ISO_8859_5_infos
};

static const unsigned char
from_ISO_8859_6_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, -1, -1, -1, 34, -1, -1, -1,   -1, -1, -1, -1, 35, 36, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, 37, -1, -1, -1, 38,
     -1, 39, 40, 41, 42, 43, 44, 45,   46, 47, 48, 49, 50, 51, 52, 53,
     54, 55, 56, 57, 58, 59, 60, 61,   62, 63, 64, -1, -1, -1, -1, -1,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
from_ISO_8859_6_infos[84] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC2','\xA4'), output2('\xD8','\x8C'),
     output2('\xC2','\xAD'), output2('\xD8','\x9B'),
     output2('\xD8','\x9F'), output2('\xD8','\xA1'),
     output2('\xD8','\xA2'), output2('\xD8','\xA3'),
     output2('\xD8','\xA4'), output2('\xD8','\xA5'),
     output2('\xD8','\xA6'), output2('\xD8','\xA7'),
     output2('\xD8','\xA8'), output2('\xD8','\xA9'),
     output2('\xD8','\xAA'), output2('\xD8','\xAB'),
     output2('\xD8','\xAC'), output2('\xD8','\xAD'),
     output2('\xD8','\xAE'), output2('\xD8','\xAF'),
     output2('\xD8','\xB0'), output2('\xD8','\xB1'),
     output2('\xD8','\xB2'), output2('\xD8','\xB3'),
     output2('\xD8','\xB4'), output2('\xD8','\xB5'),
     output2('\xD8','\xB6'), output2('\xD8','\xB7'),
     output2('\xD8','\xB8'), output2('\xD8','\xB9'),
     output2('\xD8','\xBA'), output2('\xD9','\x80'),
     output2('\xD9','\x81'), output2('\xD9','\x82'),
     output2('\xD9','\x83'), output2('\xD9','\x84'),
     output2('\xD9','\x85'), output2('\xD9','\x86'),
     output2('\xD9','\x87'), output2('\xD9','\x88'),
     output2('\xD9','\x89'), output2('\xD9','\x8A'),
     output2('\xD9','\x8B'), output2('\xD9','\x8C'),
     output2('\xD9','\x8D'), output2('\xD9','\x8E'),
     output2('\xD9','\x8F'), output2('\xD9','\x90'),
     output2('\xD9','\x91'), output2('\xD9','\x92'),
};
const BYTE_LOOKUP
from_ISO_8859_6 = {
    from_ISO_8859_6_offsets,
    from_ISO_8859_6_infos
};

static const unsigned char
to_ISO_8859_6_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, 33, -1, -1, -1,   -1, -1, -1, -1, -1, 34, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_6_C2_infos[35] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA4'), output1('\xAD'),
};
static const BYTE_LOOKUP
to_ISO_8859_6_C2 = {
    to_ISO_8859_6_C2_offsets,
    to_ISO_8859_6_C2_infos
};

static const unsigned char
to_ISO_8859_6_D8_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  0, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1,  1, -1, -1, -1,  2,
     -1,  3,  4,  5,  6,  7,  8,  9,   10, 11, 12, 13, 14, 15, 16, 17,
     18, 19, 20, 21, 22, 23, 24, 25,   26, 27, 28, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_6_D8_infos[29] = {
     output1('\xAC'), output1('\xBB'), output1('\xBF'), output1('\xC1'),
     output1('\xC2'), output1('\xC3'), output1('\xC4'), output1('\xC5'),
     output1('\xC6'), output1('\xC7'), output1('\xC8'), output1('\xC9'),
     output1('\xCA'), output1('\xCB'), output1('\xCC'), output1('\xCD'),
     output1('\xCE'), output1('\xCF'), output1('\xD0'), output1('\xD1'),
     output1('\xD2'), output1('\xD3'), output1('\xD4'), output1('\xD5'),
     output1('\xD6'), output1('\xD7'), output1('\xD8'), output1('\xD9'),
     output1('\xDA'),
};
static const BYTE_LOOKUP
to_ISO_8859_6_D8 = {
    to_ISO_8859_6_D8_offsets,
    to_ISO_8859_6_D8_infos
};

static const unsigned char
to_ISO_8859_6_D9_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_6_D9_infos[19] = {
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF0'), output1('\xF1'), output1('\xF2'),
};
static const BYTE_LOOKUP
to_ISO_8859_6_D9 = {
    to_ISO_8859_6_D9_offsets,
    to_ISO_8859_6_D9_infos
};

static const unsigned char
to_ISO_8859_6_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    2,  3, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_6_infos[4] = {
                 NOMAP, &to_ISO_8859_6_C2, &to_ISO_8859_6_D8, &to_ISO_8859_6_D9,
};
const BYTE_LOOKUP
to_ISO_8859_6 = {
    to_ISO_8859_6_offsets,
    to_ISO_8859_6_infos
};

static const unsigned char
from_ISO_8859_7_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, -1, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, 63,
     64, 65, 66, 67, 68, 69, 70, 71,   72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, -1, 82, 83, 84, 85, 86,   87, 88, 89, 90, 91, 92, 93, 94,
     95, 96, 97, 98, 99,100,101,102,  103,104,105,106,107,108,109,110,
    111,112,113,114,115,116,117,118,  119,120,121,122,123,124,125, -1,
};
static const void* const
from_ISO_8859_7_infos[126] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
     output3('\xE2','\x80','\x98'), output3('\xE2','\x80','\x99'),
            output2('\xC2','\xA3'), output3('\xE2','\x82','\xAC'),
     output3('\xE2','\x82','\xAF'),        output2('\xC2','\xA6'),
            output2('\xC2','\xA7'),        output2('\xC2','\xA8'),
            output2('\xC2','\xA9'),        output2('\xCD','\xBA'),
            output2('\xC2','\xAB'),        output2('\xC2','\xAC'),
            output2('\xC2','\xAD'), output3('\xE2','\x80','\x95'),
            output2('\xC2','\xB0'),        output2('\xC2','\xB1'),
            output2('\xC2','\xB2'),        output2('\xC2','\xB3'),
            output2('\xCE','\x84'),        output2('\xCE','\x85'),
            output2('\xCE','\x86'),        output2('\xC2','\xB7'),
            output2('\xCE','\x88'),        output2('\xCE','\x89'),
            output2('\xCE','\x8A'),        output2('\xC2','\xBB'),
            output2('\xCE','\x8C'),        output2('\xC2','\xBD'),
            output2('\xCE','\x8E'),        output2('\xCE','\x8F'),
            output2('\xCE','\x90'),        output2('\xCE','\x91'),
            output2('\xCE','\x92'),        output2('\xCE','\x93'),
            output2('\xCE','\x94'),        output2('\xCE','\x95'),
            output2('\xCE','\x96'),        output2('\xCE','\x97'),
            output2('\xCE','\x98'),        output2('\xCE','\x99'),
            output2('\xCE','\x9A'),        output2('\xCE','\x9B'),
            output2('\xCE','\x9C'),        output2('\xCE','\x9D'),
            output2('\xCE','\x9E'),        output2('\xCE','\x9F'),
            output2('\xCE','\xA0'),        output2('\xCE','\xA1'),
            output2('\xCE','\xA3'),        output2('\xCE','\xA4'),
            output2('\xCE','\xA5'),        output2('\xCE','\xA6'),
            output2('\xCE','\xA7'),        output2('\xCE','\xA8'),
            output2('\xCE','\xA9'),        output2('\xCE','\xAA'),
            output2('\xCE','\xAB'),        output2('\xCE','\xAC'),
            output2('\xCE','\xAD'),        output2('\xCE','\xAE'),
            output2('\xCE','\xAF'),        output2('\xCE','\xB0'),
            output2('\xCE','\xB1'),        output2('\xCE','\xB2'),
            output2('\xCE','\xB3'),        output2('\xCE','\xB4'),
            output2('\xCE','\xB5'),        output2('\xCE','\xB6'),
            output2('\xCE','\xB7'),        output2('\xCE','\xB8'),
            output2('\xCE','\xB9'),        output2('\xCE','\xBA'),
            output2('\xCE','\xBB'),        output2('\xCE','\xBC'),
            output2('\xCE','\xBD'),        output2('\xCE','\xBE'),
            output2('\xCE','\xBF'),        output2('\xCF','\x80'),
            output2('\xCF','\x81'),        output2('\xCF','\x82'),
            output2('\xCF','\x83'),        output2('\xCF','\x84'),
            output2('\xCF','\x85'),        output2('\xCF','\x86'),
            output2('\xCF','\x87'),        output2('\xCF','\x88'),
            output2('\xCF','\x89'),        output2('\xCF','\x8A'),
            output2('\xCF','\x8B'),        output2('\xCF','\x8C'),
            output2('\xCF','\x8D'),        output2('\xCF','\x8E'),
};
const BYTE_LOOKUP
from_ISO_8859_7 = {
    from_ISO_8859_7_offsets,
    from_ISO_8859_7_infos
};

static const unsigned char
to_ISO_8859_7_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, 33, -1, -1, 34, 35,   36, 37, -1, 38, 39, 40, -1, -1,
     41, 42, 43, 44, -1, -1, -1, 45,   -1, -1, -1, 46, -1, 47, -1, -1,
};
static const void* const
to_ISO_8859_7_C2_infos[48] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA3'), output1('\xA6'), output1('\xA7'),
     output1('\xA8'), output1('\xA9'), output1('\xAB'), output1('\xAC'),
     output1('\xAD'), output1('\xB0'), output1('\xB1'), output1('\xB2'),
     output1('\xB3'), output1('\xB7'), output1('\xBB'), output1('\xBD'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_C2 = {
    to_ISO_8859_7_C2_offsets,
    to_ISO_8859_7_C2_infos
};

static const unsigned char
to_ISO_8859_7_CD_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1,  0, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_CD_infos[1] = {
     output1('\xAA'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_CD = {
    to_ISO_8859_7_CD_offsets,
    to_ISO_8859_7_CD_infos
};

static const unsigned char
to_ISO_8859_7_CE_offsets[64] = {
     -1, -1, -1, -1,  0,  1,  2, -1,    3,  4,  5, -1,  6, -1,  7,  8,
      9, 10, 11, 12, 13, 14, 15, 16,   17, 18, 19, 20, 21, 22, 23, 24,
     25, 26, -1, 27, 28, 29, 30, 31,   32, 33, 34, 35, 36, 37, 38, 39,
     40, 41, 42, 43, 44, 45, 46, 47,   48, 49, 50, 51, 52, 53, 54, 55,
};
static const void* const
to_ISO_8859_7_CE_infos[56] = {
     output1('\xB4'), output1('\xB5'), output1('\xB6'), output1('\xB8'),
     output1('\xB9'), output1('\xBA'), output1('\xBC'), output1('\xBE'),
     output1('\xBF'), output1('\xC0'), output1('\xC1'), output1('\xC2'),
     output1('\xC3'), output1('\xC4'), output1('\xC5'), output1('\xC6'),
     output1('\xC7'), output1('\xC8'), output1('\xC9'), output1('\xCA'),
     output1('\xCB'), output1('\xCC'), output1('\xCD'), output1('\xCE'),
     output1('\xCF'), output1('\xD0'), output1('\xD1'), output1('\xD3'),
     output1('\xD4'), output1('\xD5'), output1('\xD6'), output1('\xD7'),
     output1('\xD8'), output1('\xD9'), output1('\xDA'), output1('\xDB'),
     output1('\xDC'), output1('\xDD'), output1('\xDE'), output1('\xDF'),
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_CE = {
    to_ISO_8859_7_CE_offsets,
    to_ISO_8859_7_CE_infos
};

static const unsigned char
to_ISO_8859_7_CF_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_CF_infos[15] = {
     output1('\xF0'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'), output1('\xFB'),
     output1('\xFC'), output1('\xFD'), output1('\xFE'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_CF = {
    to_ISO_8859_7_CF_offsets,
    to_ISO_8859_7_CF_infos
};

static const unsigned char
to_ISO_8859_7_E2_80_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1,  0, -1, -1,    1,  2, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_E2_80_infos[3] = {
     output1('\xAF'), output1('\xA1'), output1('\xA2'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_E2_80 = {
    to_ISO_8859_7_E2_80_offsets,
    to_ISO_8859_7_E2_80_infos
};

static const unsigned char
to_ISO_8859_7_E2_82_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  0, -1, -1,  1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_E2_82_infos[2] = {
     output1('\xA4'), output1('\xA5'),
};
static const BYTE_LOOKUP
to_ISO_8859_7_E2_82 = {
    to_ISO_8859_7_E2_82_offsets,
    to_ISO_8859_7_E2_82_infos
};

static const unsigned char
to_ISO_8859_7_E2_offsets[64] = {
      0, -1,  1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_E2_infos[2] = {
     &to_ISO_8859_7_E2_80, &to_ISO_8859_7_E2_82,
};
static const BYTE_LOOKUP
to_ISO_8859_7_E2 = {
    to_ISO_8859_7_E2_offsets,
    to_ISO_8859_7_E2_infos
};

static const unsigned char
to_ISO_8859_7_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1,  2,  3,  4,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  5, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_7_infos[6] = {
                 NOMAP, &to_ISO_8859_7_C2, &to_ISO_8859_7_CD, &to_ISO_8859_7_CE,
     &to_ISO_8859_7_CF, &to_ISO_8859_7_E2,
};
const BYTE_LOOKUP
to_ISO_8859_7 = {
    to_ISO_8859_7_offsets,
    to_ISO_8859_7_infos
};

static const unsigned char
from_ISO_8859_8_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, -1, 34, 35, 36, 37, 38, 39,   40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, 63,
     64, 65, 66, 67, 68, 69, 70, 71,   72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87,   88, 89, 90, -1, -1, 91, 92, -1,
};
static const void* const
from_ISO_8859_8_infos[93] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
            output2('\xC2','\xA2'),        output2('\xC2','\xA3'),
            output2('\xC2','\xA4'),        output2('\xC2','\xA5'),
            output2('\xC2','\xA6'),        output2('\xC2','\xA7'),
            output2('\xC2','\xA8'),        output2('\xC2','\xA9'),
            output2('\xC3','\x97'),        output2('\xC2','\xAB'),
            output2('\xC2','\xAC'),        output2('\xC2','\xAD'),
            output2('\xC2','\xAE'),        output2('\xC2','\xAF'),
            output2('\xC2','\xB0'),        output2('\xC2','\xB1'),
            output2('\xC2','\xB2'),        output2('\xC2','\xB3'),
            output2('\xC2','\xB4'),        output2('\xC2','\xB5'),
            output2('\xC2','\xB6'),        output2('\xC2','\xB7'),
            output2('\xC2','\xB8'),        output2('\xC2','\xB9'),
            output2('\xC3','\xB7'),        output2('\xC2','\xBB'),
            output2('\xC2','\xBC'),        output2('\xC2','\xBD'),
            output2('\xC2','\xBE'), output3('\xE2','\x80','\x97'),
            output2('\xD7','\x90'),        output2('\xD7','\x91'),
            output2('\xD7','\x92'),        output2('\xD7','\x93'),
            output2('\xD7','\x94'),        output2('\xD7','\x95'),
            output2('\xD7','\x96'),        output2('\xD7','\x97'),
            output2('\xD7','\x98'),        output2('\xD7','\x99'),
            output2('\xD7','\x9A'),        output2('\xD7','\x9B'),
            output2('\xD7','\x9C'),        output2('\xD7','\x9D'),
            output2('\xD7','\x9E'),        output2('\xD7','\x9F'),
            output2('\xD7','\xA0'),        output2('\xD7','\xA1'),
            output2('\xD7','\xA2'),        output2('\xD7','\xA3'),
            output2('\xD7','\xA4'),        output2('\xD7','\xA5'),
            output2('\xD7','\xA6'),        output2('\xD7','\xA7'),
            output2('\xD7','\xA8'),        output2('\xD7','\xA9'),
            output2('\xD7','\xAA'), output3('\xE2','\x80','\x8E'),
     output3('\xE2','\x80','\x8F'),
};
const BYTE_LOOKUP
from_ISO_8859_8 = {
    from_ISO_8859_8_offsets,
    from_ISO_8859_8_infos
};

static const unsigned char
to_ISO_8859_8_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, 33, 34, 35, 36, 37, 38,   39, 40, -1, 41, 42, 43, 44, 45,
     46, 47, 48, 49, 50, 51, 52, 53,   54, 55, -1, 56, 57, 58, 59, -1,
};
static const void* const
to_ISO_8859_8_C2_infos[60] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA2'), output1('\xA3'), output1('\xA4'),
     output1('\xA5'), output1('\xA6'), output1('\xA7'), output1('\xA8'),
     output1('\xA9'), output1('\xAB'), output1('\xAC'), output1('\xAD'),
     output1('\xAE'), output1('\xAF'), output1('\xB0'), output1('\xB1'),
     output1('\xB2'), output1('\xB3'), output1('\xB4'), output1('\xB5'),
     output1('\xB6'), output1('\xB7'), output1('\xB8'), output1('\xB9'),
     output1('\xBB'), output1('\xBC'), output1('\xBD'), output1('\xBE'),
};
static const BYTE_LOOKUP
to_ISO_8859_8_C2 = {
    to_ISO_8859_8_C2_offsets,
    to_ISO_8859_8_C2_infos
};

static const unsigned char
to_ISO_8859_8_C3_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1,  0,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1,  1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_8_C3_infos[2] = {
     output1('\xAA'), output1('\xBA'),
};
static const BYTE_LOOKUP
to_ISO_8859_8_C3 = {
    to_ISO_8859_8_C3_offsets,
    to_ISO_8859_8_C3_infos
};

static const unsigned char
to_ISO_8859_8_D7_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_8_D7_infos[27] = {
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF0'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'),
};
static const BYTE_LOOKUP
to_ISO_8859_8_D7 = {
    to_ISO_8859_8_D7_offsets,
    to_ISO_8859_8_D7_infos
};

static const unsigned char
to_ISO_8859_8_E2_80_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1,  0,  1,
     -1, -1, -1, -1, -1, -1, -1,  2,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_8_E2_80_infos[3] = {
     output1('\xFD'), output1('\xFE'), output1('\xDF'),
};
static const BYTE_LOOKUP
to_ISO_8859_8_E2_80 = {
    to_ISO_8859_8_E2_80_offsets,
    to_ISO_8859_8_E2_80_infos
};

static const unsigned char
to_ISO_8859_8_E2_offsets[64] = {
      0, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_8_E2_infos[1] = {
     &to_ISO_8859_8_E2_80,
};
static const BYTE_LOOKUP
to_ISO_8859_8_E2 = {
    to_ISO_8859_8_E2_offsets,
    to_ISO_8859_8_E2_infos
};

static const unsigned char
to_ISO_8859_8_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1,  3,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  4, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_8_infos[5] = {
                 NOMAP, &to_ISO_8859_8_C2, &to_ISO_8859_8_C3, &to_ISO_8859_8_D7,
     &to_ISO_8859_8_E2,
};
const BYTE_LOOKUP
to_ISO_8859_8 = {
    to_ISO_8859_8_offsets,
    to_ISO_8859_8_infos
};

static const unsigned char
from_ISO_8859_9_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_9_infos[129] = {
                      NOMAP, output2('\xC2','\x80'),
     output2('\xC2','\x81'), output2('\xC2','\x82'),
     output2('\xC2','\x83'), output2('\xC2','\x84'),
     output2('\xC2','\x85'), output2('\xC2','\x86'),
     output2('\xC2','\x87'), output2('\xC2','\x88'),
     output2('\xC2','\x89'), output2('\xC2','\x8A'),
     output2('\xC2','\x8B'), output2('\xC2','\x8C'),
     output2('\xC2','\x8D'), output2('\xC2','\x8E'),
     output2('\xC2','\x8F'), output2('\xC2','\x90'),
     output2('\xC2','\x91'), output2('\xC2','\x92'),
     output2('\xC2','\x93'), output2('\xC2','\x94'),
     output2('\xC2','\x95'), output2('\xC2','\x96'),
     output2('\xC2','\x97'), output2('\xC2','\x98'),
     output2('\xC2','\x99'), output2('\xC2','\x9A'),
     output2('\xC2','\x9B'), output2('\xC2','\x9C'),
     output2('\xC2','\x9D'), output2('\xC2','\x9E'),
     output2('\xC2','\x9F'), output2('\xC2','\xA0'),
     output2('\xC2','\xA1'), output2('\xC2','\xA2'),
     output2('\xC2','\xA3'), output2('\xC2','\xA4'),
     output2('\xC2','\xA5'), output2('\xC2','\xA6'),
     output2('\xC2','\xA7'), output2('\xC2','\xA8'),
     output2('\xC2','\xA9'), output2('\xC2','\xAA'),
     output2('\xC2','\xAB'), output2('\xC2','\xAC'),
     output2('\xC2','\xAD'), output2('\xC2','\xAE'),
     output2('\xC2','\xAF'), output2('\xC2','\xB0'),
     output2('\xC2','\xB1'), output2('\xC2','\xB2'),
     output2('\xC2','\xB3'), output2('\xC2','\xB4'),
     output2('\xC2','\xB5'), output2('\xC2','\xB6'),
     output2('\xC2','\xB7'), output2('\xC2','\xB8'),
     output2('\xC2','\xB9'), output2('\xC2','\xBA'),
     output2('\xC2','\xBB'), output2('\xC2','\xBC'),
     output2('\xC2','\xBD'), output2('\xC2','\xBE'),
     output2('\xC2','\xBF'), output2('\xC3','\x80'),
     output2('\xC3','\x81'), output2('\xC3','\x82'),
     output2('\xC3','\x83'), output2('\xC3','\x84'),
     output2('\xC3','\x85'), output2('\xC3','\x86'),
     output2('\xC3','\x87'), output2('\xC3','\x88'),
     output2('\xC3','\x89'), output2('\xC3','\x8A'),
     output2('\xC3','\x8B'), output2('\xC3','\x8C'),
     output2('\xC3','\x8D'), output2('\xC3','\x8E'),
     output2('\xC3','\x8F'), output2('\xC4','\x9E'),
     output2('\xC3','\x91'), output2('\xC3','\x92'),
     output2('\xC3','\x93'), output2('\xC3','\x94'),
     output2('\xC3','\x95'), output2('\xC3','\x96'),
     output2('\xC3','\x97'), output2('\xC3','\x98'),
     output2('\xC3','\x99'), output2('\xC3','\x9A'),
     output2('\xC3','\x9B'), output2('\xC3','\x9C'),
     output2('\xC4','\xB0'), output2('\xC5','\x9E'),
     output2('\xC3','\x9F'), output2('\xC3','\xA0'),
     output2('\xC3','\xA1'), output2('\xC3','\xA2'),
     output2('\xC3','\xA3'), output2('\xC3','\xA4'),
     output2('\xC3','\xA5'), output2('\xC3','\xA6'),
     output2('\xC3','\xA7'), output2('\xC3','\xA8'),
     output2('\xC3','\xA9'), output2('\xC3','\xAA'),
     output2('\xC3','\xAB'), output2('\xC3','\xAC'),
     output2('\xC3','\xAD'), output2('\xC3','\xAE'),
     output2('\xC3','\xAF'), output2('\xC4','\x9F'),
     output2('\xC3','\xB1'), output2('\xC3','\xB2'),
     output2('\xC3','\xB3'), output2('\xC3','\xB4'),
     output2('\xC3','\xB5'), output2('\xC3','\xB6'),
     output2('\xC3','\xB7'), output2('\xC3','\xB8'),
     output2('\xC3','\xB9'), output2('\xC3','\xBA'),
     output2('\xC3','\xBB'), output2('\xC3','\xBC'),
     output2('\xC4','\xB1'), output2('\xC5','\x9F'),
     output2('\xC3','\xBF'),
};
const BYTE_LOOKUP
from_ISO_8859_9 = {
    from_ISO_8859_9_offsets,
    from_ISO_8859_9_infos
};

static const unsigned char
to_ISO_8859_9_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39,   40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, 63,
};
static const void* const
to_ISO_8859_9_C2_infos[64] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA1'), output1('\xA2'), output1('\xA3'),
     output1('\xA4'), output1('\xA5'), output1('\xA6'), output1('\xA7'),
     output1('\xA8'), output1('\xA9'), output1('\xAA'), output1('\xAB'),
     output1('\xAC'), output1('\xAD'), output1('\xAE'), output1('\xAF'),
     output1('\xB0'), output1('\xB1'), output1('\xB2'), output1('\xB3'),
     output1('\xB4'), output1('\xB5'), output1('\xB6'), output1('\xB7'),
     output1('\xB8'), output1('\xB9'), output1('\xBA'), output1('\xBB'),
     output1('\xBC'), output1('\xBD'), output1('\xBE'), output1('\xBF'),
};
static const BYTE_LOOKUP
to_ISO_8859_9_C2 = {
    to_ISO_8859_9_C2_offsets,
    to_ISO_8859_9_C2_infos
};

static const unsigned char
to_ISO_8859_9_C3_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     -1, 16, 17, 18, 19, 20, 21, 22,   23, 24, 25, 26, 27, -1, -1, 28,
     29, 30, 31, 32, 33, 34, 35, 36,   37, 38, 39, 40, 41, 42, 43, 44,
     -1, 45, 46, 47, 48, 49, 50, 51,   52, 53, 54, 55, 56, -1, -1, 57,
};
static const void* const
to_ISO_8859_9_C3_infos[58] = {
     output1('\xC0'), output1('\xC1'), output1('\xC2'), output1('\xC3'),
     output1('\xC4'), output1('\xC5'), output1('\xC6'), output1('\xC7'),
     output1('\xC8'), output1('\xC9'), output1('\xCA'), output1('\xCB'),
     output1('\xCC'), output1('\xCD'), output1('\xCE'), output1('\xCF'),
     output1('\xD1'), output1('\xD2'), output1('\xD3'), output1('\xD4'),
     output1('\xD5'), output1('\xD6'), output1('\xD7'), output1('\xD8'),
     output1('\xD9'), output1('\xDA'), output1('\xDB'), output1('\xDC'),
     output1('\xDF'), output1('\xE0'), output1('\xE1'), output1('\xE2'),
     output1('\xE3'), output1('\xE4'), output1('\xE5'), output1('\xE6'),
     output1('\xE7'), output1('\xE8'), output1('\xE9'), output1('\xEA'),
     output1('\xEB'), output1('\xEC'), output1('\xED'), output1('\xEE'),
     output1('\xEF'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'), output1('\xFB'),
     output1('\xFC'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_9_C3 = {
    to_ISO_8859_9_C3_offsets,
    to_ISO_8859_9_C3_infos
};

static const unsigned char
to_ISO_8859_9_C4_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1,  0,  1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      2,  3, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_9_C4_infos[4] = {
     output1('\xD0'), output1('\xF0'), output1('\xDD'), output1('\xFD'),
};
static const BYTE_LOOKUP
to_ISO_8859_9_C4 = {
    to_ISO_8859_9_C4_offsets,
    to_ISO_8859_9_C4_infos
};

static const unsigned char
to_ISO_8859_9_C5_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1,  0,  1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_9_C5_infos[2] = {
     output1('\xDE'), output1('\xFE'),
};
static const BYTE_LOOKUP
to_ISO_8859_9_C5 = {
    to_ISO_8859_9_C5_offsets,
    to_ISO_8859_9_C5_infos
};

static const unsigned char
to_ISO_8859_9_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_9_infos[5] = {
                 NOMAP, &to_ISO_8859_9_C2, &to_ISO_8859_9_C3, &to_ISO_8859_9_C4,
     &to_ISO_8859_9_C5,
};
const BYTE_LOOKUP
to_ISO_8859_9 = {
    to_ISO_8859_9_offsets,
    to_ISO_8859_9_infos
};

static const unsigned char
from_ISO_8859_10_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_10_infos[129] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
            output2('\xC4','\x84'),        output2('\xC4','\x92'),
            output2('\xC4','\xA2'),        output2('\xC4','\xAA'),
            output2('\xC4','\xA8'),        output2('\xC4','\xB6'),
            output2('\xC2','\xA7'),        output2('\xC4','\xBB'),
            output2('\xC4','\x90'),        output2('\xC5','\xA0'),
            output2('\xC5','\xA6'),        output2('\xC5','\xBD'),
            output2('\xC2','\xAD'),        output2('\xC5','\xAA'),
            output2('\xC5','\x8A'),        output2('\xC2','\xB0'),
            output2('\xC4','\x85'),        output2('\xC4','\x93'),
            output2('\xC4','\xA3'),        output2('\xC4','\xAB'),
            output2('\xC4','\xA9'),        output2('\xC4','\xB7'),
            output2('\xC2','\xB7'),        output2('\xC4','\xBC'),
            output2('\xC4','\x91'),        output2('\xC5','\xA1'),
            output2('\xC5','\xA7'),        output2('\xC5','\xBE'),
     output3('\xE2','\x80','\x95'),        output2('\xC5','\xAB'),
            output2('\xC5','\x8B'),        output2('\xC4','\x80'),
            output2('\xC3','\x81'),        output2('\xC3','\x82'),
            output2('\xC3','\x83'),        output2('\xC3','\x84'),
            output2('\xC3','\x85'),        output2('\xC3','\x86'),
            output2('\xC4','\xAE'),        output2('\xC4','\x8C'),
            output2('\xC3','\x89'),        output2('\xC4','\x98'),
            output2('\xC3','\x8B'),        output2('\xC4','\x96'),
            output2('\xC3','\x8D'),        output2('\xC3','\x8E'),
            output2('\xC3','\x8F'),        output2('\xC3','\x90'),
            output2('\xC5','\x85'),        output2('\xC5','\x8C'),
            output2('\xC3','\x93'),        output2('\xC3','\x94'),
            output2('\xC3','\x95'),        output2('\xC3','\x96'),
            output2('\xC5','\xA8'),        output2('\xC3','\x98'),
            output2('\xC5','\xB2'),        output2('\xC3','\x9A'),
            output2('\xC3','\x9B'),        output2('\xC3','\x9C'),
            output2('\xC3','\x9D'),        output2('\xC3','\x9E'),
            output2('\xC3','\x9F'),        output2('\xC4','\x81'),
            output2('\xC3','\xA1'),        output2('\xC3','\xA2'),
            output2('\xC3','\xA3'),        output2('\xC3','\xA4'),
            output2('\xC3','\xA5'),        output2('\xC3','\xA6'),
            output2('\xC4','\xAF'),        output2('\xC4','\x8D'),
            output2('\xC3','\xA9'),        output2('\xC4','\x99'),
            output2('\xC3','\xAB'),        output2('\xC4','\x97'),
            output2('\xC3','\xAD'),        output2('\xC3','\xAE'),
            output2('\xC3','\xAF'),        output2('\xC3','\xB0'),
            output2('\xC5','\x86'),        output2('\xC5','\x8D'),
            output2('\xC3','\xB3'),        output2('\xC3','\xB4'),
            output2('\xC3','\xB5'),        output2('\xC3','\xB6'),
            output2('\xC5','\xA9'),        output2('\xC3','\xB8'),
            output2('\xC5','\xB3'),        output2('\xC3','\xBA'),
            output2('\xC3','\xBB'),        output2('\xC3','\xBC'),
            output2('\xC3','\xBD'),        output2('\xC3','\xBE'),
            output2('\xC4','\xB8'),
};
const BYTE_LOOKUP
from_ISO_8859_10 = {
    from_ISO_8859_10_offsets,
    from_ISO_8859_10_infos
};

static const unsigned char
to_ISO_8859_10_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, -1, -1, -1, 33,   -1, -1, -1, -1, -1, 34, -1, -1,
     35, -1, -1, -1, -1, -1, -1, 36,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_10_C2_infos[37] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA7'), output1('\xAD'), output1('\xB0'),
     output1('\xB7'),
};
static const BYTE_LOOKUP
to_ISO_8859_10_C2 = {
    to_ISO_8859_10_C2_offsets,
    to_ISO_8859_10_C2_infos
};

static const unsigned char
to_ISO_8859_10_C3_offsets[64] = {
     -1,  0,  1,  2,  3,  4,  5, -1,   -1,  6, -1,  7, -1,  8,  9, 10,
     11, -1, -1, 12, 13, 14, 15, -1,   16, -1, 17, 18, 19, 20, 21, 22,
     -1, 23, 24, 25, 26, 27, 28, -1,   -1, 29, -1, 30, -1, 31, 32, 33,
     34, -1, -1, 35, 36, 37, 38, -1,   39, -1, 40, 41, 42, 43, 44, -1,
};
static const void* const
to_ISO_8859_10_C3_infos[45] = {
     output1('\xC1'), output1('\xC2'), output1('\xC3'), output1('\xC4'),
     output1('\xC5'), output1('\xC6'), output1('\xC9'), output1('\xCB'),
     output1('\xCD'), output1('\xCE'), output1('\xCF'), output1('\xD0'),
     output1('\xD3'), output1('\xD4'), output1('\xD5'), output1('\xD6'),
     output1('\xD8'), output1('\xDA'), output1('\xDB'), output1('\xDC'),
     output1('\xDD'), output1('\xDE'), output1('\xDF'), output1('\xE1'),
     output1('\xE2'), output1('\xE3'), output1('\xE4'), output1('\xE5'),
     output1('\xE6'), output1('\xE9'), output1('\xEB'), output1('\xED'),
     output1('\xEE'), output1('\xEF'), output1('\xF0'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF8'),
     output1('\xFA'), output1('\xFB'), output1('\xFC'), output1('\xFD'),
     output1('\xFE'),
};
static const BYTE_LOOKUP
to_ISO_8859_10_C3 = {
    to_ISO_8859_10_C3_offsets,
    to_ISO_8859_10_C3_infos
};

static const unsigned char
to_ISO_8859_10_C4_offsets[64] = {
      0,  1, -1, -1,  2,  3, -1, -1,   -1, -1, -1, -1,  4,  5, -1, -1,
      6,  7,  8,  9, -1, -1, 10, 11,   12, 13, -1, -1, -1, -1, -1, -1,
     -1, -1, 14, 15, -1, -1, -1, -1,   16, 17, 18, 19, -1, -1, 20, 21,
     -1, -1, -1, -1, -1, -1, 22, 23,   24, -1, -1, 25, 26, -1, -1, -1,
};
static const void* const
to_ISO_8859_10_C4_infos[27] = {
     output1('\xC0'), output1('\xE0'), output1('\xA1'), output1('\xB1'),
     output1('\xC8'), output1('\xE8'), output1('\xA9'), output1('\xB9'),
     output1('\xA2'), output1('\xB2'), output1('\xCC'), output1('\xEC'),
     output1('\xCA'), output1('\xEA'), output1('\xA3'), output1('\xB3'),
     output1('\xA5'), output1('\xB5'), output1('\xA4'), output1('\xB4'),
     output1('\xC7'), output1('\xE7'), output1('\xA6'), output1('\xB6'),
     output1('\xFF'), output1('\xA8'), output1('\xB8'),
};
static const BYTE_LOOKUP
to_ISO_8859_10_C4 = {
    to_ISO_8859_10_C4_offsets,
    to_ISO_8859_10_C4_infos
};

static const unsigned char
to_ISO_8859_10_C5_offsets[64] = {
     -1, -1, -1, -1, -1,  0,  1, -1,   -1, -1,  2,  3,  4,  5, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      6,  7, -1, -1, -1, -1,  8,  9,   10, 11, 12, 13, -1, -1, -1, -1,
     -1, -1, 14, 15, -1, -1, -1, -1,   -1, -1, -1, -1, -1, 16, 17, -1,
};
static const void* const
to_ISO_8859_10_C5_infos[18] = {
     output1('\xD1'), output1('\xF1'), output1('\xAF'), output1('\xBF'),
     output1('\xD2'), output1('\xF2'), output1('\xAA'), output1('\xBA'),
     output1('\xAB'), output1('\xBB'), output1('\xD7'), output1('\xF7'),
     output1('\xAE'), output1('\xBE'), output1('\xD9'), output1('\xF9'),
     output1('\xAC'), output1('\xBC'),
};
static const BYTE_LOOKUP
to_ISO_8859_10_C5 = {
    to_ISO_8859_10_C5_offsets,
    to_ISO_8859_10_C5_infos
};

static const unsigned char
to_ISO_8859_10_E2_80_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1,  0, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_10_E2_80_infos[1] = {
     output1('\xBD'),
};
static const BYTE_LOOKUP
to_ISO_8859_10_E2_80 = {
    to_ISO_8859_10_E2_80_offsets,
    to_ISO_8859_10_E2_80_infos
};

static const unsigned char
to_ISO_8859_10_E2_offsets[64] = {
      0, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_10_E2_infos[1] = {
     &to_ISO_8859_10_E2_80,
};
static const BYTE_LOOKUP
to_ISO_8859_10_E2 = {
    to_ISO_8859_10_E2_offsets,
    to_ISO_8859_10_E2_infos
};

static const unsigned char
to_ISO_8859_10_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  5, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_10_infos[6] = {
                  NOMAP, &to_ISO_8859_10_C2, &to_ISO_8859_10_C3, &to_ISO_8859_10_C4,
     &to_ISO_8859_10_C5, &to_ISO_8859_10_E2,
};
const BYTE_LOOKUP
to_ISO_8859_10 = {
    to_ISO_8859_10_offsets,
    to_ISO_8859_10_infos
};

static const unsigned char
from_ISO_8859_11_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, -1, -1, -1, -1, 92,
     93, 94, 95, 96, 97, 98, 99,100,  101,102,103,104,105,106,107,108,
    109,110,111,112,113,114,115,116,  117,118,119,120, -1, -1, -1, -1,
};
static const void* const
from_ISO_8859_11_infos[121] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
     output3('\xE0','\xB8','\x81'), output3('\xE0','\xB8','\x82'),
     output3('\xE0','\xB8','\x83'), output3('\xE0','\xB8','\x84'),
     output3('\xE0','\xB8','\x85'), output3('\xE0','\xB8','\x86'),
     output3('\xE0','\xB8','\x87'), output3('\xE0','\xB8','\x88'),
     output3('\xE0','\xB8','\x89'), output3('\xE0','\xB8','\x8A'),
     output3('\xE0','\xB8','\x8B'), output3('\xE0','\xB8','\x8C'),
     output3('\xE0','\xB8','\x8D'), output3('\xE0','\xB8','\x8E'),
     output3('\xE0','\xB8','\x8F'), output3('\xE0','\xB8','\x90'),
     output3('\xE0','\xB8','\x91'), output3('\xE0','\xB8','\x92'),
     output3('\xE0','\xB8','\x93'), output3('\xE0','\xB8','\x94'),
     output3('\xE0','\xB8','\x95'), output3('\xE0','\xB8','\x96'),
     output3('\xE0','\xB8','\x97'), output3('\xE0','\xB8','\x98'),
     output3('\xE0','\xB8','\x99'), output3('\xE0','\xB8','\x9A'),
     output3('\xE0','\xB8','\x9B'), output3('\xE0','\xB8','\x9C'),
     output3('\xE0','\xB8','\x9D'), output3('\xE0','\xB8','\x9E'),
     output3('\xE0','\xB8','\x9F'), output3('\xE0','\xB8','\xA0'),
     output3('\xE0','\xB8','\xA1'), output3('\xE0','\xB8','\xA2'),
     output3('\xE0','\xB8','\xA3'), output3('\xE0','\xB8','\xA4'),
     output3('\xE0','\xB8','\xA5'), output3('\xE0','\xB8','\xA6'),
     output3('\xE0','\xB8','\xA7'), output3('\xE0','\xB8','\xA8'),
     output3('\xE0','\xB8','\xA9'), output3('\xE0','\xB8','\xAA'),
     output3('\xE0','\xB8','\xAB'), output3('\xE0','\xB8','\xAC'),
     output3('\xE0','\xB8','\xAD'), output3('\xE0','\xB8','\xAE'),
     output3('\xE0','\xB8','\xAF'), output3('\xE0','\xB8','\xB0'),
     output3('\xE0','\xB8','\xB1'), output3('\xE0','\xB8','\xB2'),
     output3('\xE0','\xB8','\xB3'), output3('\xE0','\xB8','\xB4'),
     output3('\xE0','\xB8','\xB5'), output3('\xE0','\xB8','\xB6'),
     output3('\xE0','\xB8','\xB7'), output3('\xE0','\xB8','\xB8'),
     output3('\xE0','\xB8','\xB9'), output3('\xE0','\xB8','\xBA'),
     output3('\xE0','\xB8','\xBF'), output3('\xE0','\xB9','\x80'),
     output3('\xE0','\xB9','\x81'), output3('\xE0','\xB9','\x82'),
     output3('\xE0','\xB9','\x83'), output3('\xE0','\xB9','\x84'),
     output3('\xE0','\xB9','\x85'), output3('\xE0','\xB9','\x86'),
     output3('\xE0','\xB9','\x87'), output3('\xE0','\xB9','\x88'),
     output3('\xE0','\xB9','\x89'), output3('\xE0','\xB9','\x8A'),
     output3('\xE0','\xB9','\x8B'), output3('\xE0','\xB9','\x8C'),
     output3('\xE0','\xB9','\x8D'), output3('\xE0','\xB9','\x8E'),
     output3('\xE0','\xB9','\x8F'), output3('\xE0','\xB9','\x90'),
     output3('\xE0','\xB9','\x91'), output3('\xE0','\xB9','\x92'),
     output3('\xE0','\xB9','\x93'), output3('\xE0','\xB9','\x94'),
     output3('\xE0','\xB9','\x95'), output3('\xE0','\xB9','\x96'),
     output3('\xE0','\xB9','\x97'), output3('\xE0','\xB9','\x98'),
     output3('\xE0','\xB9','\x99'), output3('\xE0','\xB9','\x9A'),
     output3('\xE0','\xB9','\x9B'),
};
const BYTE_LOOKUP
from_ISO_8859_11 = {
    from_ISO_8859_11_offsets,
    from_ISO_8859_11_infos
};

static const unsigned char
to_ISO_8859_11_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_11_C2_infos[33] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'),
};
static const BYTE_LOOKUP
to_ISO_8859_11_C2 = {
    to_ISO_8859_11_C2_offsets,
    to_ISO_8859_11_C2_infos
};

static const unsigned char
to_ISO_8859_11_E0_B8_offsets[64] = {
     -1,  0,  1,  2,  3,  4,  5,  6,    7,  8,  9, 10, 11, 12, 13, 14,
     15, 16, 17, 18, 19, 20, 21, 22,   23, 24, 25, 26, 27, 28, 29, 30,
     31, 32, 33, 34, 35, 36, 37, 38,   39, 40, 41, 42, 43, 44, 45, 46,
     47, 48, 49, 50, 51, 52, 53, 54,   55, 56, 57, -1, -1, -1, -1, 58,
};
static const void* const
to_ISO_8859_11_E0_B8_infos[59] = {
     output1('\xA1'), output1('\xA2'), output1('\xA3'), output1('\xA4'),
     output1('\xA5'), output1('\xA6'), output1('\xA7'), output1('\xA8'),
     output1('\xA9'), output1('\xAA'), output1('\xAB'), output1('\xAC'),
     output1('\xAD'), output1('\xAE'), output1('\xAF'), output1('\xB0'),
     output1('\xB1'), output1('\xB2'), output1('\xB3'), output1('\xB4'),
     output1('\xB5'), output1('\xB6'), output1('\xB7'), output1('\xB8'),
     output1('\xB9'), output1('\xBA'), output1('\xBB'), output1('\xBC'),
     output1('\xBD'), output1('\xBE'), output1('\xBF'), output1('\xC0'),
     output1('\xC1'), output1('\xC2'), output1('\xC3'), output1('\xC4'),
     output1('\xC5'), output1('\xC6'), output1('\xC7'), output1('\xC8'),
     output1('\xC9'), output1('\xCA'), output1('\xCB'), output1('\xCC'),
     output1('\xCD'), output1('\xCE'), output1('\xCF'), output1('\xD0'),
     output1('\xD1'), output1('\xD2'), output1('\xD3'), output1('\xD4'),
     output1('\xD5'), output1('\xD6'), output1('\xD7'), output1('\xD8'),
     output1('\xD9'), output1('\xDA'), output1('\xDF'),
};
static const BYTE_LOOKUP
to_ISO_8859_11_E0_B8 = {
    to_ISO_8859_11_E0_B8_offsets,
    to_ISO_8859_11_E0_B8_infos
};

static const unsigned char
to_ISO_8859_11_E0_B9_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_11_E0_B9_infos[28] = {
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF0'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'), output1('\xFB'),
};
static const BYTE_LOOKUP
to_ISO_8859_11_E0_B9 = {
    to_ISO_8859_11_E0_B9_offsets,
    to_ISO_8859_11_E0_B9_infos
};

static const unsigned char
to_ISO_8859_11_E0_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    0,  1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_11_E0_infos[2] = {
     &to_ISO_8859_11_E0_B8, &to_ISO_8859_11_E0_B9,
};
static const BYTE_LOOKUP
to_ISO_8859_11_E0 = {
    to_ISO_8859_11_E0_offsets,
    to_ISO_8859_11_E0_infos
};

static const unsigned char
to_ISO_8859_11_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      2, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_11_infos[3] = {
                  NOMAP, &to_ISO_8859_11_C2, &to_ISO_8859_11_E0,
};
const BYTE_LOOKUP
to_ISO_8859_11 = {
    to_ISO_8859_11_offsets,
    to_ISO_8859_11_infos
};

static const unsigned char
from_ISO_8859_13_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_13_infos[129] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
     output3('\xE2','\x80','\x9D'),        output2('\xC2','\xA2'),
            output2('\xC2','\xA3'),        output2('\xC2','\xA4'),
     output3('\xE2','\x80','\x9E'),        output2('\xC2','\xA6'),
            output2('\xC2','\xA7'),        output2('\xC3','\x98'),
            output2('\xC2','\xA9'),        output2('\xC5','\x96'),
            output2('\xC2','\xAB'),        output2('\xC2','\xAC'),
            output2('\xC2','\xAD'),        output2('\xC2','\xAE'),
            output2('\xC3','\x86'),        output2('\xC2','\xB0'),
            output2('\xC2','\xB1'),        output2('\xC2','\xB2'),
            output2('\xC2','\xB3'), output3('\xE2','\x80','\x9C'),
            output2('\xC2','\xB5'),        output2('\xC2','\xB6'),
            output2('\xC2','\xB7'),        output2('\xC3','\xB8'),
            output2('\xC2','\xB9'),        output2('\xC5','\x97'),
            output2('\xC2','\xBB'),        output2('\xC2','\xBC'),
            output2('\xC2','\xBD'),        output2('\xC2','\xBE'),
            output2('\xC3','\xA6'),        output2('\xC4','\x84'),
            output2('\xC4','\xAE'),        output2('\xC4','\x80'),
            output2('\xC4','\x86'),        output2('\xC3','\x84'),
            output2('\xC3','\x85'),        output2('\xC4','\x98'),
            output2('\xC4','\x92'),        output2('\xC4','\x8C'),
            output2('\xC3','\x89'),        output2('\xC5','\xB9'),
            output2('\xC4','\x96'),        output2('\xC4','\xA2'),
            output2('\xC4','\xB6'),        output2('\xC4','\xAA'),
            output2('\xC4','\xBB'),        output2('\xC5','\xA0'),
            output2('\xC5','\x83'),        output2('\xC5','\x85'),
            output2('\xC3','\x93'),        output2('\xC5','\x8C'),
            output2('\xC3','\x95'),        output2('\xC3','\x96'),
            output2('\xC3','\x97'),        output2('\xC5','\xB2'),
            output2('\xC5','\x81'),        output2('\xC5','\x9A'),
            output2('\xC5','\xAA'),        output2('\xC3','\x9C'),
            output2('\xC5','\xBB'),        output2('\xC5','\xBD'),
            output2('\xC3','\x9F'),        output2('\xC4','\x85'),
            output2('\xC4','\xAF'),        output2('\xC4','\x81'),
            output2('\xC4','\x87'),        output2('\xC3','\xA4'),
            output2('\xC3','\xA5'),        output2('\xC4','\x99'),
            output2('\xC4','\x93'),        output2('\xC4','\x8D'),
            output2('\xC3','\xA9'),        output2('\xC5','\xBA'),
            output2('\xC4','\x97'),        output2('\xC4','\xA3'),
            output2('\xC4','\xB7'),        output2('\xC4','\xAB'),
            output2('\xC4','\xBC'),        output2('\xC5','\xA1'),
            output2('\xC5','\x84'),        output2('\xC5','\x86'),
            output2('\xC3','\xB3'),        output2('\xC5','\x8D'),
            output2('\xC3','\xB5'),        output2('\xC3','\xB6'),
            output2('\xC3','\xB7'),        output2('\xC5','\xB3'),
            output2('\xC5','\x82'),        output2('\xC5','\x9B'),
            output2('\xC5','\xAB'),        output2('\xC3','\xBC'),
            output2('\xC5','\xBC'),        output2('\xC5','\xBE'),
     output3('\xE2','\x80','\x99'),
};
const BYTE_LOOKUP
from_ISO_8859_13 = {
    from_ISO_8859_13_offsets,
    from_ISO_8859_13_infos
};

static const unsigned char
to_ISO_8859_13_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, 33, 34, 35, -1, 36, 37,   -1, 38, -1, 39, 40, 41, 42, -1,
     43, 44, 45, 46, -1, 47, 48, 49,   -1, 50, -1, 51, 52, 53, 54, -1,
};
static const void* const
to_ISO_8859_13_C2_infos[55] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA2'), output1('\xA3'), output1('\xA4'),
     output1('\xA6'), output1('\xA7'), output1('\xA9'), output1('\xAB'),
     output1('\xAC'), output1('\xAD'), output1('\xAE'), output1('\xB0'),
     output1('\xB1'), output1('\xB2'), output1('\xB3'), output1('\xB5'),
     output1('\xB6'), output1('\xB7'), output1('\xB9'), output1('\xBB'),
     output1('\xBC'), output1('\xBD'), output1('\xBE'),
};
static const BYTE_LOOKUP
to_ISO_8859_13_C2 = {
    to_ISO_8859_13_C2_offsets,
    to_ISO_8859_13_C2_infos
};

static const unsigned char
to_ISO_8859_13_C3_offsets[64] = {
     -1, -1, -1, -1,  0,  1,  2, -1,   -1,  3, -1, -1, -1, -1, -1, -1,
     -1, -1, -1,  4, -1,  5,  6,  7,    8, -1, -1, -1,  9, -1, -1, 10,
     -1, -1, -1, -1, 11, 12, 13, -1,   -1, 14, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, 15, -1, 16, 17, 18,   19, -1, -1, -1, 20, -1, -1, -1,
};
static const void* const
to_ISO_8859_13_C3_infos[21] = {
     output1('\xC4'), output1('\xC5'), output1('\xAF'), output1('\xC9'),
     output1('\xD3'), output1('\xD5'), output1('\xD6'), output1('\xD7'),
     output1('\xA8'), output1('\xDC'), output1('\xDF'), output1('\xE4'),
     output1('\xE5'), output1('\xBF'), output1('\xE9'), output1('\xF3'),
     output1('\xF5'), output1('\xF6'), output1('\xF7'), output1('\xB8'),
     output1('\xFC'),
};
static const BYTE_LOOKUP
to_ISO_8859_13_C3 = {
    to_ISO_8859_13_C3_offsets,
    to_ISO_8859_13_C3_infos
};

static const unsigned char
to_ISO_8859_13_C4_offsets[64] = {
      0,  1, -1, -1,  2,  3,  4,  5,   -1, -1, -1, -1,  6,  7, -1, -1,
     -1, -1,  8,  9, -1, -1, 10, 11,   12, 13, -1, -1, -1, -1, -1, -1,
     -1, -1, 14, 15, -1, -1, -1, -1,   -1, -1, 16, 17, -1, -1, 18, 19,
     -1, -1, -1, -1, -1, -1, 20, 21,   -1, -1, -1, 22, 23, -1, -1, -1,
};
static const void* const
to_ISO_8859_13_C4_infos[24] = {
     output1('\xC2'), output1('\xE2'), output1('\xC0'), output1('\xE0'),
     output1('\xC3'), output1('\xE3'), output1('\xC8'), output1('\xE8'),
     output1('\xC7'), output1('\xE7'), output1('\xCB'), output1('\xEB'),
     output1('\xC6'), output1('\xE6'), output1('\xCC'), output1('\xEC'),
     output1('\xCE'), output1('\xEE'), output1('\xC1'), output1('\xE1'),
     output1('\xCD'), output1('\xED'), output1('\xCF'), output1('\xEF'),
};
static const BYTE_LOOKUP
to_ISO_8859_13_C4 = {
    to_ISO_8859_13_C4_offsets,
    to_ISO_8859_13_C4_infos
};

static const unsigned char
to_ISO_8859_13_C5_offsets[64] = {
     -1,  0,  1,  2,  3,  4,  5, -1,   -1, -1, -1, -1,  6,  7, -1, -1,
     -1, -1, -1, -1, -1, -1,  8,  9,   -1, -1, 10, 11, -1, -1, -1, -1,
     12, 13, -1, -1, -1, -1, -1, -1,   -1, -1, 14, 15, -1, -1, -1, -1,
     -1, -1, 16, 17, -1, -1, -1, -1,   -1, 18, 19, 20, 21, 22, 23, -1,
};
static const void* const
to_ISO_8859_13_C5_infos[24] = {
     output1('\xD9'), output1('\xF9'), output1('\xD1'), output1('\xF1'),
     output1('\xD2'), output1('\xF2'), output1('\xD4'), output1('\xF4'),
     output1('\xAA'), output1('\xBA'), output1('\xDA'), output1('\xFA'),
     output1('\xD0'), output1('\xF0'), output1('\xDB'), output1('\xFB'),
     output1('\xD8'), output1('\xF8'), output1('\xCA'), output1('\xEA'),
     output1('\xDD'), output1('\xFD'), output1('\xDE'), output1('\xFE'),
};
static const BYTE_LOOKUP
to_ISO_8859_13_C5 = {
    to_ISO_8859_13_C5_offsets,
    to_ISO_8859_13_C5_infos
};

static const unsigned char
to_ISO_8859_13_E2_80_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1,  0, -1, -1,  1,  2,  3, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_13_E2_80_infos[4] = {
     output1('\xFF'), output1('\xB4'), output1('\xA1'), output1('\xA5'),
};
static const BYTE_LOOKUP
to_ISO_8859_13_E2_80 = {
    to_ISO_8859_13_E2_80_offsets,
    to_ISO_8859_13_E2_80_infos
};

static const unsigned char
to_ISO_8859_13_E2_offsets[64] = {
      0, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_13_E2_infos[1] = {
     &to_ISO_8859_13_E2_80,
};
static const BYTE_LOOKUP
to_ISO_8859_13_E2 = {
    to_ISO_8859_13_E2_offsets,
    to_ISO_8859_13_E2_infos
};

static const unsigned char
to_ISO_8859_13_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  5, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_13_infos[6] = {
                  NOMAP, &to_ISO_8859_13_C2, &to_ISO_8859_13_C3, &to_ISO_8859_13_C4,
     &to_ISO_8859_13_C5, &to_ISO_8859_13_E2,
};
const BYTE_LOOKUP
to_ISO_8859_13 = {
    to_ISO_8859_13_offsets,
    to_ISO_8859_13_infos
};

static const unsigned char
from_ISO_8859_14_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_14_infos[129] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
     output3('\xE1','\xB8','\x82'), output3('\xE1','\xB8','\x83'),
            output2('\xC2','\xA3'),        output2('\xC4','\x8A'),
            output2('\xC4','\x8B'), output3('\xE1','\xB8','\x8A'),
            output2('\xC2','\xA7'), output3('\xE1','\xBA','\x80'),
            output2('\xC2','\xA9'), output3('\xE1','\xBA','\x82'),
     output3('\xE1','\xB8','\x8B'), output3('\xE1','\xBB','\xB2'),
            output2('\xC2','\xAD'),        output2('\xC2','\xAE'),
            output2('\xC5','\xB8'), output3('\xE1','\xB8','\x9E'),
     output3('\xE1','\xB8','\x9F'),        output2('\xC4','\xA0'),
            output2('\xC4','\xA1'), output3('\xE1','\xB9','\x80'),
     output3('\xE1','\xB9','\x81'),        output2('\xC2','\xB6'),
     output3('\xE1','\xB9','\x96'), output3('\xE1','\xBA','\x81'),
     output3('\xE1','\xB9','\x97'), output3('\xE1','\xBA','\x83'),
     output3('\xE1','\xB9','\xA0'), output3('\xE1','\xBB','\xB3'),
     output3('\xE1','\xBA','\x84'), output3('\xE1','\xBA','\x85'),
     output3('\xE1','\xB9','\xA1'),        output2('\xC3','\x80'),
            output2('\xC3','\x81'),        output2('\xC3','\x82'),
            output2('\xC3','\x83'),        output2('\xC3','\x84'),
            output2('\xC3','\x85'),        output2('\xC3','\x86'),
            output2('\xC3','\x87'),        output2('\xC3','\x88'),
            output2('\xC3','\x89'),        output2('\xC3','\x8A'),
            output2('\xC3','\x8B'),        output2('\xC3','\x8C'),
            output2('\xC3','\x8D'),        output2('\xC3','\x8E'),
            output2('\xC3','\x8F'),        output2('\xC5','\xB4'),
            output2('\xC3','\x91'),        output2('\xC3','\x92'),
            output2('\xC3','\x93'),        output2('\xC3','\x94'),
            output2('\xC3','\x95'),        output2('\xC3','\x96'),
     output3('\xE1','\xB9','\xAA'),        output2('\xC3','\x98'),
            output2('\xC3','\x99'),        output2('\xC3','\x9A'),
            output2('\xC3','\x9B'),        output2('\xC3','\x9C'),
            output2('\xC3','\x9D'),        output2('\xC5','\xB6'),
            output2('\xC3','\x9F'),        output2('\xC3','\xA0'),
            output2('\xC3','\xA1'),        output2('\xC3','\xA2'),
            output2('\xC3','\xA3'),        output2('\xC3','\xA4'),
            output2('\xC3','\xA5'),        output2('\xC3','\xA6'),
            output2('\xC3','\xA7'),        output2('\xC3','\xA8'),
            output2('\xC3','\xA9'),        output2('\xC3','\xAA'),
            output2('\xC3','\xAB'),        output2('\xC3','\xAC'),
            output2('\xC3','\xAD'),        output2('\xC3','\xAE'),
            output2('\xC3','\xAF'),        output2('\xC5','\xB5'),
            output2('\xC3','\xB1'),        output2('\xC3','\xB2'),
            output2('\xC3','\xB3'),        output2('\xC3','\xB4'),
            output2('\xC3','\xB5'),        output2('\xC3','\xB6'),
     output3('\xE1','\xB9','\xAB'),        output2('\xC3','\xB8'),
            output2('\xC3','\xB9'),        output2('\xC3','\xBA'),
            output2('\xC3','\xBB'),        output2('\xC3','\xBC'),
            output2('\xC3','\xBD'),        output2('\xC5','\xB7'),
            output2('\xC3','\xBF'),
};
const BYTE_LOOKUP
from_ISO_8859_14 = {
    from_ISO_8859_14_offsets,
    from_ISO_8859_14_infos
};

static const unsigned char
to_ISO_8859_14_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, -1, -1, 33, -1, -1, -1, 34,   -1, 35, -1, -1, -1, 36, 37, -1,
     -1, -1, -1, -1, -1, -1, 38, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_C2_infos[39] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA3'), output1('\xA7'), output1('\xA9'),
     output1('\xAD'), output1('\xAE'), output1('\xB6'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_C2 = {
    to_ISO_8859_14_C2_offsets,
    to_ISO_8859_14_C2_infos
};

static const unsigned char
to_ISO_8859_14_C3_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     -1, 16, 17, 18, 19, 20, 21, -1,   22, 23, 24, 25, 26, 27, -1, 28,
     29, 30, 31, 32, 33, 34, 35, 36,   37, 38, 39, 40, 41, 42, 43, 44,
     -1, 45, 46, 47, 48, 49, 50, -1,   51, 52, 53, 54, 55, 56, -1, 57,
};
static const void* const
to_ISO_8859_14_C3_infos[58] = {
     output1('\xC0'), output1('\xC1'), output1('\xC2'), output1('\xC3'),
     output1('\xC4'), output1('\xC5'), output1('\xC6'), output1('\xC7'),
     output1('\xC8'), output1('\xC9'), output1('\xCA'), output1('\xCB'),
     output1('\xCC'), output1('\xCD'), output1('\xCE'), output1('\xCF'),
     output1('\xD1'), output1('\xD2'), output1('\xD3'), output1('\xD4'),
     output1('\xD5'), output1('\xD6'), output1('\xD8'), output1('\xD9'),
     output1('\xDA'), output1('\xDB'), output1('\xDC'), output1('\xDD'),
     output1('\xDF'), output1('\xE0'), output1('\xE1'), output1('\xE2'),
     output1('\xE3'), output1('\xE4'), output1('\xE5'), output1('\xE6'),
     output1('\xE7'), output1('\xE8'), output1('\xE9'), output1('\xEA'),
     output1('\xEB'), output1('\xEC'), output1('\xED'), output1('\xEE'),
     output1('\xEF'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF8'),
     output1('\xF9'), output1('\xFA'), output1('\xFB'), output1('\xFC'),
     output1('\xFD'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_C3 = {
    to_ISO_8859_14_C3_offsets,
    to_ISO_8859_14_C3_infos
};

static const unsigned char
to_ISO_8859_14_C4_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1,  0,  1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      2,  3, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_C4_infos[4] = {
     output1('\xA4'), output1('\xA5'), output1('\xB2'), output1('\xB3'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_C4 = {
    to_ISO_8859_14_C4_offsets,
    to_ISO_8859_14_C4_infos
};

static const unsigned char
to_ISO_8859_14_C5_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1,  0,  1,  2,  3,    4, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_C5_infos[5] = {
     output1('\xD0'), output1('\xF0'), output1('\xDE'), output1('\xFE'),
     output1('\xAF'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_C5 = {
    to_ISO_8859_14_C5_offsets,
    to_ISO_8859_14_C5_infos
};

static const unsigned char
to_ISO_8859_14_E1_B8_offsets[64] = {
     -1, -1,  0,  1, -1, -1, -1, -1,   -1, -1,  2,  3, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1,  4,  5,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_E1_B8_infos[6] = {
     output1('\xA1'), output1('\xA2'), output1('\xA6'), output1('\xAB'),
     output1('\xB0'), output1('\xB1'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_E1_B8 = {
    to_ISO_8859_14_E1_B8_offsets,
    to_ISO_8859_14_E1_B8_infos
};

static const unsigned char
to_ISO_8859_14_E1_B9_offsets[64] = {
      0,  1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1,  2,  3,   -1, -1, -1, -1, -1, -1, -1, -1,
      4,  5, -1, -1, -1, -1, -1, -1,   -1, -1,  6,  7, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_E1_B9_infos[8] = {
     output1('\xB4'), output1('\xB5'), output1('\xB7'), output1('\xB9'),
     output1('\xBB'), output1('\xBF'), output1('\xD7'), output1('\xF7'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_E1_B9 = {
    to_ISO_8859_14_E1_B9_offsets,
    to_ISO_8859_14_E1_B9_infos
};

static const unsigned char
to_ISO_8859_14_E1_BA_offsets[64] = {
      0,  1,  2,  3,  4,  5, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_E1_BA_infos[6] = {
     output1('\xA8'), output1('\xB8'), output1('\xAA'), output1('\xBA'),
     output1('\xBD'), output1('\xBE'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_E1_BA = {
    to_ISO_8859_14_E1_BA_offsets,
    to_ISO_8859_14_E1_BA_infos
};

static const unsigned char
to_ISO_8859_14_E1_BB_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  0,  1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_E1_BB_infos[2] = {
     output1('\xAC'), output1('\xBC'),
};
static const BYTE_LOOKUP
to_ISO_8859_14_E1_BB = {
    to_ISO_8859_14_E1_BB_offsets,
    to_ISO_8859_14_E1_BB_infos
};

static const unsigned char
to_ISO_8859_14_E1_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    0,  1,  2,  3, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_E1_infos[4] = {
     &to_ISO_8859_14_E1_B8, &to_ISO_8859_14_E1_B9,
     &to_ISO_8859_14_E1_BA, &to_ISO_8859_14_E1_BB,
};
static const BYTE_LOOKUP
to_ISO_8859_14_E1 = {
    to_ISO_8859_14_E1_offsets,
    to_ISO_8859_14_E1_infos
};

static const unsigned char
to_ISO_8859_14_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2,  3,  4, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1,  5, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_14_infos[6] = {
                  NOMAP, &to_ISO_8859_14_C2, &to_ISO_8859_14_C3, &to_ISO_8859_14_C4,
     &to_ISO_8859_14_C5, &to_ISO_8859_14_E1,
};
const BYTE_LOOKUP
to_ISO_8859_14 = {
    to_ISO_8859_14_offsets,
    to_ISO_8859_14_infos
};

static const unsigned char
from_ISO_8859_15_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      1,  2,  3,  4,  5,  6,  7,  8,    9, 10, 11, 12, 13, 14, 15, 16,
     17, 18, 19, 20, 21, 22, 23, 24,   25, 26, 27, 28, 29, 30, 31, 32,
     33, 34, 35, 36, 37, 38, 39, 40,   41, 42, 43, 44, 45, 46, 47, 48,
     49, 50, 51, 52, 53, 54, 55, 56,   57, 58, 59, 60, 61, 62, 63, 64,
     65, 66, 67, 68, 69, 70, 71, 72,   73, 74, 75, 76, 77, 78, 79, 80,
     81, 82, 83, 84, 85, 86, 87, 88,   89, 90, 91, 92, 93, 94, 95, 96,
     97, 98, 99,100,101,102,103,104,  105,106,107,108,109,110,111,112,
    113,114,115,116,117,118,119,120,  121,122,123,124,125,126,127,128,
};
static const void* const
from_ISO_8859_15_infos[129] = {
                             NOMAP,        output2('\xC2','\x80'),
            output2('\xC2','\x81'),        output2('\xC2','\x82'),
            output2('\xC2','\x83'),        output2('\xC2','\x84'),
            output2('\xC2','\x85'),        output2('\xC2','\x86'),
            output2('\xC2','\x87'),        output2('\xC2','\x88'),
            output2('\xC2','\x89'),        output2('\xC2','\x8A'),
            output2('\xC2','\x8B'),        output2('\xC2','\x8C'),
            output2('\xC2','\x8D'),        output2('\xC2','\x8E'),
            output2('\xC2','\x8F'),        output2('\xC2','\x90'),
            output2('\xC2','\x91'),        output2('\xC2','\x92'),
            output2('\xC2','\x93'),        output2('\xC2','\x94'),
            output2('\xC2','\x95'),        output2('\xC2','\x96'),
            output2('\xC2','\x97'),        output2('\xC2','\x98'),
            output2('\xC2','\x99'),        output2('\xC2','\x9A'),
            output2('\xC2','\x9B'),        output2('\xC2','\x9C'),
            output2('\xC2','\x9D'),        output2('\xC2','\x9E'),
            output2('\xC2','\x9F'),        output2('\xC2','\xA0'),
            output2('\xC2','\xA1'),        output2('\xC2','\xA2'),
            output2('\xC2','\xA3'), output3('\xE2','\x82','\xAC'),
            output2('\xC2','\xA5'),        output2('\xC5','\xA0'),
            output2('\xC2','\xA7'),        output2('\xC5','\xA1'),
            output2('\xC2','\xA9'),        output2('\xC2','\xAA'),
            output2('\xC2','\xAB'),        output2('\xC2','\xAC'),
            output2('\xC2','\xAD'),        output2('\xC2','\xAE'),
            output2('\xC2','\xAF'),        output2('\xC2','\xB0'),
            output2('\xC2','\xB1'),        output2('\xC2','\xB2'),
            output2('\xC2','\xB3'),        output2('\xC5','\xBD'),
            output2('\xC2','\xB5'),        output2('\xC2','\xB6'),
            output2('\xC2','\xB7'),        output2('\xC5','\xBE'),
            output2('\xC2','\xB9'),        output2('\xC2','\xBA'),
            output2('\xC2','\xBB'),        output2('\xC5','\x92'),
            output2('\xC5','\x93'),        output2('\xC5','\xB8'),
            output2('\xC2','\xBF'),        output2('\xC3','\x80'),
            output2('\xC3','\x81'),        output2('\xC3','\x82'),
            output2('\xC3','\x83'),        output2('\xC3','\x84'),
            output2('\xC3','\x85'),        output2('\xC3','\x86'),
            output2('\xC3','\x87'),        output2('\xC3','\x88'),
            output2('\xC3','\x89'),        output2('\xC3','\x8A'),
            output2('\xC3','\x8B'),        output2('\xC3','\x8C'),
            output2('\xC3','\x8D'),        output2('\xC3','\x8E'),
            output2('\xC3','\x8F'),        output2('\xC3','\x90'),
            output2('\xC3','\x91'),        output2('\xC3','\x92'),
            output2('\xC3','\x93'),        output2('\xC3','\x94'),
            output2('\xC3','\x95'),        output2('\xC3','\x96'),
            output2('\xC3','\x97'),        output2('\xC3','\x98'),
            output2('\xC3','\x99'),        output2('\xC3','\x9A'),
            output2('\xC3','\x9B'),        output2('\xC3','\x9C'),
            output2('\xC3','\x9D'),        output2('\xC3','\x9E'),
            output2('\xC3','\x9F'),        output2('\xC3','\xA0'),
            output2('\xC3','\xA1'),        output2('\xC3','\xA2'),
            output2('\xC3','\xA3'),        output2('\xC3','\xA4'),
            output2('\xC3','\xA5'),        output2('\xC3','\xA6'),
            output2('\xC3','\xA7'),        output2('\xC3','\xA8'),
            output2('\xC3','\xA9'),        output2('\xC3','\xAA'),
            output2('\xC3','\xAB'),        output2('\xC3','\xAC'),
            output2('\xC3','\xAD'),        output2('\xC3','\xAE'),
            output2('\xC3','\xAF'),        output2('\xC3','\xB0'),
            output2('\xC3','\xB1'),        output2('\xC3','\xB2'),
            output2('\xC3','\xB3'),        output2('\xC3','\xB4'),
            output2('\xC3','\xB5'),        output2('\xC3','\xB6'),
            output2('\xC3','\xB7'),        output2('\xC3','\xB8'),
            output2('\xC3','\xB9'),        output2('\xC3','\xBA'),
            output2('\xC3','\xBB'),        output2('\xC3','\xBC'),
            output2('\xC3','\xBD'),        output2('\xC3','\xBE'),
            output2('\xC3','\xBF'),
};
const BYTE_LOOKUP
from_ISO_8859_15 = {
    from_ISO_8859_15_offsets,
    from_ISO_8859_15_infos
};

static const unsigned char
to_ISO_8859_15_C2_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, -1, 36, -1, 37,   -1, 38, 39, 40, 41, 42, 43, 44,
     45, 46, 47, 48, -1, 49, 50, 51,   -1, 52, 53, 54, -1, -1, -1, 55,
};
static const void* const
to_ISO_8859_15_C2_infos[56] = {
     output1('\x80'), output1('\x81'), output1('\x82'), output1('\x83'),
     output1('\x84'), output1('\x85'), output1('\x86'), output1('\x87'),
     output1('\x88'), output1('\x89'), output1('\x8A'), output1('\x8B'),
     output1('\x8C'), output1('\x8D'), output1('\x8E'), output1('\x8F'),
     output1('\x90'), output1('\x91'), output1('\x92'), output1('\x93'),
     output1('\x94'), output1('\x95'), output1('\x96'), output1('\x97'),
     output1('\x98'), output1('\x99'), output1('\x9A'), output1('\x9B'),
     output1('\x9C'), output1('\x9D'), output1('\x9E'), output1('\x9F'),
     output1('\xA0'), output1('\xA1'), output1('\xA2'), output1('\xA3'),
     output1('\xA5'), output1('\xA7'), output1('\xA9'), output1('\xAA'),
     output1('\xAB'), output1('\xAC'), output1('\xAD'), output1('\xAE'),
     output1('\xAF'), output1('\xB0'), output1('\xB1'), output1('\xB2'),
     output1('\xB3'), output1('\xB5'), output1('\xB6'), output1('\xB7'),
     output1('\xB9'), output1('\xBA'), output1('\xBB'), output1('\xBF'),
};
static const BYTE_LOOKUP
to_ISO_8859_15_C2 = {
    to_ISO_8859_15_C2_offsets,
    to_ISO_8859_15_C2_infos
};

static const unsigned char
to_ISO_8859_15_C3_offsets[64] = {
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23,   24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39,   40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55,   56, 57, 58, 59, 60, 61, 62, 63,
};
static const void* const
to_ISO_8859_15_C3_infos[64] = {
     output1('\xC0'), output1('\xC1'), output1('\xC2'), output1('\xC3'),
     output1('\xC4'), output1('\xC5'), output1('\xC6'), output1('\xC7'),
     output1('\xC8'), output1('\xC9'), output1('\xCA'), output1('\xCB'),
     output1('\xCC'), output1('\xCD'), output1('\xCE'), output1('\xCF'),
     output1('\xD0'), output1('\xD1'), output1('\xD2'), output1('\xD3'),
     output1('\xD4'), output1('\xD5'), output1('\xD6'), output1('\xD7'),
     output1('\xD8'), output1('\xD9'), output1('\xDA'), output1('\xDB'),
     output1('\xDC'), output1('\xDD'), output1('\xDE'), output1('\xDF'),
     output1('\xE0'), output1('\xE1'), output1('\xE2'), output1('\xE3'),
     output1('\xE4'), output1('\xE5'), output1('\xE6'), output1('\xE7'),
     output1('\xE8'), output1('\xE9'), output1('\xEA'), output1('\xEB'),
     output1('\xEC'), output1('\xED'), output1('\xEE'), output1('\xEF'),
     output1('\xF0'), output1('\xF1'), output1('\xF2'), output1('\xF3'),
     output1('\xF4'), output1('\xF5'), output1('\xF6'), output1('\xF7'),
     output1('\xF8'), output1('\xF9'), output1('\xFA'), output1('\xFB'),
     output1('\xFC'), output1('\xFD'), output1('\xFE'), output1('\xFF'),
};
static const BYTE_LOOKUP
to_ISO_8859_15_C3 = {
    to_ISO_8859_15_C3_offsets,
    to_ISO_8859_15_C3_infos
};

static const unsigned char
to_ISO_8859_15_C5_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  0,  1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      2,  3, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,    4, -1, -1, -1, -1,  5,  6, -1,
};
static const void* const
to_ISO_8859_15_C5_infos[7] = {
     output1('\xBC'), output1('\xBD'), output1('\xA6'), output1('\xA8'),
     output1('\xBE'), output1('\xB4'), output1('\xB8'),
};
static const BYTE_LOOKUP
to_ISO_8859_15_C5 = {
    to_ISO_8859_15_C5_offsets,
    to_ISO_8859_15_C5_infos
};

static const unsigned char
to_ISO_8859_15_E2_82_offsets[64] = {
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1,  0, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_15_E2_82_infos[1] = {
     output1('\xA4'),
};
static const BYTE_LOOKUP
to_ISO_8859_15_E2_82 = {
    to_ISO_8859_15_E2_82_offsets,
    to_ISO_8859_15_E2_82_infos
};

static const unsigned char
to_ISO_8859_15_E2_offsets[64] = {
     -1, -1,  0, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_15_E2_infos[1] = {
     &to_ISO_8859_15_E2_82,
};
static const BYTE_LOOKUP
to_ISO_8859_15_E2 = {
    to_ISO_8859_15_E2_offsets,
    to_ISO_8859_15_E2_infos
};

static const unsigned char
to_ISO_8859_15_offsets[256] = {
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,    0,  0,  0,  0,  0,  0,  0,  0,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  1,  2, -1,  3, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1,  4, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
};
static const void* const
to_ISO_8859_15_infos[5] = {
                  NOMAP, &to_ISO_8859_15_C2, &to_ISO_8859_15_C3, &to_ISO_8859_15_C5,
     &to_ISO_8859_15_E2,
};
const BYTE_LOOKUP
to_ISO_8859_15 = {
    to_ISO_8859_15_offsets,
    to_ISO_8859_15_infos
};

