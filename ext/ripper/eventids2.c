enum {
    tIGNORED_NL  = tLAST_TOKEN + 1,
    tCOMMENT,
    tEMBDOC_BEG,
    tEMBDOC,
    tEMBDOC_END,
    tHEREDOC_BEG,
    tHEREDOC_END,
    k__END__
};

typedef struct {
    ID ripper_id_backref;
    ID ripper_id_backtick;
    ID ripper_id_comma;
    ID ripper_id_const;
    ID ripper_id_cvar;
    ID ripper_id_embexpr_beg;
    ID ripper_id_embexpr_end;
    ID ripper_id_embvar;
    ID ripper_id_float;
    ID ripper_id_gvar;
    ID ripper_id_ident;
    ID ripper_id_imaginary;
    ID ripper_id_int;
    ID ripper_id_ivar;
    ID ripper_id_kw;
    ID ripper_id_lbrace;
    ID ripper_id_lbracket;
    ID ripper_id_lparen;
    ID ripper_id_nl;
    ID ripper_id_op;
    ID ripper_id_period;
    ID ripper_id_rbrace;
    ID ripper_id_rbracket;
    ID ripper_id_rparen;
    ID ripper_id_semicolon;
    ID ripper_id_symbeg;
    ID ripper_id_tstring_beg;
    ID ripper_id_tstring_content;
    ID ripper_id_tstring_end;
    ID ripper_id_words_beg;
    ID ripper_id_qwords_beg;
    ID ripper_id_qsymbols_beg;
    ID ripper_id_symbols_beg;
    ID ripper_id_words_sep;
    ID ripper_id_rational;
    ID ripper_id_regexp_beg;
    ID ripper_id_regexp_end;
    ID ripper_id_label;
    ID ripper_id_label_end;
    ID ripper_id_tlambda;
    ID ripper_id_tlambeg;
    ID ripper_id_tnumparam;

    ID ripper_id_ignored_nl;
    ID ripper_id_comment;
    ID ripper_id_embdoc_beg;
    ID ripper_id_embdoc;
    ID ripper_id_embdoc_end;
    ID ripper_id_sp;
    ID ripper_id_heredoc_beg;
    ID ripper_id_heredoc_end;
    ID ripper_id___end__;
    ID ripper_id_CHAR;
} ripper_scanner_ids_t;

static ripper_scanner_ids_t ripper_scanner_ids;

#include "eventids2table.c"

static void
ripper_init_eventids2(void)
{
#define set_id2(name) ripper_scanner_ids.ripper_id_##name = rb_intern_const("on_"#name)
    set_id2(backref);
    set_id2(backtick);
    set_id2(comma);
    set_id2(const);
    set_id2(cvar);
    set_id2(embexpr_beg);
    set_id2(embexpr_end);
    set_id2(embvar);
    set_id2(float);
    set_id2(gvar);
    set_id2(ident);
    set_id2(imaginary);
    set_id2(int);
    set_id2(ivar);
    set_id2(kw);
    set_id2(lbrace);
    set_id2(lbracket);
    set_id2(lparen);
    set_id2(nl);
    set_id2(op);
    set_id2(period);
    set_id2(rbrace);
    set_id2(rbracket);
    set_id2(rparen);
    set_id2(semicolon);
    set_id2(symbeg);
    set_id2(tstring_beg);
    set_id2(tstring_content);
    set_id2(tstring_end);
    set_id2(words_beg);
    set_id2(qwords_beg);
    set_id2(qsymbols_beg);
    set_id2(symbols_beg);
    set_id2(words_sep);
    set_id2(rational);
    set_id2(regexp_beg);
    set_id2(regexp_end);
    set_id2(label);
    set_id2(label_end);
    set_id2(tlambda);
    set_id2(tlambeg);
    set_id2(tnumparam);

    set_id2(ignored_nl);
    set_id2(comment);
    set_id2(embdoc_beg);
    set_id2(embdoc);
    set_id2(embdoc_end);
    set_id2(sp);
    set_id2(heredoc_beg);
    set_id2(heredoc_end);
    set_id2(__end__);
    set_id2(CHAR);
}

STATIC_ASSERT(k__END___range, k__END__ < SHRT_MAX);
STATIC_ASSERT(ripper_scanner_ids_size, sizeof(ripper_scanner_ids) < SHRT_MAX);
#define O(member) (int)offsetof(ripper_scanner_ids_t, ripper_id_##member)

static const struct token_assoc {
    unsigned short token;
    unsigned short id_offset;
} token_to_eventid[] = {
    {' ',			O(words_sep)},
    {'!',			O(op)},
    {'%',			O(op)},
    {'&',			O(op)},
    {'*',			O(op)},
    {'+',			O(op)},
    {'-',			O(op)},
    {'/',			O(op)},
    {'<',			O(op)},
    {'=',			O(op)},
    {'>',			O(op)},
    {'?',			O(op)},
    {'^',			O(op)},
    {'|',			O(op)},
    {'~',			O(op)},
    {':',			O(op)},
    {',',			O(comma)},
    {'.',			O(period)},
    {';',			O(semicolon)},
    {'`',			O(backtick)},
    {'\n',			O(nl)},
    {keyword_alias,		O(kw)},
    {keyword_and,		O(kw)},
    {keyword_begin,		O(kw)},
    {keyword_break,		O(kw)},
    {keyword_case,		O(kw)},
    {keyword_class,		O(kw)},
    {keyword_def,		O(kw)},
    {keyword_defined,		O(kw)},
    {keyword_do,		O(kw)},
    {keyword_do_block,		O(kw)},
    {keyword_do_cond,		O(kw)},
    {keyword_else,		O(kw)},
    {keyword_elsif,		O(kw)},
    {keyword_end,		O(kw)},
    {keyword_ensure,		O(kw)},
    {keyword_false,		O(kw)},
    {keyword_for,		O(kw)},
    {keyword_if,		O(kw)},
    {modifier_if,		O(kw)},
    {keyword_in,		O(kw)},
    {keyword_module,		O(kw)},
    {keyword_next,		O(kw)},
    {keyword_nil,		O(kw)},
    {keyword_not,		O(kw)},
    {keyword_or,		O(kw)},
    {keyword_redo,		O(kw)},
    {keyword_rescue,		O(kw)},
    {modifier_rescue,		O(kw)},
    {keyword_retry,		O(kw)},
    {keyword_return,		O(kw)},
    {keyword_self,		O(kw)},
    {keyword_super,		O(kw)},
    {keyword_then,		O(kw)},
    {keyword_true,		O(kw)},
    {keyword_undef,		O(kw)},
    {keyword_unless,		O(kw)},
    {modifier_unless,		O(kw)},
    {keyword_until,		O(kw)},
    {modifier_until,		O(kw)},
    {keyword_when,		O(kw)},
    {keyword_while,		O(kw)},
    {modifier_while,		O(kw)},
    {keyword_yield,		O(kw)},
    {keyword__FILE__,		O(kw)},
    {keyword__LINE__,		O(kw)},
    {keyword__ENCODING__,	O(kw)},
    {keyword_BEGIN,		O(kw)},
    {keyword_END,		O(kw)},
    {keyword_do_LAMBDA,		O(kw)},
    {tAMPER,			O(op)},
    {tANDOP,			O(op)},
    {tAREF,			O(op)},
    {tASET,			O(op)},
    {tASSOC,			O(op)},
    {tBACK_REF,			O(backref)},
    {tCHAR,			O(CHAR)},
    {tCMP,			O(op)},
    {tCOLON2,			O(op)},
    {tCOLON3,			O(op)},
    {tCONSTANT,			O(const)},
    {tCVAR,			O(cvar)},
    {tDOT2,			O(op)},
    {tDOT3,			O(op)},
    {tEQ,			O(op)},
    {tEQQ,			O(op)},
    {tFID,			O(ident)},
    {tFLOAT,			O(float)},
    {tGEQ,			O(op)},
    {tGVAR,			O(gvar)},
    {tIDENTIFIER,		O(ident)},
    {tIMAGINARY,		O(imaginary)},
    {tINTEGER,			O(int)},
    {tIVAR,			O(ivar)},
    {tLBRACE,			O(lbrace)},
    {tLBRACE_ARG,		O(lbrace)},
    {'{',			O(lbrace)},
    {'}',			O(rbrace)},
    {tLBRACK,			O(lbracket)},
    {'[',			O(lbracket)},
    {']',			O(rbracket)},
    {tLEQ,			O(op)},
    {tLPAREN,			O(lparen)},
    {tLPAREN_ARG,		O(lparen)},
    {'(',			O(lparen)},
    {')',			O(rparen)},
    {tLSHFT,			O(op)},
    {tMATCH,			O(op)},
    {tNEQ,			O(op)},
    {tNMATCH,			O(op)},
    {tNTH_REF,			O(backref)},
    {tOP_ASGN,			O(op)},
    {tOROP,			O(op)},
    {tPOW,			O(op)},
    {tQWORDS_BEG,		O(qwords_beg)},
    {tQSYMBOLS_BEG,		O(qsymbols_beg)},
    {tSYMBOLS_BEG,		O(symbols_beg)},
    {tRATIONAL,			O(rational)},
    {tREGEXP_BEG,		O(regexp_beg)},
    {tREGEXP_END,		O(regexp_end)},
    {tRPAREN,			O(rparen)},
    {tRSHFT,			O(op)},
    {tSTAR,			O(op)},
    {tDSTAR,			O(op)},
    {tANDDOT,			O(op)},
    {tMETHREF,			O(op)},
    {tSTRING_BEG,		O(tstring_beg)},
    {tSTRING_CONTENT,		O(tstring_content)},
    {tSTRING_DBEG,		O(embexpr_beg)},
    {tSTRING_DEND,		O(embexpr_end)},
    {tSTRING_DVAR,		O(embvar)},
    {tSTRING_END,		O(tstring_end)},
    {tSYMBEG,			O(symbeg)},
    {tUMINUS,			O(op)},
    {tUMINUS_NUM,		O(op)},
    {tUPLUS,			O(op)},
    {tWORDS_BEG,		O(words_beg)},
    {tXSTRING_BEG,		O(backtick)},
    {tLABEL,			O(label)},
    {tLABEL_END,		O(label_end)},
    {tLAMBDA,			O(tlambda)},
    {tLAMBEG,			O(tlambeg)},
    {tNUMPARAM, 		O(tnumparam)},

    /* ripper specific tokens */
    {tIGNORED_NL,		O(ignored_nl)},
    {tCOMMENT,			O(comment)},
    {tEMBDOC_BEG,		O(embdoc_beg)},
    {tEMBDOC,			O(embdoc)},
    {tEMBDOC_END,		O(embdoc_end)},
    {tSP,			O(sp)},
    {tHEREDOC_BEG,		O(heredoc_beg)},
    {tHEREDOC_END,		O(heredoc_end)},
    {k__END__,			O(__end__)},
};

static ID
ripper_token2eventid(int tok)
{
    int i;

    for (i = 0; i < numberof(token_to_eventid); i++) {
	const struct token_assoc *const a = &token_to_eventid[i];
        if (a->token == tok)
            return *(const ID *)((const char *)&ripper_scanner_ids + a->id_offset);
    }
    if (tok < 256) {
        return ripper_scanner_ids.ripper_id_CHAR;
    }
    rb_raise(rb_eRuntimeError, "[Ripper FATAL] unknown token %d", tok);

    UNREACHABLE_RETURN(0);
}
