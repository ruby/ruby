/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#define WrapConfig(klass, obj, conf) do { \
    if (!conf) { \
	ossl_raise(rb_eRuntimeError, "Config wasn't intitialized!"); \
    } \
    obj = Data_Wrap_Struct(klass, 0, NCONF_free, conf); \
} while (0)

#define GetConfig(obj, conf) do { \
    Data_Get_Struct(obj, CONF, conf); \
    if (!conf) { \
	ossl_raise(rb_eRuntimeError, "Config wasn't intitialized!"); \
    } \
} while (0)

/*
 * Classes
 */
VALUE cConfig;
VALUE eConfigError;

/* 
 * Public 
 */

/*
 * Private
 */
static VALUE
ossl_config_s_load(int argc, VALUE *argv, VALUE klass)
{
    CONF *conf;
    long err_line = -1;
    char *filename;
    VALUE path, obj;

    if (rb_scan_args(argc, argv, "01", &path) == 1) {
	SafeStringValue(path);
	filename = BUF_strdup(RSTRING(path)->ptr);
    }
    else {
	if (!(filename = CONF_get1_default_config_file())) {
	    ossl_raise(eConfigError, NULL);
	}
    }
    if (!(conf = NCONF_new(NULL))) {
	OPENSSL_free(filename);
	ossl_raise(eConfigError, NULL);
    }
    OSSL_Debug("Loading file: %s", filename);

    if (!NCONF_load(conf, filename, &err_line)) {
	char tmp[255];

	memcpy(tmp, filename, strlen(filename)>=sizeof(tmp)?sizeof(tmp):strlen(filename));
	tmp[sizeof(tmp)-1] = '\0';
	OPENSSL_free(filename);
	
	if (err_line <= 0) {
	    ossl_raise(eConfigError, "wrong config file (%s)", tmp);
	} else {
	    ossl_raise(eConfigError, "error on line %ld in config file \"%s\"",
		       err_line, tmp);
	}
    }
    OPENSSL_free(filename);
    WrapConfig(klass, obj, conf);
    
    return obj;
}

static VALUE
ossl_config_get_value(int argc, VALUE *argv, VALUE self)
{
    CONF *conf;
    VALUE section, item;
    char *sect = NULL, *str;
	
    GetConfig(self, conf);

    if (rb_scan_args(argc, argv, "11", &section, &item) == 1) {
	item = section;
    } else if (!NIL_P(section)) {
	sect = StringValuePtr(section);
    }
    if (!(str = NCONF_get_string(conf, sect, StringValuePtr(item)))) {
	ossl_raise(eConfigError, NULL);
    }
    return rb_str_new2(str);
}

/*
 * Get all numbers as strings - use str.to_i to convert
 * long number = CONF_get_number(confp->config, sect, StringValuePtr(item));
 */

static VALUE
ossl_config_get_section(VALUE self, VALUE section)
{
    CONF *conf;
    STACK_OF(CONF_VALUE) *sk;
    CONF_VALUE *entry;
    int i, entries;
    VALUE hash;

    GetConfig(self, conf);
	
    if (!(sk = NCONF_get_section(conf, StringValuePtr(section)))) {
	ossl_raise(eConfigError, NULL);
    }
    hash = rb_hash_new();
    
    if ((entries = sk_CONF_VALUE_num(sk)) < 0) {
	OSSL_Debug("# of items in section is < 0?!?");
	return hash;
    }
    for (i=0; i<entries; i++) {
	entry = sk_CONF_VALUE_value(sk, i);		
	rb_hash_aset(hash, rb_str_new2(entry->name), rb_str_new2(entry->value));
    }
    return hash;
}

/*
 * INIT
 */
void
Init_ossl_config()
{
    eConfigError = rb_define_class_under(mOSSL, "ConfigError", eOSSLError);

    cConfig = rb_define_class_under(mOSSL, "Config", rb_cObject);
	
    rb_define_singleton_method(cConfig, "load", ossl_config_s_load, -1);
    rb_define_alias(CLASS_OF(cConfig), "new", "load");

    rb_define_method(cConfig, "value", ossl_config_get_value, -1);
    rb_define_method(cConfig, "section", ossl_config_get_section, 1);
    rb_define_alias(cConfig, "[]", "section");
}

