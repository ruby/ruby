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
    st_insert( p->anchors, a, n );
    return n;
}

SyckNode *
syck_hdlr_add_alias( SyckParser *p, char *a )
{
    SyckNode *n;

    if ( st_lookup( p->anchors, a, &n ) )
    {
        return n;
    }

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

void 
syck_fold_format( struct SyckStr *n, int blockType, int indt_len, int nlDisp )
{
    char *spc;
    char *eol = NULL;
    char *first_nl = NULL;
    char *fc = n->ptr;
    int keep_nl = 0;
    int nl_count = 0;

    //
    // Scan the sucker for newlines and strip indent
    //
    while ( fc < n->ptr + n->len )
    {
        if ( *fc == '\n' )
        {
            spc = fc;
            while ( *(++spc) == ' ' )
            {
                if ( blockType != BLOCK_PLAIN && spc - fc > indt_len )
                    break;
            }

            if ( blockType != BLOCK_LIT && *spc != ' ' )
            {
                if ( eol != NULL ) fc = eol;
                if ( first_nl == NULL && keep_nl == 1 )
                {
                    first_nl = fc;
                    *first_nl = ' ';
                }
                if ( nl_count == 1 )
                {
                    *first_nl = '\n';
                    keep_nl = 0;
                }
            }

            fc += keep_nl;
            if ( fc != spc && ( n->len - ( spc - n->ptr ) ) > 0 )
            {
                S_MEMMOVE( fc, spc, char, n->len - ( spc - n->ptr ) ); 
            }

            n->len -= spc - fc;
            keep_nl = 1;
            eol = NULL;
            nl_count++;
        }
        else
        {
            //
            // eol tracks the last space on a line
            // 
            if ( *fc == ' ' )
            {
                if ( eol == NULL ) eol = fc;
            }
            else
            {
                eol = NULL;
            }
            first_nl = NULL;
            nl_count = 0;
            fc++;
        }
    }

    n->ptr[n->len] = '\n';

    //
    // Chomp or keep?
    //
    if ( nlDisp != NL_KEEP )
    {
        fc = n->ptr + n->len - 1;
        while ( *fc == '\n' )
            fc--;

        if ( nlDisp != NL_CHOMP )
            fc += 1;

        n->len = fc - n->ptr + 1;
    }
    else
    {
        //
        // Force last line break which I gave back
        // to the tokenizer.
        //
        n->len++;
        n->ptr[n->len] = '\n';
    }
    n->ptr[ n->len ] = '\0';
}

