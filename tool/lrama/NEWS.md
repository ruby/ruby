# NEWS for Lrama

## Lrama 0.6.4 (2024-03-22)

### Parameterizing rules (preceded, terminated, delimited)

Support `preceded`, `terminated` and `delimited` rules.

```
program: preceded(opening, X)

// Expanded to

program: preceded_opening_X
preceded_opening_X: opening X
```

```
program: terminated(X, closing)

// Expanded to

program: terminated_X_closing
terminated_X_closing: X closing
```

```
program: delimited(opening, X, closing)

// Expanded to

program: delimited_opening_X_closing
delimited_opening_X_closing: opening X closing
```

https://github.com/ruby/lrama/pull/382

### Support `%destructor` declaration

User can set codes for freeing semantic value resources by using `%destructor`.
In general, these resources are freed by actions or after parsing.
However if syntax error happens in parsing, these codes may not be executed.
Codes associated to `%destructor` are executed when semantic value is popped from the stack by an error.

```
%token <val1> NUM
%type <val2> expr2
%type <val3> expr

%destructor {
    printf("destructor for val1: %d\n", $$);
} <val1> // printer for TAG

%destructor {
    printf("destructor for val2: %d\n", $$);
} <val2>

%destructor {
    printf("destructor for expr: %d\n", $$);
} expr // printer for symbol
```

Bison supports this feature from 1.75b.

https://github.com/ruby/lrama/pull/385

## Lrama 0.6.3 (2024-02-15)

### Bring Your Own Stack

Provide functionalities for Bring Your Own Stack.

Ruby’s Ripper library requires their own semantic value stack to manage Ruby Objects returned by user defined callback method. Currently Ripper uses semantic value stack (`yyvsa`) which is used by parser to manage Node. This hack introduces some limitation on Ripper. For example, Ripper can not execute semantic analysis depending on Node structure.

Lrama introduces two features to support another semantic value stack by parser generator users.

1. Callback entry points

User can emulate semantic value stack by these callbacks.
Lrama provides these five callbacks. Registered functions are called when each event happen. For example %after-shift function is called when shift happens on original semantic value stack.

* `%after-shift` function_name
* `%before-reduce` function_name
* `%after-reduce` function_name
* `%after-shift-error-token` function_name
* `%after-pop-stack` function_name

2. `$:n` variable to access index of each grammar symbols

User also needs to access semantic value of their stack in grammar action. `$:n` provides the way to access to it. `$:n` is translated to the minus index from the top of the stack.
For example

```
primary: k_if expr_value then compstmt if_tail k_end
          {
          /*% ripper: if!($:2, $:4, $:5) %*/
          /* $:2 = -5, $:4 = -3, $:5 = -2. */
          }
```

https://github.com/ruby/lrama/pull/367

## Lrama 0.6.2 (2024-01-27)

### %no-stdlib directive

If `%no-stdlib` directive is set, Lrama doesn't load Lrama standard library for
parameterizing rules, stdlib.y.

https://github.com/ruby/lrama/pull/344

## Lrama 0.6.1 (2024-01-13)

### Nested parameterizing rules

Allow to pass an instantiated rule to other parameterizing rules.

```
%rule constant(X) : X
                  ;

%rule option(Y) : /* empty */
                | Y
                ;

%%

program         : option(constant(number)) // Nested rule
                ;
%%
```

Allow to use nested parameterizing rules when define parameterizing rules.

```
%rule option(x) : /* empty */
                | X
                ;

%rule double(Y) : Y Y
                ;

%rule double_opt(A) : option(double(A)) // Nested rule
                    ;

%%

program         : double_opt(number)
                ;

%%
```

https://github.com/ruby/lrama/pull/337

## Lrama 0.6.0 (2023-12-25)

### User defined parameterizing rules

Allow to define parameterizing rule by `%rule` directive.

```
%rule pair(X, Y): X Y { $$ = $1 + $2; }
                ;

%%

program: stmt
       ;

stmt: pair(ODD, EVEN) <num>
    | pair(EVEN, ODD) <num>
    ;
```

https://github.com/ruby/lrama/pull/285

## Lrama 0.5.11 (2023-12-02)

### Type specification of parameterizing rules

Allow to specify type of rules by specifying tag, `<i>` in below example.
Tag is post-modification style.

```
%union {
    int i;
}

%%

program         : option(number) <i>
                | number_alias? <i>
                ;
```

https://github.com/ruby/lrama/pull/272


## Lrama 0.5.10 (2023-11-18)

### Parameterizing rules (option, nonempty_list, list)

Support function call style parameterizing rules for `option`, `nonempty_list` and `list`.

https://github.com/ruby/lrama/pull/197

### Parameterizing rules (separated_list)

Support `separated_list` and `separated_nonempty_list` parameterizing rules.

```
program: separated_list(',', number)

// Expanded to

program: separated_list_number
separated_list_number: ε
separated_list_number: separated_nonempty_list_number
separated_nonempty_list_number: number
separated_nonempty_list_number: separated_nonempty_list_number ',' number
```

```
program: separated_nonempty_list(',', number)

// Expanded to

program: separated_nonempty_list_number
separated_nonempty_list_number: number
separated_nonempty_list_number: separated_nonempty_list_number ',' number
```

https://github.com/ruby/lrama/pull/204

## Lrama 0.5.9 (2023-11-05)

### Parameterizing rules (suffix)

Parameterizing rules are template of rules.
It's very common pattern to write "list" grammar rule like:

```
opt_args: /* none */
        | args
        ;

args: arg
    | args arg
```

Lrama supports these suffixes:

* `?`: option
* `+`: nonempty list
* `*`: list

Idea of Parameterizing rules comes from Menhir LR(1) parser generator (https://gallium.inria.fr/~fpottier/menhir/manual.html#sec32).

https://github.com/ruby/lrama/pull/181

## Lrama 0.5.7 (2023-10-23)

### Racc parser

Replace Lrama's parser from hand written parser to LR parser generated by Racc.
Lrama uses `--embedded` option to generate LR parser because Racc is changed from default gem to bundled gem by Ruby 3.3 (https://github.com/ruby/lrama/pull/132).

https://github.com/ruby/lrama/pull/62

## Lrama 0.5.4 (2023-08-17)

### Runtime configuration for error recovery

Meke error recovery function configurable on runtime by two new macros.

* `YYMAXREPAIR`: Expected to return max length of repair operations. `%parse-param` is passed to this function.
* `YYERROR_RECOVERY_ENABLED`: Expected to return bool value to determine error recovery is enabled or not. `%parse-param` is passed to this function.

https://github.com/ruby/lrama/pull/74

## Lrama 0.5.3 (2023-08-05)

### Error Recovery

Support token insert base Error Recovery.
`-e` option is needed to generate parser with error recovery functions.

https://github.com/ruby/lrama/pull/44

## Lrama 0.5.2 (2023-06-14)

### Named References

Instead of positional references like `$1` or `$$`,
named references allow to access to symbol by name.

```
primary: k_class cpath superclass bodystmt k_end
           {
             $primary = new_class($cpath, $bodystmt, $superclass);
           }
```

Alias name can be declared.

```
expr[result]: expr[ex-left] '+' expr[ex.right]
                {
                  $result = $[ex-left] + $[ex.right];
                }
```

Bison supports this feature from 2.5.

### Add parse params to some macros and functions

`%parse-param` are added to these macros and functions to remove ytab.sed hack from Ruby.

* `YY_LOCATION_PRINT`
* `YY_SYMBOL_PRINT`
* `yy_stack_print`
* `YY_STACK_PRINT`
* `YY_REDUCE_PRINT`
* `yysyntax_error`

https://github.com/ruby/lrama/pull/40

See also: https://github.com/ruby/ruby/pull/7807

## Lrama 0.5.0 (2023-05-17)

### stdin mode

When `-` is given as grammar file name, reads the grammar source from STDIN, and takes the next argument as the input file name. This mode helps pre-process a grammar source.

https://github.com/ruby/lrama/pull/8

## Lrama 0.4.0 (2023-05-13)

This is the first version migrated to Ruby.
This version generates "parse.c" compatible with Bison 3.8.2.
