# Option `--dump`

For other argument values,
see {Option --dump}[options_md.html#label--dump-3A+Dump+Items].

For the examples here, we use this program:

```console
$ cat t.rb
puts 'Foo'
```

The supported dump items:

- `insns`: Instruction sequences:

    ```sh
    $ ruby --dump=insns t.rb
    == disasm: #<ISeq:<main>@t.rb:1 (1,0)-(1,10)> (catch: FALSE)
    0000 putself                                                          (   1)[Li]
    0001 putstring                              "Foo"
    0003 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
    0005 leave
    ```

- `parsetree`: {Abstract syntax tree}[https://en.wikipedia.org/wiki/Abstract_syntax_tree]
  (AST):

    ```console
    $ ruby --dump=parsetree t.rb
    ###########################################################
    ## Do NOT use this node dump for any purpose other than  ##
    ## debug and research.  Compatibility is not guaranteed. ##
    ###########################################################

    # @ NODE_SCOPE (line: 1, location: (1,0)-(1,10))
    # +- nd_tbl: (empty)
    # +- nd_args:
    # |   (null node)
    # +- nd_body:
    #     @ NODE_FCALL (line: 1, location: (1,0)-(1,10))*
    #     +- nd_mid: :puts
    #     +- nd_args:
    #         @ NODE_LIST (line: 1, location: (1,5)-(1,10))
    #         +- nd_alen: 1
    #         +- nd_head:
    #         |   @ NODE_STR (line: 1, location: (1,5)-(1,10))
    #         |   +- nd_lit: "Foo"
    #         +- nd_next:
    #             (null node)
    ```

- `yydebug`: Debugging information from yacc parser generator:

    ```
    $ ruby --dump=yydebug t.rb
    Starting parse
    Entering state 0
    Reducing stack by rule 1 (line 1295):
    lex_state: NONE -> BEG at line 1296
    vtable_alloc:12392: 0x0000558453df1a00
    vtable_alloc:12393: 0x0000558453df1a60
    cmdarg_stack(push): 0 at line 12406
    cond_stack(push): 0 at line 12407
    -> $$ = nterm $@1 (1.0-1.0: )
    Stack now 0
    Entering state 2
    Reading a token:
    lex_state: BEG -> CMDARG at line 9049
    Next token is token "local variable or method" (1.0-1.4: puts)
    Shifting token "local variable or method" (1.0-1.4: puts)
    Entering state 35
    Reading a token: Next token is token "string literal" (1.5-1.6: )
    Reducing stack by rule 742 (line 5567):
    $1 = token "local variable or method" (1.0-1.4: puts)
    -> $$ = nterm operation (1.0-1.4: )
    Stack now 0 2
    Entering state 126
    Reducing stack by rule 78 (line 1794):
    $1 = nterm operation (1.0-1.4: )
    -> $$ = nterm fcall (1.0-1.4: )
    Stack now 0 2
    Entering state 80
    Next token is token "string literal" (1.5-1.6: )
    Reducing stack by rule 292 (line 2723):
    cmdarg_stack(push): 1 at line 2737
    -> $$ = nterm $@16 (1.4-1.4: )
    Stack now 0 2 80
    Entering state 235
    Next token is token "string literal" (1.5-1.6: )
    Shifting token "string literal" (1.5-1.6: )
    Entering state 216
    Reducing stack by rule 607 (line 4706):
    -> $$ = nterm string_contents (1.6-1.6: )
    Stack now 0 2 80 235 216
    Entering state 437
    Reading a token: Next token is token "literal content" (1.6-1.9: "Foo")
    Shifting token "literal content" (1.6-1.9: "Foo")
    Entering state 503
    Reducing stack by rule 613 (line 4802):
    $1 = token "literal content" (1.6-1.9: "Foo")
    -> $$ = nterm string_content (1.6-1.9: )
    Stack now 0 2 80 235 216 437
    Entering state 507
    Reducing stack by rule 608 (line 4716):
    $1 = nterm string_contents (1.6-1.6: )
    $2 = nterm string_content (1.6-1.9: )
    -> $$ = nterm string_contents (1.6-1.9: )
    Stack now 0 2 80 235 216
    Entering state 437
    Reading a token:
    lex_state: CMDARG -> END at line 7276
    Next token is token "terminator" (1.9-1.10: )
    Shifting token "terminator" (1.9-1.10: )
    Entering state 508
    Reducing stack by rule 590 (line 4569):
    $1 = token "string literal" (1.5-1.6: )
    $2 = nterm string_contents (1.6-1.9: )
    $3 = token "terminator" (1.9-1.10: )
    -> $$ = nterm string1 (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 109
    Reducing stack by rule 588 (line 4559):
    $1 = nterm string1 (1.5-1.10: )
    -> $$ = nterm string (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 108
    Reading a token:
    lex_state: END -> BEG at line 9200
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 586 (line 4541):
    $1 = nterm string (1.5-1.10: )
    -> $$ = nterm strings (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 107
    Reducing stack by rule 307 (line 2837):
    $1 = nterm strings (1.5-1.10: )
    -> $$ = nterm primary (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 90
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 261 (line 2553):
    $1 = nterm primary (1.5-1.10: )
    -> $$ = nterm arg (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 220
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 270 (line 2586):
    $1 = nterm arg (1.5-1.10: )
    -> $$ = nterm arg_value (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 221
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 297 (line 2779):
    $1 = nterm arg_value (1.5-1.10: )
    -> $$ = nterm args (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 224
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 772 (line 5626):
    -> $$ = nterm none (1.10-1.10: )
    Stack now 0 2 80 235 224
    Entering state 442
    Reducing stack by rule 296 (line 2773):
    $1 = nterm none (1.10-1.10: )

    -> $$ = nterm opt_block_arg (1.10-1.10: )
    Stack now 0 2 80 235 224
    Entering state 441
    Reducing stack by rule 288 (line 2696):
    $1 = nterm args (1.5-1.10: )
    $2 = nterm opt_block_arg (1.10-1.10: )
    -> $$ = nterm call_args (1.5-1.10: )
    Stack now 0 2 80 235
    Entering state 453
    Reducing stack by rule 293 (line 2723):
    $1 = nterm $@16 (1.4-1.4: )
    $2 = nterm call_args (1.5-1.10: )
    cmdarg_stack(pop): 0 at line 2754
    -> $$ = nterm command_args (1.4-1.10: )
    Stack now 0 2 80
    Entering state 333
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 79 (line 1804):
    $1 = nterm fcall (1.0-1.4: )
    $2 = nterm command_args (1.4-1.10: )
    -> $$ = nterm command (1.0-1.10: )
    Stack now 0 2
    Entering state 81
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 73 (line 1770):
    $1 = nterm command (1.0-1.10: )
    -> $$ = nterm command_call (1.0-1.10: )
    Stack now 0 2
    Entering state 78
    Reducing stack by rule 51 (line 1659):
    $1 = nterm command_call (1.0-1.10: )
    -> $$ = nterm expr (1.0-1.10: )
    Stack now 0 2
    Entering state 75
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 39 (line 1578):
    $1 = nterm expr (1.0-1.10: )
    -> $$ = nterm stmt (1.0-1.10: )
    Stack now 0 2
    Entering state 73
    Next token is token '\n' (1.10-1.10: )
    Reducing stack by rule 8 (line 1354):
    $1 = nterm stmt (1.0-1.10: )
    -> $$ = nterm top_stmt (1.0-1.10: )
    Stack now 0 2
    Entering state 72
    Reducing stack by rule 5 (line 1334):
    $1 = nterm top_stmt (1.0-1.10: )
    -> $$ = nterm top_stmts (1.0-1.10: )
    Stack now 0 2
    Entering state 71
    Next token is token '\n' (1.10-1.10: )
    Shifting token '\n' (1.10-1.10: )
    Entering state 311
    Reducing stack by rule 769 (line 5618):
    $1 = token '\n' (1.10-1.10: )
    -> $$ = nterm term (1.10-1.10: )
    Stack now 0 2 71
    Entering state 313
    Reducing stack by rule 770 (line 5621):
    $1 = nterm term (1.10-1.10: )
    -> $$ = nterm terms (1.10-1.10: )
    Stack now 0 2 71
    Entering state 314
    Reading a token: Now at end of input.
    Reducing stack by rule 759 (line 5596):
    $1 = nterm terms (1.10-1.10: )
    -> $$ = nterm opt_terms (1.10-1.10: )
    Stack now 0 2 71
    Entering state 312
    Reducing stack by rule 3 (line 1321):
    $1 = nterm top_stmts (1.0-1.10: )
    $2 = nterm opt_terms (1.10-1.10: )
    -> $$ = nterm top_compstmt (1.0-1.10: )
    Stack now 0 2
    Entering state 70
    Reducing stack by rule 2 (line 1295):
    $1 = nterm $@1 (1.0-1.0: )
    $2 = nterm top_compstmt (1.0-1.10: )
    vtable_free:12426: p->lvtbl->args(0x0000558453df1a00)
    vtable_free:12427: p->lvtbl->vars(0x0000558453df1a60)
    cmdarg_stack(pop): 0 at line 12428
    cond_stack(pop): 0 at line 12429
    -> $$ = nterm program (1.0-1.10: )
    Stack now 0
    Entering state 1
    Now at end of input.
    Shifting token "end-of-input" (1.10-1.10: )
    Entering state 3
    Stack now 0 1 3
    Cleanup: popping token "end-of-input" (1.10-1.10: )
    Cleanup: popping nterm program (1.0-1.10: )
    ```

Additional flags can follow dump items.

- `+comment`: Add comments to AST.
- `+error-tolerant`: Parse in error-tolerant mode.
- `-optimize`: Disable optimizations for instruction sequences.
