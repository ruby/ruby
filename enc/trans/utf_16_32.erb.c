#include "transcode_data.h"

static int
fun_so_from_utf_16be(const unsigned char* s, unsigned char* o)
{
    if (!s[0] && s[1]<0x80) {
        o[0] = s[1];
        return 1;
    }
    else if (s[0]<0x08) {
        o[0] = 0xC0 | (s[0]<<2) | (s[1]>>6);
        o[1] = 0x80 | (s[1]&0x3F);
        return 2;
    }
    else if ((s[0]&0xF8)!=0xD8) {
        o[0] = 0xE0 | (s[0]>>4);
        o[1] = 0x80 | ((s[0]&0x0F)<<2) | (s[1]>>6);
        o[2] = 0x80 | (s[1]&0x3F);
        return 3;
    }
    else {
        unsigned int u = (((s[0]&0x03)<<2)|(s[1]>>6)) + 1;
        o[0] = 0xF0 | (u>>2);
        o[1] = 0x80 | ((u&0x03)<<4) | ((s[1]>>2)&0x0F);
        o[2] = 0x80 | ((s[1]&0x03)<<4) | ((s[2]&0x03)<<2) | (s[3]>>6);
        o[3] = 0x80 | (s[3]&0x3F);
        return 4;
    }
}

static int
fun_so_to_utf_16be(const unsigned char* s, unsigned char* o)
{
    if (!(s[0]&0x80)) {
        o[0] = 0x00;
        o[1] = s[0];
        return 2;
    }
    else if ((s[0]&0xE0)==0xC0) {
        o[0] = (s[0]>>2)&0x07;
        o[1] = ((s[0]&0x03)<<6) | (s[1]&0x3F);
        return 2;
    }
    else if ((s[0]&0xF0)==0xE0) {
        o[0] = (s[0]<<4) | ((s[1]>>2)^0x20);
        o[1] = (s[1]<<6) | (s[2]^0x80);
        return 2;
    }
    else {
        int w = (((s[0]&0x07)<<2) | ((s[1]>>4)&0x03)) - 1;
        o[0] = 0xD8 | (w>>2);
        o[1] = (w<<6) | ((s[1]&0x0F)<<2) | ((s[2]>>4)-8);
        o[2] = 0xDC | ((s[2]>>2)&0x03);
        o[3] = (s[2]<<6) | (s[3]&~0x80);
        return 4;
    }
}

static int
fun_so_from_utf_16le(const unsigned char* s, unsigned char* o)
{
    if (!s[1] && s[0]<0x80) {
        o[0] = s[0];
        return 1;
    }
    else if (s[1]<0x08) {
        o[0] = 0xC0 | (s[1]<<2) | (s[0]>>6);
        o[1] = 0x80 | (s[0]&0x3F);
        return 2;
    }
    else if ((s[1]&0xF8)!=0xD8) {
        o[0] = 0xE0 | (s[1]>>4);
        o[1] = 0x80 | ((s[1]&0x0F)<<2) | (s[0]>>6);
        o[2] = 0x80 | (s[0]&0x3F);
        return 3;
    }
    else {
        unsigned int u = (((s[1]&0x03)<<2)|(s[0]>>6)) + 1;
        o[0] = 0xF0 | u>>2;
        o[1] = 0x80 | ((u&0x03)<<4) | ((s[0]>>2)&0x0F);
        o[2] = 0x80 | ((s[0]&0x03)<<4) | ((s[3]&0x03)<<2) | (s[2]>>6);
        o[3] = 0x80 | (s[2]&0x3F);
        return 4;
    }
}

static int
fun_so_to_utf_16le(const unsigned char* s, unsigned char* o)
{
    if (!(s[0]&0x80)) {
        o[1] = 0x00;
        o[0] = s[0];
        return 2;
    }
    else if ((s[0]&0xE0)==0xC0) {
        o[1] = (s[0]>>2)&0x07;
        o[0] = ((s[0]&0x03)<<6) | (s[1]&0x3F);
        return 2;
    }
    else if ((s[0]&0xF0)==0xE0) {
        o[1] = (s[0]<<4) | ((s[1]>>2)^0x20);
        o[0] = (s[1]<<6) | (s[2]^0x80);
        return 2;
    }
    else {
        int w = (((s[0]&0x07)<<2) | ((s[1]>>4)&0x03)) - 1;
        o[1] = 0xD8 | (w>>2);
        o[0] = (w<<6) | ((s[1]&0x0F)<<2) | ((s[2]>>4)-8);
        o[3] = 0xDC | ((s[2]>>2)&0x03);
        o[2] = (s[2]<<6) | (s[3]&~0x80);
        return 4;
    }
}

static int
fun_so_from_utf_32be(const unsigned char* s, unsigned char* o)
{
    if (!s[1]) {
        if (s[2]==0 && s[3]<0x80) {
            o[0] = s[3];
            return 1;
        }
        else if (s[2]<0x08) {
            o[0] = 0xC0 | (s[2]<<2) | (s[3]>>6);
            o[1] = 0x80 | (s[3]&0x3F);
            return 2;
        }
        else {
            o[0] = 0xE0 | (s[2]>>4);
            o[1] = 0x80 | ((s[2]&0x0F)<<2) | (s[3]>>6);
            o[2] = 0x80 | (s[3]&0x3F);
            return 3;
        }
    }
    else {
        o[0] = 0xF0 | (s[1]>>2);
        o[1] = 0x80 | ((s[1]&0x03)<<4) | (s[2]>>4);
        o[2] = 0x80 | ((s[2]&0x0F)<<2) | (s[3]>>6);
        o[3] = 0x80 | (s[3]&0x3F);
        return 4;
    }
}

static int
fun_so_to_utf_32be(const unsigned char* s, unsigned char* o)
{
    o[0] = 0;
    if (!(s[0]&0x80)) {
        o[1] = o[2] = 0x00;
        o[3] = s[0];
    }
    else if ((s[0]&0xE0)==0xC0) {
        o[1] = 0x00;
        o[2] = (s[0]>>2)&0x07;
        o[3] = ((s[0]&0x03)<<6) | (s[1]&0x3F);
    }
    else if ((s[0]&0xF0)==0xE0) {
        o[1] = 0x00;
        o[2] = (s[0]<<4) | ((s[1]>>2)^0x20);
        o[3] = (s[1]<<6) | (s[2]^0x80);
    }
    else {
        o[1] = ((s[0]&0x07)<<2) | ((s[1]>>4)&0x03);
        o[2] = ((s[1]&0x0F)<<4) | ((s[2]>>2)&0x0F);
        o[3] = ((s[2]&0x03)<<6) | (s[3]&0x3F);
    }
    return 4;
}

static int
fun_so_from_utf_32le(const unsigned char* s, unsigned char* o)
{
    return 1;
}

static int
fun_so_to_utf_32le(const unsigned char* s, unsigned char* o)
{
    return 4;
}

<%=
  map = {}
  map["{00-d7,e0-ff}{00-ff}"] = :func_so
  map["{d8-db}{00-ff}{dc-df}{00-ff}"] = :func_so
  map["{dc-df}{00-ff}"] = :invalid
  map["{d8-db}{00-ff}{00-db,e0-ff}{00-ff}"] = :invalid
  code = ''
  transcode_generate_node(ActionMap.parse(map), code, "from_UTF_16BE", [])
  code
%>

static const rb_transcoder
rb_from_UTF_16BE = {
    "UTF-16BE", "UTF-8", &from_UTF_16BE, 4, 0,
    NULL, NULL, NULL, NULL, NULL, &fun_so_from_utf_16be
};

<%=
  map = {}
  map["{00-7f}"] = :func_so
  map["{c2-df}{80-bf}"] = :func_so
  map["e0{a0-bf}{80-bf}"] = :func_so
  map["{e1-ec}{80-bf}{80-bf}"] = :func_so
  map["ed{80-9f}{80-bf}"] = :func_so
  map["{ee-ef}{80-bf}{80-bf}"] = :func_so
  map["f0{90-bf}{80-bf}{80-bf}"] = :func_so
  map["{f1-f3}{80-bf}{80-bf}{80-bf}"] = :func_so
  map["f4{80-8f}{80-bf}{80-bf}"] = :func_so
  map["{80-c1,f5-ff}"] = :invalid
  map["e0{80-9f}"] = :invalid
  map["ed{a0-bf}"] = :invalid
  map["f0{80-8f}"] = :invalid
  map["f4{90-bf}"] = :invalid
  code = ''
  am = ActionMap.parse(map)
  transcode_generate_node(am, code, "to_UTF_16BE", [0x00..0xff, 0x80..0xbf, 0x80..0xbf, 0x80..0xbf])
  code
%>

static const rb_transcoder
rb_to_UTF_16BE = {
    "UTF-8", "UTF-16BE", &to_UTF_16BE, 4, 1,
    NULL, NULL, NULL, NULL, NULL, &fun_so_to_utf_16be
};

<%=
  map = {}
  map["{00-ff}{00-d7,e0-ff}"] = :func_so
  map["{00-ff}{d8-db}{00-ff}{dc-df}"] = :func_so
  map["{00-ff}{dc-df}"] = :invalid
  map["{00-ff}{d8-db}{00-ff}{00-db,e0-ff}"] = :invalid
  code = ''
  transcode_generate_node(ActionMap.parse(map), code, "from_UTF_16LE", [])
  code
%>

static const rb_transcoder
rb_from_UTF_16LE = {
    "UTF-16LE", "UTF-8", &from_UTF_16LE, 4, 0,
    NULL, NULL, NULL, NULL, NULL, &fun_so_from_utf_16le
};

static const rb_transcoder
rb_to_UTF_16LE = {
    "UTF-8", "UTF-16LE", &to_UTF_16BE, 4, 1,
    NULL, NULL, NULL, NULL, NULL, &fun_so_to_utf_16le
};

<%=
  map = {}
  map["0000{00-d7,e0-ff}{00-ff}"] = :func_so
  map["00{01-10}{00-ff}{00-ff}"] = :func_so
  map["00{11-ff}{00-ff}{00-ff}"] = :invalid
  map["0000{d8-df}{00-ff}"] = :invalid
  map["{01-ff}{00-ff}{00-ff}{00-ff}"] = :invalid
  code = ''
  transcode_generate_node(ActionMap.parse(map), code, "from_UTF_32BE", [])
  code
%>

static const rb_transcoder
rb_from_UTF_32BE = {
    "UTF-32BE", "UTF-8", &from_UTF_32BE, 4, 0,
    NULL, NULL, NULL, NULL, NULL, &fun_so_from_utf_32be
};

static const rb_transcoder
rb_to_UTF_32BE = {
    "UTF-8", "UTF-32BE", &to_UTF_16BE, 4, 1,
    NULL, NULL, NULL, NULL, NULL, &fun_so_to_utf_32be
};

<%=
  map = {}
  map["{00-ff}{00-d7,e0-ff}0000"] = :func_so
  map["{00-ff}{00-ff}{01-10}00"] = :func_so
  map["{00-ff}{00-ff}{00-ff}{01-ff}"] = :invalid
  map["{00-ff}{00-ff}{11-ff}00"] = :invalid
  map["{00-ff}{d8-df}0000"] = :invalid
  code = ''
  transcode_generate_node(ActionMap.parse(map), code, "from_UTF_32LE", [])
  code
%>

static const rb_transcoder
rb_from_UTF_32LE = {
    "UTF-32LE", "UTF-8", &from_UTF_32LE, 4, 0,
    NULL, NULL, NULL, NULL, NULL, &fun_so_from_utf_32le
};

static const rb_transcoder
rb_to_UTF_32LE = {
    "UTF-8", "UTF-32LE", &to_UTF_16BE, 4, 1,
    NULL, NULL, NULL, NULL, NULL, &fun_so_to_utf_32le
};

void
Init_utf_16_32(void)
{
    rb_register_transcoder(&rb_from_UTF_16BE);
    rb_register_transcoder(&rb_to_UTF_16BE);
    rb_register_transcoder(&rb_from_UTF_16LE);
    rb_register_transcoder(&rb_to_UTF_16LE);
    rb_register_transcoder(&rb_from_UTF_32BE);
    rb_register_transcoder(&rb_to_UTF_32BE);
    rb_register_transcoder(&rb_from_UTF_32LE);
    rb_register_transcoder(&rb_to_UTF_32LE);
}
