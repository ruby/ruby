#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE hash_spec_rb_hash(VALUE self, VALUE hash) {
  return rb_hash(hash);
}

VALUE hash_spec_rb_Hash(VALUE self, VALUE val) {
  return rb_Hash(val);
}

VALUE hash_spec_rb_hash_dup(VALUE self, VALUE hash) {
  return rb_hash_dup(hash);
}

VALUE hash_spec_rb_hash_fetch(VALUE self, VALUE hash, VALUE key) {
  return rb_hash_fetch(hash, key);
}

VALUE hash_spec_rb_hash_freeze(VALUE self, VALUE hash) {
  return rb_hash_freeze(hash);
}

VALUE hash_spec_rb_hash_aref(VALUE self, VALUE hash, VALUE key) {
  return rb_hash_aref(hash, key);
}

VALUE hash_spec_rb_hash_aref_nil(VALUE self, VALUE hash, VALUE key) {
  VALUE ret = rb_hash_aref(hash, key);
  return NIL_P(ret) ? Qtrue : Qfalse;
}

VALUE hash_spec_rb_hash_aset(VALUE self, VALUE hash, VALUE key, VALUE val) {
  return rb_hash_aset(hash, key, val);
}

VALUE hash_spec_rb_hash_clear(VALUE self, VALUE hash) {
  return rb_hash_clear(hash);
}

VALUE hash_spec_rb_hash_delete(VALUE self, VALUE hash, VALUE key) {
  return rb_hash_delete(hash, key);
}

VALUE hash_spec_rb_hash_delete_if(VALUE self, VALUE hash) {
  return rb_hash_delete_if(hash);
}

static int foreach_i(VALUE key, VALUE val, VALUE other) {
  rb_hash_aset(other, key, val);
  return 0; /* ST_CONTINUE; */
}

static int foreach_stop_i(VALUE key, VALUE val, VALUE other) {
  rb_hash_aset(other, key, val);
  return 1; /* ST_STOP; */
}

static int foreach_delete_i(VALUE key, VALUE val, VALUE other) {
  rb_hash_aset(other, key, val);
  return 2; /* ST_DELETE; */
}

VALUE hash_spec_rb_hash_foreach(VALUE self, VALUE hsh) {
  VALUE other = rb_hash_new();
  rb_hash_foreach(hsh, foreach_i, other);
  return other;
}

VALUE hash_spec_rb_hash_foreach_stop(VALUE self, VALUE hsh) {
  VALUE other = rb_hash_new();
  rb_hash_foreach(hsh, foreach_stop_i, other);
  return other;
}

VALUE hash_spec_rb_hash_foreach_delete(VALUE self, VALUE hsh) {
  VALUE other = rb_hash_new();
  rb_hash_foreach(hsh, foreach_delete_i, other);
  return other;
}

VALUE hash_spec_rb_hash_lookup(VALUE self, VALUE hash, VALUE key) {
  return rb_hash_lookup(hash, key);
}

VALUE hash_spec_rb_hash_lookup_nil(VALUE self, VALUE hash, VALUE key) {
  VALUE ret = rb_hash_lookup(hash, key);
  return ret == Qnil ? Qtrue : Qfalse;
}

VALUE hash_spec_rb_hash_lookup2(VALUE self, VALUE hash, VALUE key, VALUE def) {
  return rb_hash_lookup2(hash, key, def);
}

VALUE hash_spec_rb_hash_lookup2_default_undef(VALUE self, VALUE hash, VALUE key) {
  VALUE ret = rb_hash_lookup2(hash, key, Qundef);
  return ret == Qundef ? Qtrue : Qfalse;
}

VALUE hash_spec_rb_hash_new(VALUE self) {
  return rb_hash_new();
}

VALUE hash_spec_rb_hash_new_capa(VALUE self, VALUE capacity) {
  return rb_hash_new_capa(NUM2LONG(capacity));
}

VALUE rb_ident_hash_new(void); /* internal.h, used in ripper */

VALUE hash_spec_rb_ident_hash_new(VALUE self) {
  return rb_ident_hash_new();
}

VALUE hash_spec_rb_hash_size(VALUE self, VALUE hash) {
  return rb_hash_size(hash);
}

VALUE hash_spec_rb_hash_set_ifnone(VALUE self, VALUE hash, VALUE def) {
  return rb_hash_set_ifnone(hash, def);
}

VALUE hash_spec_compute_a_hash_code(VALUE self, VALUE seed) {
  int int_seed = FIX2INT(seed);
  st_index_t h = rb_hash_start(int_seed);
  h = rb_hash_uint32(h, 540u);
  h = rb_hash_uint32(h, 340u);
  h = rb_hash_end(h);
  return ULONG2NUM(h);
}

VALUE hash_spec_rb_hash_bulk_insert(VALUE self, VALUE array_len, VALUE array, VALUE hash) {
  VALUE* ptr;

  if (array == Qnil) {
    ptr = NULL;
  } else {
    ptr = RARRAY_PTR(array);
  }

  long len = FIX2LONG(array_len);
  rb_hash_bulk_insert(len, ptr, hash);
  return Qnil;
}

void Init_hash_spec(void) {
  VALUE cls = rb_define_class("CApiHashSpecs", rb_cObject);
  rb_define_method(cls, "rb_hash", hash_spec_rb_hash, 1);
  rb_define_method(cls, "rb_Hash", hash_spec_rb_Hash, 1);
  rb_define_method(cls, "rb_hash_dup", hash_spec_rb_hash_dup, 1);
  rb_define_method(cls, "rb_hash_freeze", hash_spec_rb_hash_freeze, 1);
  rb_define_method(cls, "rb_hash_aref", hash_spec_rb_hash_aref, 2);
  rb_define_method(cls, "rb_hash_aref_nil", hash_spec_rb_hash_aref_nil, 2);
  rb_define_method(cls, "rb_hash_aset", hash_spec_rb_hash_aset, 3);
  rb_define_method(cls, "rb_hash_clear", hash_spec_rb_hash_clear, 1);
  rb_define_method(cls, "rb_hash_delete", hash_spec_rb_hash_delete, 2);
  rb_define_method(cls, "rb_hash_delete_if", hash_spec_rb_hash_delete_if, 1);
  rb_define_method(cls, "rb_hash_fetch", hash_spec_rb_hash_fetch, 2);
  rb_define_method(cls, "rb_hash_foreach", hash_spec_rb_hash_foreach, 1);
  rb_define_method(cls, "rb_hash_foreach_stop", hash_spec_rb_hash_foreach_stop, 1);
  rb_define_method(cls, "rb_hash_foreach_delete", hash_spec_rb_hash_foreach_delete, 1);
  rb_define_method(cls, "rb_hash_lookup_nil", hash_spec_rb_hash_lookup_nil, 2);
  rb_define_method(cls, "rb_hash_lookup", hash_spec_rb_hash_lookup, 2);
  rb_define_method(cls, "rb_hash_lookup2", hash_spec_rb_hash_lookup2, 3);
  rb_define_method(cls, "rb_hash_lookup2_default_undef", hash_spec_rb_hash_lookup2_default_undef, 2);
  rb_define_method(cls, "rb_hash_new", hash_spec_rb_hash_new, 0);
  rb_define_method(cls, "rb_hash_new_capa", hash_spec_rb_hash_new_capa, 1);
  rb_define_method(cls, "rb_ident_hash_new", hash_spec_rb_ident_hash_new, 0);
  rb_define_method(cls, "rb_hash_size", hash_spec_rb_hash_size, 1);
  rb_define_method(cls, "rb_hash_set_ifnone", hash_spec_rb_hash_set_ifnone, 2);
  rb_define_method(cls, "compute_a_hash_code", hash_spec_compute_a_hash_code, 1);
  rb_define_method(cls, "rb_hash_bulk_insert", hash_spec_rb_hash_bulk_insert, 3);
}

#ifdef __cplusplus
}
#endif
