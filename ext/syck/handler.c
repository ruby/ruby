/*
 * handler.h
 *
 * $Author$
 * $Date$
 *
 * Copyright (C) 2003 why the lucky stiff
 */

#include "syck.h"

SYMID 
syck_hdlr_add_node( SyckParser *p, SyckNode *n )
{
    SYMID id;

    if ( ! n->id ) 
    {
        n->id = (p->handler)( p, n );
    }
    id = n->id;

    if ( n->anchor == NULL )
    {
        syck_free_node( n );
    }
    return id;
}

SyckNode *
syck_hdlr_add_anchor( SyckParser *p, char *a, SyckNode *n )
{
    n->anchor = a;
    st_insert( p->anchors, (st_data_t)a, (st_data_t)n );
    return n;
}

SyckNode *
syck_hdlr_add_alias( SyckParser *p, char *a )
{
    SyckNode *n;

    if ( st_lookup( p->anchors, (st_data_t)a, (st_data_t *)&n ) )
    {
        return n;
    }

    //
    // FIXME: Return an InvalidAnchor object
    //
    return syck_new_str( "..." );
}

void
syck_add_transfer( char *uri, SyckNode *n, int taguri )
{
    char *comma = NULL;
    char *slash = uri;
    char *domain = NULL;

    if ( n->type_id != NULL )
    {
        S_FREE( n->type_id );
    }

    if ( taguri == 0 )
    {
        n->type_id = uri;
        return;
    }

    n->type_id = syck_type_id_to_uri( uri );
    S_FREE( uri );
}

char *
syck_xprivate( char *type_id, int type_len )
{
    char *uri = S_ALLOC_N( char, type_len + 14 );
    uri[0] = '\0';
    strcat( uri, "x-private:" );
    strncat( uri, type_id, type_len );
    return uri;
}

char *
syck_taguri( char *domain, char *type_id, int type_len )
{
    char *uri = S_ALLOC_N( char, strlen( domain ) + type_len + 14 );
    uri[0] = '\0';
    strcat( uri, "taguri:" );
    strcat( uri, domain );
    strcat( uri, ":" );
    strncat( uri, type_id, type_len );
    return uri;
}

int 
syck_try_implicit( SyckNode *n )
{
    return 1;
}

