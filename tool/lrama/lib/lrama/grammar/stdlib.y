/**********************************************************************

  stdlib.y

  This is lrama's standard library. It provides a number of
  parameterized rule definitions, such as options and lists,
  that should be useful in a number of situations.

**********************************************************************/

%%

// -------------------------------------------------------------------
// Options

/*
 * program: option(X)
 *
 * =>
 *
 * program: option_X
 * option_X: %empty
 * option_X: X
 */
%rule option(X)
                : /* empty */
                | X
                ;


/*
 * program: ioption(X)
 *
 * =>
 *
 * program: %empty
 * program: X
 */
%rule %inline ioption(X)
                : /* empty */
                | X
                ;

// -------------------------------------------------------------------
// Sequences

/*
 * program: preceded(opening, X)
 *
 * =>
 *
 * program: preceded_opening_X
 * preceded_opening_X: opening X
 */
%rule preceded(opening, X)
                : opening X { $$ = $2; }
                ;

/*
 * program: terminated(X, closing)
 *
 * =>
 *
 * program: terminated_X_closing
 * terminated_X_closing: X closing
 */
%rule terminated(X, closing)
                : X closing { $$ = $1; }
                ;

/*
 * program: delimited(opening, X, closing)
 *
 * =>
 *
 * program: delimited_opening_X_closing
 * delimited_opening_X_closing: opening X closing
 */
%rule delimited(opening, X, closing)
                : opening X closing { $$ = $2; }
                ;

// -------------------------------------------------------------------
// Lists

/*
 * program: list(X)
 *
 * =>
 *
 * program: list_X
 * list_X: %empty
 * list_X: list_X X
 */
%rule list(X)
                : /* empty */
                | list(X) X
                ;

/*
 * program: nonempty_list(X)
 *
 * =>
 *
 * program: nonempty_list_X
 * nonempty_list_X: X
 * nonempty_list_X: nonempty_list_X X
 */
%rule nonempty_list(X)
                : X
                | nonempty_list(X) X
                ;

/*
 * program: separated_nonempty_list(separator, X)
 *
 * =>
 *
 * program: separated_nonempty_list_separator_X
 * separated_nonempty_list_separator_X: X
 * separated_nonempty_list_separator_X: separated_nonempty_list_separator_X separator X
 */
%rule separated_nonempty_list(separator, X)
                : X
                | separated_nonempty_list(separator, X) separator X
                ;

/*
 * program: separated_list(separator, X)
 *
 * =>
 *
 * program: separated_list_separator_X
 * separated_list_separator_X: option_separated_nonempty_list_separator_X
 * option_separated_nonempty_list_separator_X: %empty
 * option_separated_nonempty_list_separator_X: separated_nonempty_list_separator_X
 * separated_nonempty_list_separator_X: X
 * separated_nonempty_list_separator_X: separator separated_nonempty_list_separator_X X
 */
%rule separated_list(separator, X)
                : option(separated_nonempty_list(separator, X))
                ;
