/*
 * syck.h
 *
 * $Author$
 * $Date$
 *
 * Copyright (C) 2003 why the lucky stiff
 */

#ifndef SYCK_H
#define SYCK_H

#define SYCK_YAML_MAJOR 1
#define SYCK_YAML_MINOR 0

#define SYCK_VERSION    "0.43"
#define YAML_DOMAIN     "yaml.org,2002"

#include <stdio.h>
#include <ctype.h>
#include "st.h"

#if defined(__cplusplus)
extern "C" {
#endif

/*
 * Memory Allocation
 */
#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

#if DEBUG
  void syck_assert( char *, unsigned );
# define ASSERT(f) \
    if ( f ) \
        {}   \
    else     \
        syck_assert( __FILE__, __LINE__ )
#else
# define ASSERT(f)
#endif

#ifndef NULL
# define NULL (void *)0
#endif

#define ALLOC_CT 8
#define SYCK_BUFFERSIZE 4096
#define S_ALLOC_N(type,n) (type*)malloc(sizeof(type)*(n))
#define S_ALLOC(type) (type*)malloc(sizeof(type))
#define S_REALLOC_N(var,type,n) (var)=(type*)realloc((char*)(var),sizeof(type)*(n))
#define S_FREE(n) free(n); n = NULL;

#define S_ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define S_MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define S_MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))
#define S_MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(n))
#define S_MEMCMP(p1,p2,type,n) memcmp((p1), (p2), sizeof(type)*(n))

#define BLOCK_FOLD  10
#define BLOCK_LIT   20
#define BLOCK_PLAIN 30
#define NL_CHOMP    130
#define NL_KEEP     140

/*
 * Node definitions
 */
#define SYMID unsigned long

typedef struct _syck_node SyckNode;

enum syck_kind_tag {
    syck_map_kind,
    syck_seq_kind,
    syck_str_kind
};

enum map_part {
    map_key,
    map_value
};

/*
 * Node metadata struct
 */
struct _syck_node {
    /* Symbol table ID */
    SYMID id;
    /* Underlying kind */
    enum syck_kind_tag kind;
    /* Fully qualified tag-uri for type */
    char *type_id;
    /* Anchor name */
    char *anchor;
    union {
        /* Storage for map data */
        struct SyckMap {
            SYMID *keys;
            SYMID *values;
            long capa;
            long idx;
        } *pairs;
        /* Storage for sequence data */
        struct SyckSeq {
            SYMID *items;
            long capa;
            long idx;
        } *list;
        /* Storage for string data */
        struct SyckStr {
            char *ptr;
            long len;
        } *str;
    } data;
    /* Shortcut node */
    void *shortcut;
};

/*
 * Parser definitions
 */
typedef struct _syck_parser SyckParser;
typedef struct _syck_file SyckIoFile;
typedef struct _syck_str SyckIoStr;
typedef struct _syck_level SyckLevel;

typedef SYMID (*SyckNodeHandler)(SyckParser *, SyckNode *);
typedef void (*SyckErrorHandler)(SyckParser *, char *);
typedef SyckNode * (*SyckBadAnchorHandler)(SyckParser *, char *);
typedef long (*SyckIoFileRead)(char *, SyckIoFile *, long, long); 
typedef long (*SyckIoStrRead)(char *, SyckIoStr *, long, long);

enum syck_io_type {
    syck_io_str,
    syck_io_file
};

enum syck_parser_input {
    syck_yaml_utf8,
    syck_yaml_utf16,
    syck_yaml_utf32,
    syck_bytecode_utf8
};

enum syck_level_status {
    syck_lvl_header,
    syck_lvl_doc,
    syck_lvl_open,
    syck_lvl_seq,
    syck_lvl_map,
    syck_lvl_block,
    syck_lvl_str,
    syck_lvl_inline,
    syck_lvl_end,
    syck_lvl_pause
};

/*
 * Parser structs
 */
struct _syck_file {
    /* File pointer */
    FILE *ptr;
    /* Function which FILE -> buffer */
    SyckIoFileRead read;
};

struct _syck_str {
    /* String buffer pointers */
    char *beg, *ptr, *end;
    /* Function which string -> buffer */
    SyckIoStrRead read;
};

struct _syck_level {
    int spaces;
    int ncount;
    char *domain;
    enum syck_level_status status;
};

struct _syck_parser {
    /* Root node */
    SYMID root, root_on_error;
    /* Implicit typing flag */
    int implicit_typing, taguri_expansion;
    /* Scripting language function to handle nodes */
    SyckNodeHandler handler;
    /* Error handler */
    SyckErrorHandler error_handler;
    /* InvalidAnchor handler */
    SyckBadAnchorHandler bad_anchor_handler;
    /* Parser input type */
    enum syck_parser_input input_type;
    /* IO type */
    enum syck_io_type io_type;
    /* Custom buffer size */
    size_t bufsize;
    /* Buffer pointers */
    char *buffer, *linectptr, *lineptr, *toktmp, *token, *cursor, *marker, *limit;
    /* Line counter */
    int linect;
    /* Last token from yylex() */
    int last_token;
    /* Force a token upon next call to yylex() */
    int force_token;
    /* EOF flag */
    int eof;
    union {
        SyckIoFile *file;
        SyckIoStr *str;
    } io;
    /* Symbol table for anchors */
    st_table *anchors, *bad_anchors;
    /* Optional symbol table for SYMIDs */
    st_table *syms;
    /* Levels of indentation */
    SyckLevel *levels;
    int lvl_idx;
    int lvl_capa;
    void *bonus;
};

/*
 * Emitter definitions
 */
typedef struct _syck_emitter SyckEmitter;
typedef struct _syck_emitter_node SyckEmitterNode;

typedef void (*SyckOutputHandler)(SyckEmitter *, char *, long); 

enum doc_stage {
    doc_open,
    doc_need_header,
    doc_processing
};

enum block_styles {
    block_arbitrary,
    block_fold,
    block_literal
};

/*
 * Emitter struct
 */
struct _syck_emitter {
    /* Headerless doc flag */
    int headless;
    /* Sequence map shortcut flag */
    int seq_map;
    /* Force header? */
    int use_header;
    /* Force version? */
    int use_version;
    /* Sort hash keys */
    int sort_keys;
    /* Anchor format */
    char *anchor_format;
    /* Explicit typing on all collections? */
    int explicit_typing;
    /* Best width on folded scalars */
    int best_width;
    /* Use literal[1] or folded[2] blocks on all text? */
    enum block_styles block_style;
    /* Stage of written document */
    enum doc_stage stage;
    /* Level counter */
    int level;
    /* Default indentation */
    int indent;
    /* Object ignore ID */
    SYMID ignore_id;
    /* Symbol table for anchors */
    st_table *markers, *anchors;
    /* Custom buffer size */
    size_t bufsize;
    /* Buffer */
    char *buffer, *marker;
    /* Absolute position of the buffer */
    long bufpos;
    /* Handler for output */
    SyckOutputHandler handler;
    /* Pointer for extension's use */
    void *bonus;
};

/*
 * Emitter node metadata struct
 */
struct _syck_emitter_node {
    /* Node buffer position */
    long pos;
    /* Current indent */
    long indent;
    /* Collection? */
    int is_shortcut;
};

/*
 * Handler prototypes
 */
SYMID syck_hdlr_add_node( SyckParser *, SyckNode * );
SyckNode *syck_hdlr_add_anchor( SyckParser *, char *, SyckNode * );
void syck_hdlr_remove_anchor( SyckParser *, char * );
SyckNode *syck_hdlr_get_anchor( SyckParser *, char * );
void syck_add_transfer( char *, SyckNode *, int );
char *syck_xprivate( char *, int );
char *syck_taguri( char *, char *, int );
int syck_add_sym( SyckParser *, char * );
int syck_lookup_sym( SyckParser *, SYMID, char ** );
int syck_try_implicit( SyckNode * );
char *syck_type_id_to_uri( char * );
void try_tag_implicit( SyckNode *, int );
char *syck_match_implicit( char *, size_t );

/*
 * API prototypes
 */
char *syck_strndup( char *, long );
long syck_io_file_read( char *, SyckIoFile *, long, long );
long syck_io_str_read( char *, SyckIoStr *, long, long );
char *syck_base64enc( char *, long );
char *syck_base64dec( char *, long );
SyckEmitter *syck_new_emitter();
void syck_emitter_ignore_id( SyckEmitter *, SYMID );
void syck_emitter_handler( SyckEmitter *, SyckOutputHandler );
void syck_free_emitter( SyckEmitter * );
void syck_emitter_clear( SyckEmitter * );
void syck_emitter_simple( SyckEmitter *, char *, long );
void syck_emitter_write( SyckEmitter *, char *, long );
void syck_emitter_flush( SyckEmitter *, long );
char *syck_emitter_start_obj( SyckEmitter *, SYMID );
void syck_emitter_end_obj( SyckEmitter * );
SyckParser *syck_new_parser();
void syck_free_parser( SyckParser * );
void syck_parser_set_root_on_error( SyckParser *, SYMID );
void syck_parser_implicit_typing( SyckParser *, int );
void syck_parser_taguri_expansion( SyckParser *, int );
void syck_parser_handler( SyckParser *, SyckNodeHandler );
void syck_parser_error_handler( SyckParser *, SyckErrorHandler );
void syck_parser_bad_anchor_handler( SyckParser *, SyckBadAnchorHandler );
void syck_parser_file( SyckParser *, FILE *, SyckIoFileRead );
void syck_parser_str( SyckParser *, char *, long, SyckIoStrRead );
void syck_parser_str_auto( SyckParser *, char *, SyckIoStrRead );
SyckLevel *syck_parser_current_level( SyckParser * );
void syck_parser_add_level( SyckParser *, int, enum syck_level_status );
void syck_parser_pop_level( SyckParser * );
void free_any_io( SyckParser * );
long syck_parser_read( SyckParser * );
long syck_parser_readlen( SyckParser *, long );
void syck_parser_init( SyckParser *, int );
SYMID syck_parse( SyckParser * );
void syck_default_error_handler( SyckParser *, char * );
SYMID syck_yaml2byte_handler( SyckParser *, SyckNode * );
char *syck_yaml2byte( char * );

/*
 * Allocation prototypes
 */
SyckNode *syck_alloc_map();
SyckNode *syck_alloc_seq();
SyckNode *syck_alloc_str();
void syck_free_node( SyckNode * );
void syck_free_members( SyckNode * );
SyckNode *syck_new_str( char * );
SyckNode *syck_new_str2( char *, long );
void syck_str_blow_away_commas( SyckNode * );
char *syck_str_read( SyckNode * );
SyckNode *syck_new_map( SYMID, SYMID );
void syck_map_add( SyckNode *, SYMID, SYMID );
SYMID syck_map_read( SyckNode *, enum map_part, long );
void syck_map_assign( SyckNode *, enum map_part, long, SYMID );
long syck_map_count( SyckNode * );
void syck_map_update( SyckNode *, SyckNode * );
SyckNode *syck_new_seq( SYMID );
void syck_seq_add( SyckNode *, SYMID );
SYMID syck_seq_read( SyckNode *, long );
long syck_seq_count( SyckNode * );

void apply_seq_in_map( SyckParser *, SyckNode * );

/*
 * Lexer prototypes
 */
void syckerror( char * );

#ifndef ST_DATA_T_DEFINED
typedef long st_data_t;
#endif

#if defined(__cplusplus)
}  /* extern "C" { */
#endif

#endif /* ifndef SYCK_H */
