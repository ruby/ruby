/* -*- indent-tabs-mode: nil -*-
/*
 * rubyext.c
 *
 * $Author$
 * $Date$
 *
 * Copyright (C) 2003 why the lucky stiff
 */

#include "ruby.h"
#include "syck.h"
#include <sys/types.h>
#include <time.h>

typedef struct RVALUE {
    union {
#if 0
	struct {
	    unsigned long flags;	/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
#endif
	struct RBasic  basic;
	struct RObject object;
	struct RClass  klass;
	/*struct RFloat  flonum;*/
	/*struct RString string;*/
	struct RArray  array;
	/*struct RRegexp regexp;*/
	struct RHash   hash;
	/*struct RData   data;*/
	struct RStruct rstruct;
	/*struct RBignum bignum;*/
	/*struct RFile   file;*/
    } as;
} RVALUE;

typedef struct {
   long hash;
   char *buffer;
   long length;
   long remaining;
   int  printed;
} bytestring_t;

#define RUBY_DOMAIN   "ruby.yaml.org,2002"

/*
 * symbols and constants
 */
static ID s_new, s_utc, s_at, s_to_f, s_to_i, s_read, s_binmode, s_call, s_cmp, s_transfer, s_update, s_dup, s_match, s_keys, s_to_str, s_unpack, s_tr_bang, s_anchors, s_default_set;
static ID s_anchors, s_domain, s_families, s_kind, s_name, s_options, s_private_types, s_type_id, s_value;
static VALUE sym_model, sym_generic, sym_input, sym_bytecode;
static VALUE sym_scalar, sym_seq, sym_map;
VALUE cDate, cParser, cLoader, cNode, cPrivateType, cDomainType, cBadAlias, cDefaultKey, cMergeKey, cEmitter;
VALUE oDefaultLoader;

/*
 * my private collection of numerical oddities.
 */
static double S_zero()    { return 0.0; }
static double S_one() { return 1.0; }
static double S_inf() { return S_one() / S_zero(); }
static double S_nan() { return S_zero() / S_zero(); }

static VALUE syck_node_transform( VALUE );

/*
 * handler prototypes
 */
SYMID rb_syck_parse_handler _((SyckParser *, SyckNode *));
SYMID rb_syck_load_handler _((SyckParser *, SyckNode *));
void rb_syck_err_handler _((SyckParser *, char *));
SyckNode * rb_syck_bad_anchor_handler _((SyckParser *, char *));
void rb_syck_output_handler _((SyckEmitter *, char *, long));
int syck_parser_assign_io _((SyckParser *, VALUE));

struct parser_xtra {
    VALUE data;  /* Borrowed this idea from marshal.c to fix [ruby-core:8067] problem */
    VALUE proc;
    int taint;
};

/*
 * Convert YAML to bytecode
 */
VALUE
rb_syck_compile(self, port)
	VALUE self, port;
{
    SYMID oid;
    int taint;
    char *ret;
    VALUE bc;
    bytestring_t *sav; 

    SyckParser *parser = syck_new_parser();
	taint = syck_parser_assign_io(parser, port);
    syck_parser_handler( parser, syck_yaml2byte_handler );
    syck_parser_error_handler( parser, NULL );
    syck_parser_implicit_typing( parser, 0 );
    syck_parser_taguri_expansion( parser, 0 );
    oid = syck_parse( parser );
    syck_lookup_sym( parser, oid, (char **)&sav );

    ret = S_ALLOC_N( char, strlen( sav->buffer ) + 3 );
    ret[0] = '\0';
    strcat( ret, "D\n" );
    strcat( ret, sav->buffer );

    syck_free_parser( parser );

    bc = rb_str_new2( ret );
    if ( taint )      OBJ_TAINT( bc );
    return bc;
}

/*
 * read from io.
 */
long
rb_syck_io_str_read( char *buf, SyckIoStr *str, long max_size, long skip )
{
    long len = 0;

    ASSERT( str != NULL );
    max_size -= skip;

    if ( max_size <= 0 ) max_size = 0;
    else
    {
        /*
         * call io#read.
         */
        VALUE src = (VALUE)str->ptr;
        VALUE n = LONG2NUM(max_size);
        VALUE str2 = rb_funcall2(src, s_read, 1, &n);
        if (!NIL_P(str2))
        {
            len = RSTRING(str2)->len;
            memcpy( buf + skip, RSTRING(str2)->ptr, len );
        }
    }
    len += skip;
    buf[len] = '\0';
    return len;
}

/*
 * determine: are we reading from a string or io?
 * (returns tainted? boolean)
 */
int
syck_parser_assign_io(parser, port)
	SyckParser *parser;
	VALUE port;
{
    int taint = Qtrue;
    if (rb_respond_to(port, s_to_str)) {
	    taint = OBJ_TAINTED(port); /* original taintedness */
	    StringValue(port);	       /* possible conversion */
	    syck_parser_str( parser, RSTRING(port)->ptr, RSTRING(port)->len, NULL );
    }
    else if (rb_respond_to(port, s_read)) {
        if (rb_respond_to(port, s_binmode)) {
            rb_funcall2(port, s_binmode, 0, 0);
        }
        syck_parser_str( parser, (char *)port, 0, rb_syck_io_str_read );
    }
    else {
        rb_raise(rb_eTypeError, "instance of IO needed");
    }
    return taint;
}

/*
 * Get value in hash by key, forcing an empty hash if nil.
 */
VALUE
syck_get_hash_aref(hsh, key)
    VALUE hsh, key;
{
   VALUE val = rb_hash_aref( hsh, key );
   if ( NIL_P( val ) ) 
   {
       val = rb_hash_new();
       rb_hash_aset(hsh, key, val);
   }
   return val;
}

/*
 * creating timestamps
 */
SYMID
rb_syck_mktime(str)
    char *str;
{
    VALUE time;
    char *ptr = str;
    VALUE year, mon, day, hour, min, sec;
    long usec;

    /* Year*/
    ptr[4] = '\0';
    year = INT2FIX(strtol(ptr, NULL, 10));

    /* Month*/
    ptr += 4;
    while ( !ISDIGIT( *ptr ) ) ptr++;
    mon = INT2FIX(strtol(ptr, NULL, 10));

    /* Day*/
    ptr += 2;
    while ( !ISDIGIT( *ptr ) ) ptr++;
    day = INT2FIX(strtol(ptr, NULL, 10));

    /* Hour*/
    ptr += 2;
    while ( !ISDIGIT( *ptr ) ) ptr++;
    hour = INT2FIX(strtol(ptr, NULL, 10));

    /* Minute */
    ptr += 2;
    while ( !ISDIGIT( *ptr ) ) ptr++;
    min = INT2FIX(strtol(ptr, NULL, 10));

    /* Second */
    ptr += 2;
    while ( !ISDIGIT( *ptr ) ) ptr++;
    sec = INT2FIX(strtol(ptr, NULL, 10));

    /* Millisecond */
    ptr += 2;
    if ( *ptr == '.' )
    {
        char *padded = syck_strndup( "000000", 6 );
        char *end = ptr + 1;
        while ( isdigit( *end ) ) end++;
        MEMCPY(padded, ptr + 1, char, end - (ptr + 1));
        usec = strtol(padded, NULL, 10);
    }
    else
    {
        usec = 0;
    }

    /* Time Zone*/
    while ( *ptr != 'Z' && *ptr != '+' && *ptr != '-' && *ptr != '\0' ) ptr++;
    if ( *ptr == '-' || *ptr == '+' )
    {
        time_t tz_offset = strtol(ptr, NULL, 10) * 3600;                                                                           
        time_t tmp;

        while ( *ptr != ':' && *ptr != '\0' ) ptr++;
        if ( *ptr == ':' )
        {
            ptr += 1;
            if ( tz_offset < 0 )
            {
                tz_offset -= strtol(ptr, NULL, 10) * 60;
            }
            else
            {
                tz_offset += strtol(ptr, NULL, 10) * 60;
            }
        }

        /* Make TZ time*/
        time = rb_funcall(rb_cTime, s_utc, 6, year, mon, day, hour, min, sec);                                                     
        tmp = NUM2LONG(rb_funcall(time, s_to_i, 0)) - tz_offset;                                                                   
        return rb_funcall(rb_cTime, s_at, 2, LONG2NUM(tmp), LONG2NUM(usec));                                                       
    }                                                                                                                              
    else                                                                                                                           
    {                                                                                                                              
        /* Make UTC time*/                                                                                                         
        return rb_funcall(rb_cTime, s_utc, 7, year, mon, day, hour, min, sec, LONG2NUM(usec));                                     

    }
}

/*
 * {generic mode} node handler
 * - Loads data into Node classes
 */
SYMID
rb_syck_parse_handler(p, n)
    SyckParser *p;
    SyckNode *n;
{
    VALUE t, obj, v = Qnil;
    int i;
    struct parser_xtra *bonus;

    obj = rb_obj_alloc(cNode);
    if ( n->type_id != NULL )
    {
        t = rb_str_new2(n->type_id);
        rb_ivar_set(obj, s_type_id, t);
    }

    switch (n->kind)
    {
        case syck_str_kind:
            rb_ivar_set(obj, s_kind, sym_scalar);
            v = rb_str_new( n->data.str->ptr, n->data.str->len );
        break;

        case syck_seq_kind:
            rb_ivar_set(obj, s_kind, sym_seq);
            v = rb_ary_new2( n->data.list->idx );
            for ( i = 0; i < n->data.list->idx; i++ )
            {
                rb_ary_store( v, i, syck_seq_read( n, i ) );
            }
        break;

        case syck_map_kind:
            rb_ivar_set(obj, s_kind, sym_map);
            v = rb_hash_new();
            for ( i = 0; i < n->data.pairs->idx; i++ )
            {
                VALUE key = syck_node_transform( syck_map_read( n, map_key, i ) );
                VALUE val = rb_ary_new();
                rb_ary_push(val, syck_map_read( n, map_key, i ));
                rb_ary_push(val, syck_map_read( n, map_value, i ));

                rb_hash_aset( v, key, val );
            }
        break;
    }

    bonus = (struct parser_xtra *)p->bonus;
    if ( bonus->taint)      OBJ_TAINT( obj );
	if ( bonus->proc != 0 ) rb_funcall(bonus->proc, s_call, 1, v);

    rb_ivar_set(obj, s_value, v);
    rb_hash_aset(bonus->data, INT2FIX(RHASH(bonus->data)->tbl->num_entries), obj);
    return obj;
}

/*
 * handles merging of an array of hashes
 * (see http://www.yaml.org/type/merge/)
 */
VALUE
syck_merge_i( entry, hsh )
    VALUE entry, hsh;
{
	if ( rb_obj_is_kind_of( entry, rb_cHash ) )
	{
		rb_funcall( hsh, s_update, 1, entry );
	}
    return Qnil;
}

/*
 * build a syck node from a Ruby VALUE
 */
SyckNode *
rb_new_syck_node( obj, type_id )
    VALUE obj, type_id;
{
    long i = 0;
    SyckNode *n = NULL;

    if (rb_respond_to(obj, s_to_str)) 
    {
	    StringValue(obj);	       /* possible conversion */
        n = syck_alloc_str();
        n->data.str->ptr = RSTRING(obj)->ptr;
        n->data.str->len = RSTRING(obj)->len;
    }
	else if ( rb_obj_is_kind_of( obj, rb_cArray ) )
    {
        n = syck_alloc_seq();
        for ( i = 0; i < RARRAY(obj)->len; i++ )
        {
            syck_seq_add(n, rb_ary_entry(obj, i));
        }
    }
    else if ( rb_obj_is_kind_of( obj, rb_cHash ) )
    {
        VALUE keys;
        n = syck_alloc_map();
        keys = rb_funcall( obj, s_keys, 0 );
        for ( i = 0; i < RARRAY(keys)->len; i++ )
        {
            VALUE key = rb_ary_entry(keys, i);
            syck_map_add(n, key, rb_hash_aref(obj, key));
        }
    }

    if ( n!= NULL && rb_respond_to( type_id, s_to_str ) ) 
    {
        StringValue(type_id);
        n->type_id = syck_strndup( RSTRING(type_id)->ptr, RSTRING(type_id)->len );
    }

    return n;
}

/*
 * default handler for ruby.yaml.org types
 */
int
yaml_org_handler( n, ref )
    SyckNode *n;
    VALUE *ref;
{
    char *type_id = n->type_id;
    int transferred = 0;
    long i = 0;
    VALUE obj = Qnil;

    switch (n->kind)
    {
        case syck_str_kind:
            transferred = 1;
            if ( type_id == NULL )
            {
                obj = rb_str_new( n->data.str->ptr, n->data.str->len );
            }
            else if ( strcmp( type_id, "null" ) == 0 )
            {
                obj = Qnil;
            }
            else if ( strcmp( type_id, "binary" ) == 0 )
            {
                VALUE arr;
                obj = rb_str_new( n->data.str->ptr, n->data.str->len );
                rb_funcall( obj, s_tr_bang, 2, rb_str_new2( "\n\t " ), rb_str_new2( "" ) );
                arr = rb_funcall( obj, s_unpack, 1, rb_str_new2( "m" ) );
                obj = rb_ary_shift( arr );
            }
            else if ( strcmp( type_id, "bool#yes" ) == 0 )
            {
                obj = Qtrue;
            }
            else if ( strcmp( type_id, "bool#no" ) == 0 )
            {
                obj = Qfalse;
            }
            else if ( strcmp( type_id, "int#hex" ) == 0 )
            {
                syck_str_blow_away_commas( n );
                obj = rb_cstr2inum( n->data.str->ptr, 16 );
            }
            else if ( strcmp( type_id, "int#oct" ) == 0 )
            {
                syck_str_blow_away_commas( n );
                obj = rb_cstr2inum( n->data.str->ptr, 8 );
            }
            else if ( strcmp( type_id, "int#base60" ) == 0 )
            {
                char *ptr, *end;
                long sixty = 1;
                long total = 0;
                syck_str_blow_away_commas( n );
                ptr = n->data.str->ptr;
                end = n->data.str->ptr + n->data.str->len;
                while ( end > ptr )
                {
                    long bnum = 0;
                    char *colon = end - 1;
                    while ( colon >= ptr && *colon != ':' )
                    {
                        colon--;
                    }
                    if ( *colon == ':' ) *colon = '\0';

                    bnum = strtol( colon + 1, NULL, 10 );
                    total += bnum * sixty;
                    sixty *= 60;
                    end = colon;
                }
                obj = INT2FIX(total);
            }
            else if ( strncmp( type_id, "int", 3 ) == 0 )
            {
                syck_str_blow_away_commas( n );
                obj = rb_cstr2inum( n->data.str->ptr, 10 );
            }
            else if ( strcmp( type_id, "float#nan" ) == 0 )
            {
                obj = rb_float_new( S_nan() );
            }
            else if ( strcmp( type_id, "float#inf" ) == 0 )
            {
                obj = rb_float_new( S_inf() );
            }
            else if ( strcmp( type_id, "float#neginf" ) == 0 )
            {
                obj = rb_float_new( -S_inf() );
            }
            else if ( strncmp( type_id, "float", 5 ) == 0 )
            {
                double f;
                syck_str_blow_away_commas( n );
                f = strtod( n->data.str->ptr, NULL );
                obj = rb_float_new( f );
            }
            else if ( strcmp( type_id, "timestamp#iso8601" ) == 0 )
            {
                obj = rb_syck_mktime( n->data.str->ptr );
            }
            else if ( strcmp( type_id, "timestamp#spaced" ) == 0 )
            {
                obj = rb_syck_mktime( n->data.str->ptr );
            }
            else if ( strcmp( type_id, "timestamp#ymd" ) == 0 )
            {
                char *ptr = n->data.str->ptr;
                VALUE year, mon, day;

                /* Year*/
                ptr[4] = '\0';
                year = INT2FIX(strtol(ptr, NULL, 10));

                /* Month*/
                ptr += 4;
                while ( !ISDIGIT( *ptr ) ) ptr++;
                mon = INT2FIX(strtol(ptr, NULL, 10));

                /* Day*/
                ptr += 2;
                while ( !ISDIGIT( *ptr ) ) ptr++;
                day = INT2FIX(strtol(ptr, NULL, 10));

                if ( !cDate ) {
                    /*
                     * Load Date module
                     */
                    rb_require( "date" );
                    cDate = rb_const_get( rb_cObject, rb_intern("Date") );
                }

                obj = rb_funcall( cDate, s_new, 3, year, mon, day );
            }
            else if ( strncmp( type_id, "timestamp", 9 ) == 0 )
            {
                obj = rb_syck_mktime( n->data.str->ptr );
            }
			else if ( strncmp( type_id, "merge", 5 ) == 0 )
			{
				obj = rb_funcall( cMergeKey, s_new, 0 );
			}
			else if ( strncmp( type_id, "default", 7 ) == 0 )
			{
				obj = rb_funcall( cDefaultKey, s_new, 0 );
			}
            else if ( n->data.str->style == scalar_plain &&
                      n->data.str->len > 1 && 
                      strncmp( n->data.str->ptr, ":", 1 ) == 0 )
            {
                obj = rb_funcall( oDefaultLoader, s_transfer, 2, 
                                  rb_str_new2( "ruby/sym" ), 
                                  rb_str_new( n->data.str->ptr + 1, n->data.str->len - 1 ) );
            }
            else if ( strcmp( type_id, "str" ) == 0 )
            {
                obj = rb_str_new( n->data.str->ptr, n->data.str->len );
            }
            else
            {
                transferred = 0;
                obj = rb_str_new( n->data.str->ptr, n->data.str->len );
            }
        break;

        case syck_seq_kind:
            if ( type_id == NULL || strcmp( type_id, "seq" ) == 0 )
            {
                transferred = 1;
            }
            obj = rb_ary_new2( n->data.list->idx );
            for ( i = 0; i < n->data.list->idx; i++ )
            {
                rb_ary_store( obj, i, syck_seq_read( n, i ) );
            }
        break;

        case syck_map_kind:
            if ( type_id == NULL || strcmp( type_id, "map" ) == 0 )
            {
                transferred = 1;
            }
            obj = rb_hash_new();
            for ( i = 0; i < n->data.pairs->idx; i++ )
            {
				VALUE k = syck_map_read( n, map_key, i );
				VALUE v = syck_map_read( n, map_value, i );
				int skip_aset = 0;

				/*
				 * Handle merge keys
				 */
				if ( rb_obj_is_kind_of( k, cMergeKey ) )
				{
					if ( rb_obj_is_kind_of( v, rb_cHash ) )
					{
						VALUE dup = rb_funcall( v, s_dup, 0 );
						rb_funcall( dup, s_update, 1, obj );
						obj = dup;
						skip_aset = 1;
					}
					else if ( rb_obj_is_kind_of( v, rb_cArray ) )
					{
						VALUE end = rb_ary_pop( v );
						if ( rb_obj_is_kind_of( end, rb_cHash ) )
						{
							VALUE dup = rb_funcall( end, s_dup, 0 );
							v = rb_ary_reverse( v );
							rb_ary_push( v, obj );
							rb_iterate( rb_each, v, syck_merge_i, dup );
							obj = dup;
							skip_aset = 1;
						}
					}
				}
                else if ( rb_obj_is_kind_of( k, cDefaultKey ) )
                {
                    rb_funcall( obj, s_default_set, 1, v );
                    skip_aset = 1;
                }

				if ( ! skip_aset )
				{
					rb_hash_aset( obj, k, v );
				}
            }
        break;
    }

    *ref = obj;
    return transferred;
}

/*
 * {native mode} node handler
 * - Converts data into native Ruby types
 */
SYMID
rb_syck_load_handler(p, n)
    SyckParser *p;
    SyckNode *n;
{
    VALUE obj = Qnil;
    struct parser_xtra *bonus;

    /*
     * Attempt common transfers
     */
    int transferred = yaml_org_handler(n, &obj);
    if ( transferred == 0 && n->type_id != NULL )
    {
        obj = rb_funcall( oDefaultLoader, s_transfer, 2, rb_str_new2( n->type_id ), obj );
    }

    /*
     * ID already set, let's alter the symbol table to accept the new object
     */
    if (n->id > 0 && !NIL_P(obj))
    {
        MEMCPY((void *)n->id, (void *)obj, RVALUE, 1);
        MEMZERO((void *)obj, RVALUE, 1);
        obj = n->id;
    }

    bonus = (struct parser_xtra *)p->bonus;
    if ( bonus->taint)      OBJ_TAINT( obj );
	if ( bonus->proc != 0 ) rb_funcall(bonus->proc, s_call, 1, obj);

    rb_hash_aset(bonus->data, INT2FIX(RHASH(bonus->data)->tbl->num_entries), obj);
    return obj;
}

/*
 * friendly errors.
 */
void
rb_syck_err_handler(p, msg)
    SyckParser *p;
    char *msg;
{
    char *endl = p->cursor;

    while ( *endl != '\0' && *endl != '\n' )
        endl++;

    endl[0] = '\0';
    rb_raise(rb_eArgError, "%s on line %d, col %d: `%s'",
           msg,
           p->linect,
           p->cursor - p->lineptr, 
           p->lineptr); 
}

/*
 * provide bad anchor object to the parser.
 */
SyckNode *
rb_syck_bad_anchor_handler(p, a)
    SyckParser *p;
    char *a;
{
    VALUE anchor_name = rb_str_new2( a );
    SyckNode *badanc = syck_new_map( rb_str_new2( "name" ), anchor_name );
    badanc->type_id = syck_strndup( "tag:ruby.yaml.org,2002:object:YAML::Syck::BadAlias", 53 );
    return badanc;
}

/*
 * data loaded based on the model requested.
 */
void
syck_set_model( parser, input, model )
	SyckParser *parser;
	VALUE input, model;
{
	if ( model == sym_generic )
	{
		syck_parser_handler( parser, rb_syck_parse_handler );
		syck_parser_implicit_typing( parser, 1 );
		syck_parser_taguri_expansion( parser, 1 );
	}
	else
	{
		syck_parser_handler( parser, rb_syck_load_handler );
		syck_parser_implicit_typing( parser, 1 );
		syck_parser_taguri_expansion( parser, 0 );
	}
    if ( input == sym_bytecode )
    {
        syck_parser_set_input_type( parser, syck_bytecode_utf8 );
    }
    syck_parser_error_handler( parser, rb_syck_err_handler );
    syck_parser_bad_anchor_handler( parser, rb_syck_bad_anchor_handler );
}

/*
 * mark parser nodes
 */
static void
syck_mark_parser(parser)
    SyckParser *parser;
{
    rb_gc_mark(parser->root);
    rb_gc_mark(parser->root_on_error);
}

/*
 * YAML::Syck::Parser.new
 */
VALUE 
syck_parser_new(argc, argv, class)
    int argc;
    VALUE *argv;
	VALUE class;
{
	VALUE pobj, options, init_argv[1];
    SyckParser *parser = syck_new_parser();

    rb_scan_args(argc, argv, "01", &options);
	pobj = Data_Wrap_Struct( class, syck_mark_parser, syck_free_parser, parser );

    syck_parser_set_root_on_error( parser, Qnil );

    if ( ! rb_obj_is_instance_of( options, rb_cHash ) )
    {
        options = rb_hash_new();
    }
	init_argv[0] = options;
	rb_obj_call_init(pobj, 1, init_argv);
	return pobj;
}

/*
 * YAML::Syck::Parser.initialize( options )
 */
static VALUE
syck_parser_initialize( self, options )
    VALUE self, options;
{
    rb_ivar_set(self, s_options, options);
	return self;
}

/*
 * YAML::Syck::Parser.bufsize = Integer
 */
static VALUE
syck_parser_bufsize_set( self, size )
    VALUE self, size;
{
	SyckParser *parser;

	Data_Get_Struct(self, SyckParser, parser);
    if ( rb_respond_to( size, s_to_i ) ) {
        parser->bufsize = NUM2INT(rb_funcall(size, s_to_i, 0));
    }
	return self;
}

/*
 * YAML::Syck::Parser.bufsize => Integer
 */
static VALUE
syck_parser_bufsize_get( self )
    VALUE self;
{
	SyckParser *parser;

	Data_Get_Struct(self, SyckParser, parser);
	return INT2FIX( parser->bufsize );
}

/*
 * YAML::Syck::Parser.load( IO or String )
 */
VALUE
syck_parser_load(argc, argv, self)
    int argc;
    VALUE *argv;
	VALUE self;
{
    VALUE port, proc, model, input;
	SyckParser *parser;
    struct parser_xtra bonus;
    volatile VALUE hash;	/* protect from GC */

    rb_scan_args(argc, argv, "11", &port, &proc);
	Data_Get_Struct(self, SyckParser, parser);

    input = rb_hash_aref( rb_attr_get( self, s_options ), sym_input );
    model = rb_hash_aref( rb_attr_get( self, s_options ), sym_model );
	syck_set_model( parser, input, model );

	bonus.taint = syck_parser_assign_io(parser, port);
    bonus.data = hash = rb_hash_new();
	if ( NIL_P( proc ) ) bonus.proc = 0;
    else                 bonus.proc = proc;
    
	parser->bonus = (void *)&bonus;

    return syck_parse( parser );
}

/*
 * YAML::Syck::Parser.load_documents( IO or String ) { |doc| }
 */
VALUE
syck_parser_load_documents(argc, argv, self)
    int argc;
    VALUE *argv;
	VALUE self;
{
    VALUE port, proc, v, input, model;
	SyckParser *parser;
    struct parser_xtra bonus;
    volatile VALUE hash;

    rb_scan_args(argc, argv, "1&", &port, &proc);
	Data_Get_Struct(self, SyckParser, parser);

    input = rb_hash_aref( rb_attr_get( self, s_options ), sym_input );
    model = rb_hash_aref( rb_attr_get( self, s_options ), sym_model );
	syck_set_model( parser, input, model );
    
	bonus.taint = syck_parser_assign_io(parser, port);
    while ( 1 )
	{
        /* Reset hash for tracking nodes */
        bonus.data = hash = rb_hash_new();
        bonus.proc = 0;
        parser->bonus = (void *)&bonus;

        /* Parse a document */
    	v = syck_parse( parser );
        if ( parser->eof == 1 )
        {
            break;
        }

        /* Pass document to block */
		rb_funcall( proc, s_call, 1, v );
	}

    return Qnil;
}

/*
 * YAML::Syck::Loader.initialize
 */
static VALUE
syck_loader_initialize( self )
    VALUE self;
{
    VALUE families;

    families = rb_hash_new();
    rb_ivar_set(self, s_families, families);
    rb_ivar_set(self, s_private_types, rb_hash_new());
    rb_ivar_set(self, s_anchors, rb_hash_new());

    rb_hash_aset(families, rb_str_new2( YAML_DOMAIN ), rb_hash_new());
    rb_hash_aset(families, rb_str_new2( RUBY_DOMAIN ), rb_hash_new());

    return self;
}

/*
 * Add type family, used by add_*_type methods.
 */
VALUE
syck_loader_add_type_family( self, domain, type_re, proc )
    VALUE self, domain, type_re, proc;
{
    VALUE families, domain_types;

    families = rb_attr_get(self, s_families);
    domain_types = syck_get_hash_aref(families, domain);
    rb_hash_aset( domain_types, type_re, proc );
    return Qnil;
}

/*
 * YAML::Syck::Loader.add_domain_type
 */
VALUE
syck_loader_add_domain_type( argc, argv, self )
    int argc;
    VALUE *argv;
       VALUE self;
{
    VALUE domain, type_re, proc;

    rb_scan_args(argc, argv, "2&", &domain, &type_re, &proc);
    syck_loader_add_type_family( self, domain, type_re, proc );
    return Qnil;
}


/*
 * YAML::Syck::Loader.add_builtin_type
 */
VALUE
syck_loader_add_builtin_type( argc, argv, self )
    int argc;
    VALUE *argv;
       VALUE self;
{
    VALUE type_re, proc;

    rb_scan_args(argc, argv, "1&", &type_re, &proc);
    syck_loader_add_type_family( self, rb_str_new2( YAML_DOMAIN ), type_re, proc );
    return Qnil;
}

/*
 * YAML::Syck::Loader.add_ruby_type
 */
VALUE
syck_loader_add_ruby_type( argc, argv, self )
    int argc;
    VALUE *argv;
       VALUE self;
{
    VALUE type_re, proc;

    rb_scan_args(argc, argv, "1&", &type_re, &proc);
    syck_loader_add_type_family( self, rb_str_new2( RUBY_DOMAIN ), type_re, proc );
    return Qnil;
}

/*
 * YAML::Syck::Loader.add_private_type
 */
VALUE
syck_loader_add_private_type( argc, argv, self )
    int argc;
    VALUE *argv;
       VALUE self;
{
    VALUE type_re, proc, priv_types;

    rb_scan_args(argc, argv, "1&", &type_re, &proc);

    priv_types = rb_attr_get(self, s_private_types);
    rb_hash_aset( priv_types, type_re, proc );
    return Qnil;
}

/*
 * YAML::Syck::Loader#detect 
 */
VALUE
syck_loader_detect_implicit( self, val )
    VALUE self, val;
{
    char *type_id;

    if ( TYPE(val) == T_STRING )
    {
        type_id = syck_match_implicit( RSTRING(val)->ptr, RSTRING(val)->len );
        return rb_str_new2( type_id );
    }

    return rb_str_new2( "" );
}

/*
 * iterator to search a type hash for a match.
 */
static VALUE
transfer_find_i(entry, col)
    VALUE entry, col;
{
    VALUE key = rb_ary_entry( entry, 0 );
    VALUE tid = rb_ary_entry( col, 0 );
	if ( rb_respond_to( key, s_match ) )
	{
		VALUE match = rb_funcall( key, rb_intern("match"), 1, tid );
		if ( ! NIL_P( match ) )
		{
			rb_ary_push( col, rb_ary_entry( entry, 1 ) );
			rb_iter_break();
		}
	}
    return Qnil;
}

/*
 * YAML::Syck::Loader#transfer
 */
VALUE
syck_loader_transfer( self, type, val )
    VALUE self, type, val;
{
    char *taguri = NULL;

    if (NIL_P(type) || !RSTRING(type)->ptr || RSTRING(type)->len == 0) 
    {
        /*
         * Empty transfer, detect type
         */
        if ( TYPE(val) == T_STRING )
        {
            StringValue(val);
            taguri = syck_match_implicit( RSTRING(val)->ptr, RSTRING(val)->len );
            taguri = syck_taguri( YAML_DOMAIN, taguri, strlen( taguri ) );
        }
    }
    else
    {
        taguri = syck_type_id_to_uri( RSTRING(type)->ptr );
    }

    if ( taguri != NULL )
    {
        int transferred = 0;
        VALUE scheme, name, type_hash, domain = Qnil, type_proc = Qnil;
        VALUE type_uri = rb_str_new2( taguri );
        VALUE str_taguri = rb_str_new2("tag");
        VALUE str_xprivate = rb_str_new2("x-private");
        VALUE str_yaml_domain = rb_str_new2(YAML_DOMAIN);
        VALUE parts = rb_str_split( type_uri, ":" );

        scheme = rb_ary_shift( parts );

        if ( rb_str_cmp( scheme, str_xprivate ) == 0 )
        {
            name = rb_ary_join( parts, rb_str_new2( ":" ) );
            type_hash = rb_attr_get(self, s_private_types);
        }
        else if ( rb_str_cmp( scheme, str_taguri ) == 0 )
        {
            domain = rb_ary_shift( parts );
            name = rb_ary_join( parts, rb_str_new2( ":" ) );
            type_hash = rb_attr_get(self, s_families);
            type_hash = rb_hash_aref(type_hash, domain);

            /*
             * Route yaml.org types through the transfer
             * method here in this extension
             */
            if ( rb_str_cmp( domain, str_yaml_domain ) == 0 )
            {
                SyckNode *n = rb_new_syck_node(val, name);
                if ( n != NULL )
                {
                    transferred = yaml_org_handler(n, &val);
                    S_FREE( n );
                }
            }

        }
        else
        {
               rb_raise(rb_eTypeError, "invalid typing scheme: %s given",
                       scheme);
        }

        if ( ! transferred )
        {
            if ( rb_obj_is_instance_of( type_hash, rb_cHash ) )
            {
                type_proc = rb_hash_aref( type_hash, name );
                if ( NIL_P( type_proc ) )
                {
                    VALUE col = rb_ary_new();
                    rb_ary_push( col, name );
                    rb_iterate(rb_each, type_hash, transfer_find_i, col );
                    name = rb_ary_shift( col );
                    type_proc = rb_ary_shift( col );
                }
            }

            if ( rb_respond_to( type_proc, s_call ) )
            {
                val = rb_funcall(type_proc, s_call, 2, type_uri, val);
            }
            else if ( rb_str_cmp( scheme, str_xprivate ) == 0 )
            {
                val = rb_funcall(cPrivateType, s_new, 2, name, val);
            }
            else 
            {
                val = rb_funcall(cDomainType, s_new, 3, domain, name, val);
            }
            transferred = 1;
        }
    }

    return val;
}

/*
 * YAML::Syck::BadAlias.initialize
 */
VALUE
syck_badalias_initialize( self, val )
    VALUE self, val;
{
    rb_ivar_set( self, s_name, val );
    return self;
}

/*
 * YAML::Syck::BadAlias.<=>
 */
VALUE
syck_badalias_cmp( alias1, alias2 )
    VALUE alias1, alias2;
{
    VALUE str1 = rb_ivar_get( alias1, s_name ); 
    VALUE str2 = rb_ivar_get( alias2, s_name ); 
    VALUE val = rb_funcall( str1, s_cmp, 1, str2 );
    return val;
}

/*
 * YAML::Syck::DomainType.initialize
 */
VALUE
syck_domaintype_initialize( self, domain, type_id, val )
    VALUE self, type_id, val;
{
    rb_ivar_set( self, s_domain, domain );
    rb_ivar_set( self, s_type_id, type_id );
    rb_ivar_set( self, s_value, val );
    return self;
}

/*
 * YAML::Syck::PrivateType.initialize
 */
VALUE
syck_privatetype_initialize( self, type_id, val )
    VALUE self, type_id, val;
{
    rb_ivar_set( self, s_type_id, type_id );
    rb_ivar_set( self, s_value, val );
    return self;
}

/*
 * YAML::Syck::Node.initialize
 */
VALUE
syck_node_initialize( self, type_id, val )
    VALUE self, type_id, val;
{
    rb_ivar_set( self, s_type_id, type_id );
    rb_ivar_set( self, s_value, val );
    return self;
}

VALUE
syck_node_thash( entry, t )
    VALUE entry, t;
{
    VALUE key, val;
    key = rb_ary_entry( entry, 0 );
    val = syck_node_transform( rb_ary_entry( rb_ary_entry( entry, 1 ), 1 ) );
    rb_hash_aset( t, key, val );
    return Qnil;
}

VALUE
syck_node_ahash( entry, t )
    VALUE entry, t;
{
    VALUE val = syck_node_transform( entry );
    rb_ary_push( t, val );
    return Qnil;
}

/*
 * YAML::Syck::Node.transform
 */
VALUE
syck_node_transform( self )
    VALUE self;
{
    VALUE t = Qnil;
    VALUE type_id = rb_attr_get( self, s_type_id );
    VALUE val = rb_attr_get( self, s_value );
    if ( rb_obj_is_instance_of( val, rb_cHash ) )
    {
        t = rb_hash_new();
        rb_iterate( rb_each, val, syck_node_thash, t );
    }
    else if ( rb_obj_is_instance_of( val, rb_cArray ) )
    {
        t = rb_ary_new();
        rb_iterate( rb_each, val, syck_node_ahash, t );
    }
    else
    {
        t = val;
    }
    return rb_funcall( oDefaultLoader, s_transfer, 2, type_id, t );
}

/*
 * Handle output from the emitter
 */
void 
rb_syck_output_handler( emitter, str, len )
    SyckEmitter *emitter;
    char *str;
    long len;
{
    VALUE dest = (VALUE)emitter->bonus;
    if ( rb_respond_to( dest, s_to_str ) ) {
        rb_str_cat( dest, str, len );
    } else {
        rb_io_write( dest, rb_str_new( str, len ) );
    }
}

/*
 * Mark emitter values.
 */
static void
syck_mark_emitter(emitter)
    SyckEmitter *emitter;
{
    rb_gc_mark(emitter->ignore_id);
    if ( emitter->bonus != NULL )
    {
        rb_gc_mark( (VALUE)emitter->bonus );
    }
}

/*
 * YAML::Syck::Emitter.new
 */
VALUE 
syck_emitter_new(argc, argv, class)
    int argc;
    VALUE *argv;
	VALUE class;
{
	VALUE pobj, options, init_argv[1];
    SyckEmitter *emitter = syck_new_emitter();
    rb_scan_args(argc, argv, "01", &options);

	pobj = Data_Wrap_Struct( class, syck_mark_emitter, syck_free_emitter, emitter );
    syck_emitter_ignore_id( emitter, Qnil );
    syck_emitter_handler( emitter, rb_syck_output_handler );
    emitter->bonus = (void *)rb_str_new2( "" );

    if ( ! rb_obj_is_instance_of( options, rb_cHash ) )
    {
        options = rb_hash_new();
    }
	init_argv[0] = options;
	rb_obj_call_init(pobj, 1, init_argv);
	return pobj;
}

/*
 * YAML::Syck::Emitter.initialize( options )
 */
static VALUE
syck_emitter_initialize( self, options )
    VALUE self, options;
{
    rb_ivar_set(self, s_options, options);
	return self;
}

/*
 * YAML::Syck::Emitter.level
 */
VALUE
syck_emitter_level_m( self )
    VALUE self;
{
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    return LONG2NUM( emitter->level );
}

/*
 * YAML::Syck::Emitter.flush
 */
VALUE
syck_emitter_flush_m( self )
    VALUE self;
{
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    syck_emitter_flush( emitter, 0 );
    return self;
}

/*
 * YAML::Syck::Emitter.write( str )
 */
VALUE
syck_emitter_write_m( self, str )
    VALUE self, str;
{
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    StringValue(str);
    syck_emitter_write( emitter, RSTRING(str)->ptr, RSTRING(str)->len );
    return self;
}

/*
 * YAML::Syck::Emitter.simple( str )
 */
VALUE
syck_emitter_simple_write( self, str )
    VALUE self, str;
{
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    StringValue(str);
    syck_emitter_simple( emitter, RSTRING(str)->ptr, RSTRING(str)->len );
    return self;
}

/*
 * YAML::Syck::Emitter.start_object( object_id )
 */
VALUE
syck_emitter_start_object( self, oid )
    VALUE self, oid;
{
    char *anchor_name;
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    anchor_name = syck_emitter_start_obj( emitter, oid );

    if ( anchor_name == NULL )
    {
        return Qnil;
    }

    return rb_str_new2( anchor_name );
}

/*
 * YAML::Syck::Emitter.end_object
 */
VALUE
syck_emitter_end_object( self )
    VALUE self;
{
    SyckEmitter *emitter;

	Data_Get_Struct(self, SyckEmitter, emitter);
    syck_emitter_end_obj( emitter );

    if ( emitter->level < 0 )
    {
        syck_emitter_flush( emitter, 0 );
    }
    return (VALUE)emitter->bonus;
}

/*
 * Initialize Syck extension
 */
void
Init_syck()
{
    VALUE rb_yaml = rb_define_module( "YAML" );
    VALUE rb_syck = rb_define_module_under( rb_yaml, "Syck" );
    rb_define_const( rb_syck, "VERSION", rb_str_new2( SYCK_VERSION ) );
    rb_define_module_function( rb_syck, "compile", rb_syck_compile, 1 );

	/*
	 * Global symbols
	 */
    s_new = rb_intern("new");
    s_utc = rb_intern("utc");
    s_at = rb_intern("at");
    s_to_f = rb_intern("to_f");
    s_to_i = rb_intern("to_i");
    s_read = rb_intern("read");
    s_anchors = rb_intern("anchors");
    s_binmode = rb_intern("binmode");
    s_transfer = rb_intern("transfer");
    s_call = rb_intern("call");
    s_cmp = rb_intern("<=>");
	s_update = rb_intern("update");
	s_dup = rb_intern("dup");
    s_default_set = rb_intern("default=");
	s_match = rb_intern("match");
	s_keys = rb_intern("keys");
	s_to_str = rb_intern("to_str");
	s_tr_bang = rb_intern("tr!");
    s_unpack = rb_intern("unpack");

    s_anchors = rb_intern("@anchors");
    s_domain = rb_intern("@domain");
    s_families = rb_intern("@families");
    s_kind = rb_intern("@kind");
    s_name = rb_intern("@name");
    s_options = rb_intern("@options");
    s_private_types = rb_intern("@private_types");
    s_type_id = rb_intern("@type_id");
    s_value = rb_intern("@value");

	sym_model = ID2SYM(rb_intern("Model"));
	sym_generic = ID2SYM(rb_intern("Generic"));
	sym_input = ID2SYM(rb_intern("Input"));
	sym_bytecode = ID2SYM(rb_intern("Bytecode"));
    sym_map = ID2SYM(rb_intern("map"));
    sym_scalar = ID2SYM(rb_intern("scalar"));
    sym_seq = ID2SYM(rb_intern("seq"));

    /*
     * Define YAML::Syck::Loader class
     */
    cLoader = rb_define_class_under( rb_syck, "Loader", rb_cObject );
    rb_define_attr( cLoader, "families", 1, 1 );
    rb_define_attr( cLoader, "private_types", 1, 1 );
    rb_define_attr( cLoader, "anchors", 1, 1 );
    rb_define_method( cLoader, "initialize", syck_loader_initialize, 0 );
    rb_define_method( cLoader, "add_domain_type", syck_loader_add_domain_type, -1 );
    rb_define_method( cLoader, "add_builtin_type", syck_loader_add_builtin_type, -1 );
    rb_define_method( cLoader, "add_ruby_type", syck_loader_add_ruby_type, -1 );
    rb_define_method( cLoader, "add_private_type", syck_loader_add_private_type, -1 );
    rb_define_method( cLoader, "bufsize=", syck_parser_bufsize_set, 1 );
    rb_define_method( cLoader, "bufsize", syck_parser_bufsize_get, 0 );
    rb_define_method( cLoader, "detect_implicit", syck_loader_detect_implicit, 1 );
    rb_define_method( cLoader, "transfer", syck_loader_transfer, 2 );

    oDefaultLoader = rb_funcall( cLoader, rb_intern( "new" ), 0 );
    rb_define_const( rb_syck, "DefaultLoader", oDefaultLoader );

    /*
     * Define YAML::Syck::Parser class
     */
    cParser = rb_define_class_under( rb_syck, "Parser", rb_cObject );
    rb_define_attr( cParser, "options", 1, 1 );
	rb_define_singleton_method( cParser, "new", syck_parser_new, -1 );
    rb_define_method(cParser, "initialize", syck_parser_initialize, 1);
    rb_define_method(cParser, "load", syck_parser_load, -1);
    rb_define_method(cParser, "load_documents", syck_parser_load_documents, -1);

    /*
     * Define YAML::Syck::Node class
     */
    cNode = rb_define_class_under( rb_syck, "Node", rb_cObject );
    rb_define_attr( cNode, "kind", 1, 1 );
    rb_define_attr( cNode, "type_id", 1, 1 );
    rb_define_attr( cNode, "value", 1, 1 );
    rb_define_attr( cNode, "anchor", 1, 1 );
    rb_define_method( cNode, "initialize", syck_node_initialize, 2);
    rb_define_method( cNode, "transform", syck_node_transform, 0);

    /*
     * Define YAML::Syck::PrivateType class
     */
    cPrivateType = rb_define_class_under( rb_syck, "PrivateType", rb_cObject );
    rb_define_attr( cPrivateType, "type_id", 1, 1 );
    rb_define_attr( cPrivateType, "value", 1, 1 );
    rb_define_method( cPrivateType, "initialize", syck_privatetype_initialize, 2);

    /*
     * Define YAML::Syck::DomainType class
     */
    cDomainType = rb_define_class_under( rb_syck, "DomainType", rb_cObject );
    rb_define_attr( cDomainType, "domain", 1, 1 );
    rb_define_attr( cDomainType, "type_id", 1, 1 );
    rb_define_attr( cDomainType, "value", 1, 1 );
    rb_define_method( cDomainType, "initialize", syck_domaintype_initialize, 3);

    /*
     * Define YAML::Syck::BadAlias class
     */
    cBadAlias = rb_define_class_under( rb_syck, "BadAlias", rb_cObject );
    rb_define_attr( cBadAlias, "name", 1, 1 );
    rb_define_method( cBadAlias, "initialize", syck_badalias_initialize, 1);
    rb_define_method( cBadAlias, "<=>", syck_badalias_cmp, 1);
    rb_include_module( cBadAlias, rb_const_get( rb_cObject, rb_intern("Comparable") ) );

	/*
	 * Define YAML::Syck::MergeKey class
	 */
	cMergeKey = rb_define_class_under( rb_syck, "MergeKey", rb_cObject );

	/*
	 * Define YAML::Syck::DefaultKey class
	 */
	cDefaultKey = rb_define_class_under( rb_syck, "DefaultKey", rb_cObject );

    /*
     * Define YAML::Syck::Emitter class
     */
    cEmitter = rb_define_class_under( rb_syck, "Emitter", rb_cObject );
	rb_define_singleton_method( cEmitter, "new", syck_emitter_new, -1 );
    rb_define_method( cEmitter, "initialize", syck_emitter_initialize, 1 );
    rb_define_method( cEmitter, "level", syck_emitter_level_m, 0 );
    rb_define_method( cEmitter, "write", syck_emitter_write_m, 1 );
    rb_define_method( cEmitter, "<<", syck_emitter_write_m, 1 );
    rb_define_method( cEmitter, "simple", syck_emitter_simple_write, 1 );
    rb_define_method( cEmitter, "flush", syck_emitter_flush_m, 0 );
    rb_define_method( cEmitter, "start_object", syck_emitter_start_object, 1 );
    rb_define_method( cEmitter, "end_object", syck_emitter_end_object, 0 );
}

