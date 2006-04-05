/************************************************

  tkutil.c -

  $Author$
  $Date$
  created at: Fri Nov  3 00:47:54 JST 1995

************************************************/

#define TKUTIL_RELEASE_DATE "2006-04-06"

#include "ruby.h"
#include "rubysig.h"
#include "version.h"
#include "st.h"

static VALUE cMethod;

static VALUE cTclTkLib;

static VALUE cTkObject;
static VALUE cTkCallbackEntry;

static VALUE TK_None;

static VALUE cCB_SUBST;
static VALUE cSUBST_INFO;

static ID ID_split_tklist;
static ID ID_toUTF8;
static ID ID_fromUTF8;
static ID ID_path;
static ID ID_at_path;
static ID ID_at_enc;
static ID ID_to_eval;
static ID ID_to_s;
static ID ID_source;
static ID ID_downcase;
static ID ID_install_cmd;
static ID ID_merge_tklist;
static ID ID_encoding;
static ID ID_encoding_system;
static ID ID_call;

static ID ID_SUBST_INFO;

static VALUE CALLBACK_TABLE;
static unsigned long CALLBACK_ID_NUM = 0;

/*************************************/

static VALUE
tk_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj = rb_class_new_instance(argc, argv, klass);

    if (rb_block_given_p()) {
#if RUBY_VERSION_MAJOR == 1 && RUBY_VERSION_MINOR <= 8 /* ruby 1.8.x */
      rb_obj_instance_eval(0, 0, obj);
#else
      rb_obj_instance_exec(1, &obj, obj);
#endif
    }
    return obj;
}

/*************************************/

static VALUE
tkNone_to_s(self)
    VALUE self;
{
    return rb_str_new2("None");
}

/*************************************/

static VALUE
tk_eval_cmd(argc, argv, self)
    int argc;
    VALUE argv[];
    VALUE self;
{
    volatile VALUE cmd, rest;

    rb_scan_args(argc, argv, "1*", &cmd, &rest);
    return rb_eval_cmd(cmd, rest, 0);
}

static VALUE
tk_do_callback(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
#if 0
    volatile VALUE id;
    volatile VALUE rest;

    rb_scan_args(argc, argv, "1*", &id, &rest);
    return rb_apply(rb_hash_aref(CALLBACK_TABLE, id), ID_call, rest);
#endif
    return rb_funcall2(rb_hash_aref(CALLBACK_TABLE, argv[0]), 
                       ID_call, argc - 1, argv + 1);
}

static char *cmd_id_head = "ruby_cmd TkUtil callback ";
static char *cmd_id_prefix = "cmd";

static VALUE
tk_install_cmd_core(cmd)
    VALUE cmd;
{
    volatile VALUE id_num;

    id_num = ULONG2NUM(CALLBACK_ID_NUM++);
    id_num = rb_funcall(id_num, ID_to_s, 0, 0);
    id_num = rb_str_append(rb_str_new2(cmd_id_prefix), id_num);
    rb_hash_aset(CALLBACK_TABLE, id_num, cmd);
    return rb_str_append(rb_str_new2(cmd_id_head), id_num);
}

static VALUE
tk_install_cmd(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    volatile VALUE cmd;

#if 0
    if (rb_scan_args(argc, argv, "01", &cmd) == 0) {
        cmd = rb_block_proc();
    }
    return tk_install_cmd_core(cmd);
#endif
    if (argc == 0) {
        cmd = rb_block_proc();
    } else {
        cmd = argv[0];
    }
    return tk_install_cmd_core(cmd);
}

static VALUE
tk_uninstall_cmd(self, cmd_id)
    VALUE self;
    VALUE cmd_id;
{
    int head_len = strlen(cmd_id_head);
    int prefix_len = strlen(cmd_id_prefix);

    StringValue(cmd_id);
    if (strncmp(cmd_id_head, RSTRING(cmd_id)->ptr, head_len) != 0) {
        return Qnil;
    }
    if (strncmp(cmd_id_prefix, 
                RSTRING(cmd_id)->ptr + head_len, prefix_len) != 0) {
        return Qnil;
    }

    return rb_hash_delete(CALLBACK_TABLE, 
                          rb_str_new2(RSTRING(cmd_id)->ptr + head_len));
}

static VALUE
tk_toUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    return rb_funcall2(cTclTkLib, ID_toUTF8, argc, argv);
}

static VALUE
tk_fromUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    return rb_funcall2(cTclTkLib, ID_fromUTF8, argc, argv);
}

static VALUE
fromDefaultEnc_toUTF8(str, self)
    VALUE str;
    VALUE self;
{
    VALUE argv[1];

    argv[0] = str;
    return tk_toUTF8(1, argv, self);
}

static VALUE
fromUTF8_toDefaultEnc(str, self)
    VALUE str;
    VALUE self;
{
    VALUE argv[1];

    argv[0] = str;
    return tk_fromUTF8(1, argv, self);
}

static int
to_strkey(key, value, hash)
    VALUE key;
    VALUE value;
    VALUE hash;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_hash_aset(hash, rb_funcall(key, ID_to_s, 0, 0), value);
    return ST_CHECK;
}

static VALUE
tk_symbolkey2str(self, keys)
    VALUE self;
    VALUE keys;
{
    volatile VALUE new_keys = rb_hash_new();

    if NIL_P(keys) return new_keys;
    keys = rb_convert_type(keys, T_HASH, "Hash", "to_hash");
    st_foreach(RHASH(keys)->tbl, to_strkey, new_keys);
    return new_keys;
}

static VALUE get_eval_string_core _((VALUE, VALUE, VALUE));
static VALUE ary2list _((VALUE, VALUE, VALUE));
static VALUE ary2list2 _((VALUE, VALUE, VALUE));
static VALUE hash2list _((VALUE, VALUE));
static VALUE hash2list_enc _((VALUE, VALUE));
static VALUE hash2kv _((VALUE, VALUE, VALUE));
static VALUE hash2kv_enc _((VALUE, VALUE, VALUE));

static VALUE
ary2list(ary, enc_flag, self)
    VALUE ary;
    VALUE enc_flag;
    VALUE self;
{
    int idx, idx2, size, size2, req_chk_flag;
    volatile VALUE val, val2, str_val;
    volatile VALUE dst;
    volatile VALUE sys_enc, dst_enc, str_enc;

    sys_enc = rb_funcall(cTclTkLib, ID_encoding, 0, 0);
    if (NIL_P(sys_enc)) {
      sys_enc = rb_funcall(cTclTkLib, ID_encoding_system, 0, 0);
      sys_enc = rb_funcall(sys_enc, ID_to_s, 0, 0);
    }

    if NIL_P(enc_flag) {
        dst_enc = sys_enc;
        req_chk_flag = 1;
    } else if (TYPE(enc_flag) == T_TRUE || TYPE(enc_flag) == T_FALSE) {
        dst_enc = enc_flag;
        req_chk_flag = 0;
    } else {
        dst_enc = rb_funcall(enc_flag, ID_to_s, 0, 0);
        req_chk_flag = 0;
    }

    /* size = RARRAY(ary)->len; */
    size = 0;
    for(idx = 0; idx < RARRAY(ary)->len; idx++) {
        if (TYPE(RARRAY(ary)->ptr[idx]) == T_HASH) {
            size += 2 * RHASH(RARRAY(ary)->ptr[idx])->tbl->num_entries;
        } else {
            size++;
        }
    }

    dst = rb_ary_new2(size);
    RARRAY(dst)->len = 0;
    for(idx = 0; idx < RARRAY(ary)->len; idx++) {
        val = RARRAY(ary)->ptr[idx];
        str_val = Qnil;
        switch(TYPE(val)) {
        case T_ARRAY:
            str_val = ary2list(val, enc_flag, self);
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;

            if (req_chk_flag) {
                str_enc = rb_ivar_get(str_val, ID_at_enc);
                if (!NIL_P(str_enc)) {
                    str_enc = rb_funcall(str_enc, ID_to_s, 0, 0);
                } else {
                    str_enc = sys_enc;
                }
                if (!rb_str_cmp(str_enc, dst_enc)) {
                    dst_enc = Qtrue;
                    req_chk_flag = 0;
                }
            }

            break;

        case T_HASH:
            /* RARRAY(dst)->ptr[RARRAY(dst)->len++] = hash2list(val, self); */
            if (RTEST(enc_flag)) {
                val = hash2kv_enc(val, Qnil, self);
            } else {
                val = hash2kv(val, Qnil, self);
            }
            size2 = RARRAY(val)->len;
            for(idx2 = 0; idx2 < size2; idx2++) {
                val2 = RARRAY(val)->ptr[idx2];
                switch(TYPE(val2)) {
                case T_ARRAY:
                    str_val = ary2list(val2, enc_flag, self);
                    RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;
                    break;

                case T_HASH:
                    if (RTEST(enc_flag)) {
                        str_val = hash2list_enc(val2, self);
                    } else {
                        str_val = hash2list(val2, self);
                    }
                    RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;
                    break;

                default:
                    if (val2 != TK_None) {
                        str_val = get_eval_string_core(val2, enc_flag, self);
                        RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;
                    }
                }

                if (req_chk_flag) {
                    str_enc = rb_ivar_get(str_val, ID_at_enc);
                    if (!NIL_P(str_enc)) {
                        str_enc = rb_funcall(str_enc, ID_to_s, 0, 0);
                    } else {
                        str_enc = sys_enc;
                    }
                    if (!rb_str_cmp(str_enc, dst_enc)) {
                        dst_enc = Qtrue;
                        req_chk_flag = 0;
                    }
                }
            }
            break;

        default:
            if (val != TK_None) {
                str_val = get_eval_string_core(val, enc_flag, self);
                RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;

                if (req_chk_flag) {
                    str_enc = rb_ivar_get(str_val, ID_at_enc);
                    if (!NIL_P(str_enc)) {
                        str_enc = rb_funcall(str_enc, ID_to_s, 0, 0);
                    } else {
                        str_enc = sys_enc;
                    }
                    if (!rb_str_cmp(str_enc, dst_enc)) {
                        dst_enc = Qtrue;
                        req_chk_flag = 0;
                    }
                }
            }
        }
    }

    if (RTEST(dst_enc) && !NIL_P(sys_enc)) {
        for(idx = 0; idx < RARRAY(dst)->len; idx++) {
            str_val = RARRAY(dst)->ptr[idx];
            if (rb_obj_respond_to(self, ID_toUTF8, Qtrue)) {
                str_val = rb_funcall(self, ID_toUTF8, 1, str_val);
            } else {
                str_val = rb_funcall(cTclTkLib, ID_toUTF8, 1, str_val);
            }
            RARRAY(dst)->ptr[idx] = str_val;
        }
        val = rb_apply(cTclTkLib, ID_merge_tklist, dst);
        if (TYPE(dst_enc) == T_STRING) {
            val = rb_funcall(cTclTkLib, ID_fromUTF8, 2, val, dst_enc);
            rb_ivar_set(val, ID_at_enc, dst_enc);
        } else {
            rb_ivar_set(val, ID_at_enc, rb_str_new2("utf-8"));
        }
        return val;
    } else {
        return rb_apply(cTclTkLib, ID_merge_tklist, dst);
    }
}

static VALUE
ary2list2(ary, enc_flag, self)
    VALUE ary;
    VALUE enc_flag;
    VALUE self;
{
    int idx, size, req_chk_flag;
    volatile VALUE val, str_val;
    volatile VALUE dst;
    volatile VALUE sys_enc, dst_enc, str_enc;

    sys_enc = rb_funcall(cTclTkLib, ID_encoding, 0, 0);
    if NIL_P(sys_enc) {
      sys_enc = rb_funcall(cTclTkLib, ID_encoding_system, 0, 0);
      sys_enc = rb_funcall(sys_enc, ID_to_s, 0, 0);
    }

    if NIL_P(enc_flag) {
        dst_enc = sys_enc;
        req_chk_flag = 1;
    } else if (TYPE(enc_flag) == T_TRUE || TYPE(enc_flag) == T_FALSE) {
        dst_enc = enc_flag;
        req_chk_flag = 0;
    } else {
        dst_enc = rb_funcall(enc_flag, ID_to_s, 0, 0);
        req_chk_flag = 0;
    }

    size = RARRAY(ary)->len;
    dst = rb_ary_new2(size);
    RARRAY(dst)->len = 0;
    for(idx = 0; idx < RARRAY(ary)->len; idx++) {
        val = RARRAY(ary)->ptr[idx];
        str_val = Qnil;
        switch(TYPE(val)) {
        case T_ARRAY:
            str_val = ary2list(val, enc_flag, self);
            break;

        case T_HASH:
            if (RTEST(enc_flag)) {
                str_val = hash2list(val, self);
            } else {
                str_val = hash2list_enc(val, self);
            }
            break;

        default:
            if (val != TK_None) {
                str_val = get_eval_string_core(val, enc_flag, self);
            }
        }

        if (!NIL_P(str_val)) {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = str_val;

            if (req_chk_flag) {
                str_enc = rb_ivar_get(str_val, ID_at_enc);
                if (!NIL_P(str_enc)) {
                    str_enc = rb_funcall(str_enc, ID_to_s, 0, 0);
                } else {
                    str_enc = sys_enc;
                }
                if (!rb_str_cmp(str_enc, dst_enc)) {
                    dst_enc = Qtrue;
                    req_chk_flag = 0;
                }
            }
        }
    }

    if (RTEST(dst_enc) && !NIL_P(sys_enc)) {
        for(idx = 0; idx < RARRAY(dst)->len; idx++) {
            str_val = RARRAY(dst)->ptr[idx];
            if (rb_obj_respond_to(self, ID_toUTF8, Qtrue)) {
                str_val = rb_funcall(self, ID_toUTF8, 1, str_val);
            } else {
                str_val = rb_funcall(cTclTkLib, ID_toUTF8, 1, str_val);
            }
            RARRAY(dst)->ptr[idx] = str_val;
        }
        val = rb_apply(cTclTkLib, ID_merge_tklist, dst);
        if (TYPE(dst_enc) == T_STRING) {
            val = rb_funcall(cTclTkLib, ID_fromUTF8, 2, val, dst_enc);
            rb_ivar_set(val, ID_at_enc, dst_enc);
        } else {
            rb_ivar_set(val, ID_at_enc, rb_str_new2("utf-8"));
        }
        return val;
    } else {
        return rb_apply(cTclTkLib, ID_merge_tklist, dst);
    }
}

static VALUE
key2keyname(key)
    VALUE key;
{
    return rb_str_append(rb_str_new2("-"), rb_funcall(key, ID_to_s, 0, 0));
}

static VALUE
assoc2kv(assoc, ary, self)
    VALUE assoc;
    VALUE ary;
    VALUE self;
{
    int i, j, len;
    volatile VALUE pair;
    volatile VALUE val;
    volatile VALUE dst = rb_ary_new2(2 * RARRAY(assoc)->len);

    len = RARRAY(assoc)->len;

    for(i = 0; i < len; i++) {
        pair = RARRAY(assoc)->ptr[i];
        if (TYPE(pair) != T_ARRAY) {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = key2keyname(pair);
            continue;
        }
        switch(RARRAY(assoc)->len) {
        case 2:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = RARRAY(pair)->ptr[2];

        case 1:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = key2keyname(RARRAY(pair)->ptr[0]);

        case 0:
            continue;

        default:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = key2keyname(RARRAY(pair)->ptr[0]);

            val = rb_ary_new2(RARRAY(pair)->len - 1);
            RARRAY(val)->len = 0;
            for(j = 1; j < RARRAY(pair)->len; j++) {
                RARRAY(val)->ptr[RARRAY(val)->len++] = RARRAY(pair)->ptr[j];
            }

            RARRAY(dst)->ptr[RARRAY(dst)->len++] = val;
        }
    }

    if (NIL_P(ary)) {
        return dst;
    } else {
        return rb_ary_plus(ary, dst);
    }
}

static VALUE
assoc2kv_enc(assoc, ary, self)
    VALUE assoc;
    VALUE ary;
    VALUE self;
{
    int i, j, len;
    volatile VALUE pair;
    volatile VALUE val;
    volatile VALUE dst = rb_ary_new2(2 * RARRAY(assoc)->len);

    len = RARRAY(assoc)->len;

    for(i = 0; i < len; i++) {
        pair = RARRAY(assoc)->ptr[i];
        if (TYPE(pair) != T_ARRAY) {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = key2keyname(pair);
            continue;
        }
        switch(RARRAY(assoc)->len) {
        case 2:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = get_eval_string_core(RARRAY(pair)->ptr[2], Qtrue, self);

        case 1:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = key2keyname(RARRAY(pair)->ptr[0]);

        case 0:
            continue;

        default:
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = key2keyname(RARRAY(pair)->ptr[0]);

            val = rb_ary_new2(RARRAY(pair)->len - 1);
            RARRAY(val)->len = 0;
            for(j = 1; j < RARRAY(pair)->len; j++) {
                RARRAY(val)->ptr[RARRAY(val)->len++] = RARRAY(pair)->ptr[j];
            }

            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = get_eval_string_core(val, Qtrue, self);
        }
    }

    if (NIL_P(ary)) {
        return dst;
    } else {
        return rb_ary_plus(ary, dst);
    }
}

static int
push_kv(key, val, args)
    VALUE key;
    VALUE val;
    VALUE args;
{
    volatile VALUE ary;

    ary = RARRAY(args)->ptr[0];

    if (key == Qundef) return ST_CONTINUE;
#if 0
    rb_ary_push(ary, key2keyname(key));
    if (val != TK_None) rb_ary_push(ary, val);
#endif
    RARRAY(ary)->ptr[RARRAY(ary)->len++] = key2keyname(key);

    if (val == TK_None) return ST_CHECK;

    RARRAY(ary)->ptr[RARRAY(ary)->len++]
        = get_eval_string_core(val, Qnil, RARRAY(args)->ptr[1]);

    return ST_CHECK;
}

static VALUE
hash2kv(hash, ary, self)
    VALUE hash;
    VALUE ary;
    VALUE self;
{
    volatile VALUE args = rb_ary_new2(2);
    volatile VALUE dst = rb_ary_new2(2 * RHASH(hash)->tbl->num_entries);

    RARRAY(dst)->len = 0;

    RARRAY(args)->ptr[0] = dst;
    RARRAY(args)->ptr[1] = self;
    RARRAY(args)->len = 2;
    st_foreach(RHASH(hash)->tbl, push_kv, args);

    if (NIL_P(ary)) {
        return dst;
    } else {
        return rb_ary_concat(ary, dst);
    }
}

static int
push_kv_enc(key, val, args)
    VALUE key;
    VALUE val;
    VALUE args;
{
    volatile VALUE ary;

    ary = RARRAY(args)->ptr[0];

    if (key == Qundef) return ST_CONTINUE;
#if 0
    rb_ary_push(ary, key2keyname(key));
    if (val != TK_None) {
        rb_ary_push(ary, get_eval_string_core(val, Qtrue, 
                                              RARRAY(args)->ptr[1]));
    }
#endif
    RARRAY(ary)->ptr[RARRAY(ary)->len++] = key2keyname(key);

    if (val == TK_None) return ST_CHECK;

    RARRAY(ary)->ptr[RARRAY(ary)->len++] 
        = get_eval_string_core(val, Qtrue, RARRAY(args)->ptr[1]);

    return ST_CHECK;
}

static VALUE
hash2kv_enc(hash, ary, self)
    VALUE hash;
    VALUE ary;
    VALUE self;
{
    volatile VALUE args = rb_ary_new2(2);
    volatile VALUE dst = rb_ary_new2(2 * RHASH(hash)->tbl->num_entries);

    RARRAY(dst)->len = 0;

    RARRAY(args)->ptr[0] = dst;
    RARRAY(args)->ptr[1] = self;
    RARRAY(args)->len = 2;
    st_foreach(RHASH(hash)->tbl, push_kv_enc, args);

    if (NIL_P(ary)) {
        return dst;
    } else {
        return rb_ary_concat(ary, dst);
    }
}

static VALUE
hash2list(hash, self)
    VALUE hash;
    VALUE self;
{
    return ary2list2(hash2kv(hash, Qnil, self), Qfalse, self);
}


static VALUE
hash2list_enc(hash, self)
    VALUE hash;
    VALUE self;
{
    return ary2list2(hash2kv_enc(hash, Qnil, self), Qfalse, self);
}

static VALUE
tk_hash_kv(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    volatile VALUE hash, enc_flag, ary;

    ary = Qnil;
    enc_flag = Qnil;
    switch(argc) {
    case 3:
        ary = argv[2];
    case 2:
        enc_flag = argv[1];
    case 1:
        hash = argv[0];
        break;
    case 0:
        rb_raise(rb_eArgError, "too few arguments");
    default: /* >= 3 */
        rb_raise(rb_eArgError, "too many arguments");
    }

    switch(TYPE(hash)) {
    case T_ARRAY:
        if (RTEST(enc_flag)) {
            return assoc2kv_enc(hash, ary, self);
        } else {
            return assoc2kv(hash, ary, self);
        }

    case T_HASH:
        if (RTEST(enc_flag)) {
            return hash2kv_enc(hash, ary, self);
        } else {
            return hash2kv(hash, ary, self);
        }

    case T_NIL:
        if (NIL_P(ary)) {
            return rb_ary_new();
        } else {
            return ary;
        }

    default:
        if (hash == TK_None) {
            if (NIL_P(ary)) {
                return rb_ary_new();
            } else {
                return ary;
            }
        }
        rb_raise(rb_eArgError, "Hash is expected for 1st argument");
    }
}

static VALUE
get_eval_string_core(obj, enc_flag, self)
    VALUE obj;
    VALUE enc_flag;
    VALUE self;
{
    switch(TYPE(obj)) {
    case T_FLOAT:
    case T_FIXNUM:
    case T_BIGNUM:
        return rb_funcall(obj, ID_to_s, 0, 0);

    case T_STRING:
        if (RTEST(enc_flag)) {
            if (rb_obj_respond_to(self, ID_toUTF8, Qtrue)) {
                return rb_funcall(self, ID_toUTF8, 1, obj);
            } else {
                return fromDefaultEnc_toUTF8(obj, self);
            }
        } else {
            return obj;
        }

    case T_SYMBOL:
        if (RTEST(enc_flag)) {
            if (rb_obj_respond_to(self, ID_toUTF8, Qtrue)) {
                return rb_funcall(self, ID_toUTF8, 1, 
                                  rb_str_new2(rb_id2name(SYM2ID(obj))));
            } else {
                return fromDefaultEnc_toUTF8(rb_str_new2(rb_id2name(SYM2ID(obj))), self);
            }
        } else {
            return rb_str_new2(rb_id2name(SYM2ID(obj)));
        }

    case T_HASH:
        if (RTEST(enc_flag)) {
            return hash2list_enc(obj, self);
        } else {
            return hash2list(obj, self);
        }

    case T_ARRAY:
        return ary2list(obj, enc_flag, self);

    case T_FALSE:
        return rb_str_new2("0");

    case T_TRUE:
        return rb_str_new2("1");

    case T_NIL:
        return rb_str_new2("");

    case T_REGEXP:
        return rb_funcall(obj, ID_source, 0, 0);

    default:
        if (rb_obj_is_kind_of(obj, cTkObject)) {
            /* return rb_str_new3(rb_funcall(obj, ID_path, 0, 0)); */
            return get_eval_string_core(rb_funcall(obj, ID_path, 0, 0), 
                                        enc_flag, self);
        }

        if (rb_obj_is_kind_of(obj, rb_cProc)
            || rb_obj_is_kind_of(obj, cMethod)
            || rb_obj_is_kind_of(obj, cTkCallbackEntry)) {
            if (rb_obj_respond_to(self, ID_install_cmd, Qtrue)) {
                return rb_funcall(self, ID_install_cmd, 1, obj);
            } else {
                return tk_install_cmd_core(obj);
            }
        }

        if (obj == TK_None)  return Qnil;

        if (rb_obj_respond_to(obj, ID_to_eval, Qtrue)) {
            /* return rb_funcall(obj, ID_to_eval, 0, 0); */
            return get_eval_string_core(rb_funcall(obj, ID_to_eval, 0, 0), 
                                        enc_flag, self);
        } else if (rb_obj_respond_to(obj, ID_path, Qtrue)) {
            /* return rb_funcall(obj, ID_path, 0, 0); */
            return get_eval_string_core(rb_funcall(obj, ID_path, 0, 0), 
                                        enc_flag, self);
        } else if (rb_obj_respond_to(obj, ID_to_s, Qtrue)) {
            return rb_funcall(obj, ID_to_s, 0, 0);
        }
    }

    rb_warning("fail to convert '%s' to string for Tk", 
               RSTRING(rb_funcall(obj, rb_intern("inspect"), 0, 0))->ptr);

    return obj;
}

static VALUE
tk_get_eval_string(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    volatile VALUE obj, enc_flag;

    if (rb_scan_args(argc, argv, "11", &obj, &enc_flag) == 1) {
        enc_flag = Qnil;
    }

    return get_eval_string_core(obj, enc_flag, self);
}

static VALUE
tk_get_eval_enc_str(self, obj)
    VALUE self;
    VALUE obj;
{
    if (obj == TK_None) {
        return obj;
    } else {
        return get_eval_string_core(obj, Qtrue, self);
    }
}

static VALUE
tk_conv_args(argc, argv, self)
    int   argc;
    VALUE *argv; /* [0]:base_array, [1]:enc_mode, [2]..[n]:args */
    VALUE self;
{
    int idx, size;
    volatile VALUE dst;
    int thr_crit_bup;
    VALUE old_gc;

    if (argc < 2) {
      rb_raise(rb_eArgError, "too few arguments");
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;
    old_gc = rb_gc_disable();

    for(size = 0, idx = 2; idx < argc; idx++) {
        if (TYPE(argv[idx]) == T_HASH) {
            size += 2 * RHASH(argv[idx])->tbl->num_entries;
        } else {
            size++;
        }
    }
    /* dst = rb_ary_new2(argc - 2); */
    dst = rb_ary_new2(size);
    RARRAY(dst)->len = 0;
    for(idx = 2; idx < argc; idx++) {
        if (TYPE(argv[idx]) == T_HASH) {
            if (RTEST(argv[1])) {
                hash2kv_enc(argv[idx], dst, self);
            } else {
                hash2kv(argv[idx], dst, self);
            }
        } else if (argv[idx] != TK_None) {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = get_eval_string_core(argv[idx], argv[1], self);
        }
    }

    if (old_gc == Qfalse) rb_gc_enable();
    rb_thread_critical = thr_crit_bup;

    return rb_ary_plus(argv[0], dst);
}


/*************************************/

static VALUE
tcl2rb_bool(self, value)
    VALUE self;
    VALUE value;
{
    if (TYPE(value) == T_FIXNUM) {
        if (NUM2INT(value) == 0) {
            return Qfalse;
        } else {
            return Qtrue;
        }
    }

    if (TYPE(value) == T_TRUE || TYPE(value) == T_FALSE) {
        return value;
    }

    rb_check_type(value, T_STRING);

    value = rb_funcall(value, ID_downcase, 0);

    if (RSTRING(value)->ptr == (char*)NULL) return Qnil;

    if (RSTRING(value)->ptr[0] == '\0'
        || strcmp(RSTRING(value)->ptr, "0") == 0
        || strcmp(RSTRING(value)->ptr, "no") == 0
        || strcmp(RSTRING(value)->ptr, "off") == 0
        || strcmp(RSTRING(value)->ptr, "false") == 0) {
        return Qfalse;
    } else {
        return Qtrue;
    }
}

static VALUE
tkstr_to_dec(value)
    VALUE value;
{
    return rb_cstr_to_inum(RSTRING(value)->ptr, 10, 1);
}

static VALUE
tkstr_to_int(value)
    VALUE value;
{
    return rb_cstr_to_inum(RSTRING(value)->ptr, 0, 1);
}

static VALUE
tkstr_to_float(value)
    VALUE value;
{
    return rb_float_new(rb_cstr_to_dbl(RSTRING(value)->ptr, 1));
}

static VALUE
tkstr_invalid_numstr(value)
    VALUE value;
{
    rb_raise(rb_eArgError, 
             "invalid value for Number: '%s'", RSTRING(value)->ptr);
    return Qnil; /*dummy*/
}

static VALUE
tkstr_rescue_float(value)
    VALUE value;
{
    return rb_rescue2(tkstr_to_float, value, 
                      tkstr_invalid_numstr, value, 
                      rb_eArgError, 0);
}

static VALUE
tkstr_to_number(value)
    VALUE value;
{
    rb_check_type(value, T_STRING);

    if (RSTRING(value)->ptr == (char*)NULL) return INT2FIX(0);

    return rb_rescue2(tkstr_to_int, value, 
                      tkstr_rescue_float, value, 
                      rb_eArgError, 0);
}

static VALUE
tcl2rb_number(self, value)
    VALUE self;
    VALUE value;
{
    return tkstr_to_number(value);
}

static VALUE
tkstr_to_str(value)
    VALUE value;
{
    char * ptr;
    int len;

    ptr = RSTRING(value)->ptr;
    len = RSTRING(value)->len;

    if (len > 1 && *ptr == '{' && *(ptr + len - 1) == '}') {
        return rb_str_new(ptr + 1, len - 2);
    }
    return value;
}

static VALUE
tcl2rb_string(self, value)
    VALUE self;
    VALUE value;
{
    rb_check_type(value, T_STRING);

    if (RSTRING(value)->ptr == (char*)NULL) return rb_tainted_str_new2("");

    return tkstr_to_str(value);
}

static VALUE
tcl2rb_num_or_str(self, value)
    VALUE self;
    VALUE value;
{
    rb_check_type(value, T_STRING);

    if (RSTRING(value)->ptr == (char*)NULL) return rb_tainted_str_new2("");

    return rb_rescue2(tkstr_to_number, value, 
                      tkstr_to_str, value, 
                      rb_eArgError, 0);
}


/*************************************/

struct cbsubst_info {
    int   size;
    char  *key;
    char  *type;
    ID    *ivar;
    VALUE proc;
    VALUE aliases;
};

static void
subst_mark(ptr)
    struct cbsubst_info *ptr;
{
    rb_gc_mark(ptr->proc);
    rb_gc_mark(ptr->aliases);
}

static void
subst_free(ptr)
    struct cbsubst_info *ptr;
{
    if (ptr) {
        if (ptr->key != (char*)NULL) free(ptr->key);
        if (ptr->type != (char*)NULL) free(ptr->type);
        if (ptr->ivar != (ID*)NULL) free(ptr->ivar);
        free(ptr);
    }
}

static void
cbsubst_init()
{
    struct cbsubst_info *inf;
    ID *ivar;
    volatile VALUE proc, aliases;

    inf = ALLOC(struct cbsubst_info);

    inf->size = 0;

    inf->key = ALLOC_N(char, 1);
    inf->key[0] = '\0';

    inf->type = ALLOC_N(char, 1);
    inf->type[0] = '\0';

    ivar = ALLOC_N(ID, 1);
    inf->ivar = ivar;

    proc = rb_hash_new();
    inf->proc = proc;

    aliases = rb_hash_new();
    inf->aliases = aliases;

    rb_const_set(cCB_SUBST, ID_SUBST_INFO, 
                 Data_Wrap_Struct(cSUBST_INFO, subst_mark, subst_free, inf));
}

static VALUE
cbsubst_initialize(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct cbsubst_info *inf;
    int idx;

    Data_Get_Struct(rb_const_get(rb_obj_class(self), ID_SUBST_INFO), 
                    struct cbsubst_info, inf);

    for(idx = 0; idx < argc; idx++) {
        rb_ivar_set(self, inf->ivar[idx], argv[idx]);
    }

    return self;
}


static VALUE
cbsubst_ret_val(self, val)
    VALUE self;
    VALUE val;
{
    return val;
}

static int
each_attr_def(key, value, klass)
    VALUE key, value, klass;
{
    ID key_id, value_id;

    if (key == Qundef) return ST_CONTINUE;

    switch(TYPE(key)) {
    case T_STRING:
        key_id = rb_intern(RSTRING(key)->ptr);
        break;
    case T_SYMBOL:
        key_id = SYM2ID(key);
        break;
    default:
        rb_raise(rb_eArgError, 
                 "includes invalid key(s). expected a String or a Symbol");
    }

    switch(TYPE(value)) {
    case T_STRING:
        value_id = rb_intern(RSTRING(value)->ptr);
        break;
    case T_SYMBOL:
        value_id = SYM2ID(value);
        break;
    default:
        rb_raise(rb_eArgError, 
                 "includes invalid value(s). expected a String or a Symbol");
    }

    rb_alias(klass, key_id, value_id);

    return ST_CONTINUE;
}

static VALUE
cbsubst_def_attr_aliases(self, tbl)
    VALUE self;
    VALUE tbl;
{
    struct cbsubst_info *inf;

    if (TYPE(tbl) != T_HASH) {
        rb_raise(rb_eArgError, "expected a Hash");
    }

    Data_Get_Struct(rb_const_get(self, ID_SUBST_INFO), 
                    struct cbsubst_info, inf);

    rb_hash_foreach(tbl, each_attr_def, self);

    return rb_funcall(inf->aliases, rb_intern("update"), 1, tbl);
}

static VALUE
cbsubst_get_subst_arg(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct cbsubst_info *inf;
    char *str, *buf, *ptr;
    int i, j, len;
    ID id;
    volatile VALUE arg_sym, ret;

    Data_Get_Struct(rb_const_get(self, ID_SUBST_INFO), 
                    struct cbsubst_info, inf);

    buf = ALLOC_N(char, 3*argc + 1);
    ptr = buf;
    len = strlen(inf->key);

    for(i = 0; i < argc; i++) {
        switch(TYPE(argv[i])) {
        case T_STRING:
            str = RSTRING(argv[i])->ptr;
            arg_sym = ID2SYM(rb_intern(str));
            break;
        case T_SYMBOL:
            arg_sym = argv[i];
            str = rb_id2name(SYM2ID(arg_sym));
            break;
        default:
            rb_raise(rb_eArgError, "arg #%d is not a String or a Symbol", i);
        }

        if (!NIL_P(ret = rb_hash_aref(inf->aliases, arg_sym))) {
            str = rb_id2name(SYM2ID(ret));
        }

        id = rb_intern(RSTRING(rb_str_cat2(rb_str_new2("@"), str))->ptr);

        for(j = 0; j < len; j++) {
            if (inf->ivar[j] == id) break;
        }

        if (j >= len) {
            rb_raise(rb_eArgError, "cannot find attribute :%s", str);
        }

        *(ptr++) = '%';
        *(ptr++) = *(inf->key + j);
        *(ptr++) = ' ';
    }

    *ptr = '\0';

    ret = rb_str_new2(buf);

    free(buf);

    return ret;
}

static VALUE
cbsubst_get_subst_key(self, str)
    VALUE self;
    VALUE str;
{
    volatile VALUE list;
    volatile VALUE ret;
    int i, len;
    char *buf, *ptr;

    list = rb_funcall(cTclTkLib, ID_split_tklist, 1, str);

    len = RARRAY(list)->len;
    buf = ALLOC_N(char, len + 1);

    for(i = 0; i < len; i++) {
        ptr = RSTRING(RARRAY(list)->ptr[i])->ptr;
        if (*ptr == '%' && *(ptr + 2) == '\0') {
            *(buf + i) = *(ptr + 1);
        } else {
            *(buf + i) = ' ';
        }
    }
    *(buf + len) = '\0';

    ret = rb_str_new2(buf);
    free(buf);
    return ret;
}

static VALUE
cbsubst_get_all_subst_keys(self)
    VALUE self;
{
    struct cbsubst_info *inf;
    char *buf, *ptr;
    int i, len;
    volatile VALUE ret;

    Data_Get_Struct(rb_const_get(self, ID_SUBST_INFO), 
                    struct cbsubst_info, inf);

    len = strlen(inf->key);
    buf = ALLOC_N(char, 3*len + 1);
    ptr = buf;
    for(i = 0; i < len; i++) {
        *(ptr++) = '%';
        *(ptr++) = *(inf->key + i);
        *(ptr++) = ' ';
    }
    *(buf + 3*len) = '\0';

    ret = rb_ary_new3(2, rb_str_new2(inf->key), rb_str_new2(buf));

    free(buf);

    return ret;
}

static VALUE
cbsubst_table_setup(self, key_inf, proc_inf)
    VALUE self;
    VALUE key_inf;
    VALUE proc_inf;
{
    struct cbsubst_info *subst_inf;
    int idx;
    int len = RARRAY(key_inf)->len;
    int real_len = 0;
    char *key = ALLOC_N(char, len + 1);
    char *type = ALLOC_N(char, len + 1);
    ID *ivar = ALLOC_N(ID, len + 1);
    volatile VALUE proc = rb_hash_new();
    volatile VALUE aliases = rb_hash_new();
    volatile VALUE inf;

    /* init */
    subst_inf = ALLOC(struct cbsubst_info);
    /* subst_inf->size = len; */
    subst_inf->key  = key;
    subst_inf->type = type;
    subst_inf->ivar = ivar;
    subst_inf->proc = proc;
    subst_inf->aliases = aliases;

    /*
     * keys : array of [subst, type, ivar]
     *         subst ==> char code 
     *         type  ==> char code 
     *         ivar  ==> symbol
     */
    for(idx = 0; idx < len; idx++) {
        inf = RARRAY(key_inf)->ptr[idx];
        if (TYPE(inf) != T_ARRAY) continue;
        *(key  + real_len) = (char)NUM2INT(RARRAY(inf)->ptr[0]);
        *(type + real_len) = (char)NUM2INT(RARRAY(inf)->ptr[1]);

        *(ivar + real_len) 
            = rb_intern(
                RSTRING(
                  rb_str_cat2(rb_str_new2("@"), 
                              rb_id2name(SYM2ID(RARRAY(inf)->ptr[2])))
                )->ptr
              );

        rb_attr(self, SYM2ID(RARRAY(inf)->ptr[2]), 1, 0, Qtrue);
        real_len++;
    }
    *(key + real_len) = '\0';
    *(type + real_len) = '\0';
    subst_inf->size = real_len;

    /*
     * procs : array of [type, proc]
     *         type  ==> char code 
     *         proc  ==> proc/method/obj (must respond to 'call')
     */
    len = RARRAY(proc_inf)->len;
    for(idx = 0; idx < len; idx++) {
        inf = RARRAY(proc_inf)->ptr[idx];
        if (TYPE(inf) != T_ARRAY) continue;
        rb_hash_aset(proc, RARRAY(inf)->ptr[0], RARRAY(inf)->ptr[1]);
    }

    rb_const_set(self, ID_SUBST_INFO, 
                 Data_Wrap_Struct(cSUBST_INFO, subst_mark, 
                                  subst_free, subst_inf));

    return self;
}

static VALUE
cbsubst_get_extra_args_tbl(self)
    VALUE self;
{
  return rb_ary_new();
}

static VALUE
cbsubst_scan_args(self, arg_key, val_ary)
    VALUE self;
    VALUE arg_key;
    VALUE val_ary;
{
    struct cbsubst_info *inf;
    int idx;
    int len = RARRAY(val_ary)->len;
    char c;
    char *ptr;
    volatile VALUE dst = rb_ary_new2(len);
    volatile VALUE proc;
    int thr_crit_bup;
    VALUE old_gc;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    old_gc = rb_gc_disable();

    Data_Get_Struct(rb_const_get(self, ID_SUBST_INFO), 
                    struct cbsubst_info, inf);

    RARRAY(dst)->len = 0;
    for(idx = 0; idx < len; idx++) {
        if (idx >= RSTRING(arg_key)->len) {
            proc = Qnil;
        } else if (*(RSTRING(arg_key)->ptr + idx) == ' ') {
            proc = Qnil;
        } else {
          ptr = strchr(inf->key, *(RSTRING(arg_key)->ptr + idx));
          if (ptr == (char*)NULL) {
            proc = Qnil;
          } else {
            c = *(inf->type + (ptr - inf->key));
            proc = rb_hash_aref(inf->proc, INT2FIX(c));
          }
        }

        if (NIL_P(proc)) {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] = RARRAY(val_ary)->ptr[idx];
        } else {
            RARRAY(dst)->ptr[RARRAY(dst)->len++] 
                = rb_funcall(proc, ID_call, 1, RARRAY(val_ary)->ptr[idx]);
        }
    }

    if (old_gc == Qfalse) rb_gc_enable();
    rb_thread_critical = thr_crit_bup;

    return dst;
}

static VALUE
cbsubst_inspect(self)
    VALUE self;
{
    return rb_str_new2("CallbackSubst");
}

static VALUE
substinfo_inspect(self)
    VALUE self;
{
    return rb_str_new2("SubstInfo");
}

/*************************************/

static VALUE
tk_cbe_inspect(self)
    VALUE self;
{
    return rb_str_new2("TkCallbackEntry");
}

/*************************************/

static VALUE
tkobj_path(self)
    VALUE self;
{
    return rb_ivar_get(self, ID_at_path);
}

/*************************************/
/* release date */
const char tkutil_release_date[] = TKUTIL_RELEASE_DATE;

void
Init_tkutil()
{
    VALUE cTK = rb_define_class("TkKernel", rb_cObject);
    VALUE mTK = rb_define_module("TkUtil");

    /* --------------------- */

    rb_define_const(mTK, "RELEASE_DATE", 
                    rb_obj_freeze(rb_str_new2(tkutil_release_date)));

    /* --------------------- */
    rb_global_variable(&cMethod);
    cMethod = rb_const_get(rb_cObject, rb_intern("Method"));

    ID_path = rb_intern("path");
    ID_at_path = rb_intern("@path");
    ID_at_enc = rb_intern("@encoding");
    ID_to_eval = rb_intern("to_eval");
    ID_to_s = rb_intern("to_s");
    ID_source = rb_intern("source");
    ID_downcase = rb_intern("downcase");
    ID_install_cmd = rb_intern("install_cmd");
    ID_merge_tklist = rb_intern("_merge_tklist");
    ID_encoding = rb_intern("encoding");
    ID_encoding_system = rb_intern("encoding_system");
    ID_call = rb_intern("call");

    /* --------------------- */
    cCB_SUBST = rb_define_class_under(mTK, "CallbackSubst", rb_cObject);
    rb_define_singleton_method(cCB_SUBST, "inspect", cbsubst_inspect, 0);

    cSUBST_INFO = rb_define_class_under(cCB_SUBST, "Info", rb_cObject);
    rb_define_singleton_method(cSUBST_INFO, "inspect", substinfo_inspect, 0);

    ID_SUBST_INFO = rb_intern("SUBST_INFO");
    rb_define_singleton_method(cCB_SUBST, "ret_val", cbsubst_ret_val, 1);
    rb_define_singleton_method(cCB_SUBST, "scan_args", cbsubst_scan_args, 2);
    rb_define_singleton_method(cCB_SUBST, "subst_arg", 
                               cbsubst_get_subst_arg, -1);
    rb_define_singleton_method(cCB_SUBST, "_get_subst_key", 
                               cbsubst_get_subst_key,  1);
    rb_define_singleton_method(cCB_SUBST, "_get_all_subst_keys", 
                               cbsubst_get_all_subst_keys,  0);
    rb_define_singleton_method(cCB_SUBST, "_setup_subst_table", 
                               cbsubst_table_setup, 2);
    rb_define_singleton_method(cCB_SUBST, "_get_extra_args_tbl", 
                               cbsubst_get_extra_args_tbl,  0);
    rb_define_singleton_method(cCB_SUBST, "_define_attribute_aliases", 
                               cbsubst_def_attr_aliases,  1);

    rb_define_method(cCB_SUBST, "initialize", cbsubst_initialize, -1);

    cbsubst_init();

    /* --------------------- */
    rb_global_variable(&cTkCallbackEntry);
    cTkCallbackEntry = rb_define_class("TkCallbackEntry", cTK);
    rb_define_singleton_method(cTkCallbackEntry, "inspect", tk_cbe_inspect, 0);

    /* --------------------- */
    rb_global_variable(&cTkObject);
    cTkObject = rb_define_class("TkObject", cTK);
    rb_define_method(cTkObject, "path", tkobj_path, 0);

    /* --------------------- */
    rb_require("tcltklib");
    rb_global_variable(&cTclTkLib);
    cTclTkLib = rb_const_get(rb_cObject, rb_intern("TclTkLib"));
    ID_split_tklist = rb_intern("_split_tklist");
    ID_toUTF8 = rb_intern("_toUTF8");
    ID_fromUTF8 = rb_intern("_fromUTF8");

    /* --------------------- */
    rb_define_singleton_method(cTK, "new", tk_s_new, -1);

    /* --------------------- */
    rb_global_variable(&TK_None);
    TK_None = rb_obj_alloc(rb_cObject);
    rb_define_const(mTK, "None", TK_None);
    rb_define_singleton_method(TK_None, "to_s", tkNone_to_s, 0);
    rb_define_singleton_method(TK_None, "inspect", tkNone_to_s, 0);
    OBJ_FREEZE(TK_None);

    /* --------------------- */
    rb_global_variable(&CALLBACK_TABLE);
    CALLBACK_TABLE = rb_hash_new();

    /* --------------------- */
    rb_define_singleton_method(mTK, "eval_cmd", tk_eval_cmd, -1);
    rb_define_singleton_method(mTK, "callback", tk_do_callback, -1);
    rb_define_singleton_method(mTK, "install_cmd", tk_install_cmd, -1);
    rb_define_singleton_method(mTK, "uninstall_cmd", tk_uninstall_cmd, 1);
    rb_define_singleton_method(mTK, "_symbolkey2str", tk_symbolkey2str, 1);
    rb_define_singleton_method(mTK, "hash_kv", tk_hash_kv, -1);
    rb_define_singleton_method(mTK, "_get_eval_string", 
                               tk_get_eval_string, -1);
    rb_define_singleton_method(mTK, "_get_eval_enc_str", 
                               tk_get_eval_enc_str, 1);
    rb_define_singleton_method(mTK, "_conv_args", tk_conv_args, -1);

    rb_define_singleton_method(mTK, "bool", tcl2rb_bool, 1);
    rb_define_singleton_method(mTK, "number", tcl2rb_number, 1);
    rb_define_singleton_method(mTK, "string", tcl2rb_string, 1);
    rb_define_singleton_method(mTK, "num_or_str", tcl2rb_num_or_str, 1);

    rb_define_method(mTK, "_toUTF8", tk_toUTF8, -1);
    rb_define_method(mTK, "_fromUTF8", tk_fromUTF8, -1);
    rb_define_method(mTK, "_symbolkey2str", tk_symbolkey2str, 1);
    rb_define_method(mTK, "hash_kv", tk_hash_kv, -1);
    rb_define_method(mTK, "_get_eval_string", tk_get_eval_string, -1);
    rb_define_method(mTK, "_get_eval_enc_str", tk_get_eval_enc_str, 1);
    rb_define_method(mTK, "_conv_args", tk_conv_args, -1);

    rb_define_method(mTK, "bool", tcl2rb_bool, 1);
    rb_define_method(mTK, "number", tcl2rb_number, 1);
    rb_define_method(mTK, "string", tcl2rb_string, 1);
    rb_define_method(mTK, "num_or_str", tcl2rb_num_or_str, 1);

    /* --------------------- */
}
