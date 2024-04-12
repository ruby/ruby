/**********************************************************************

  stdlib.y

  This is lrama's standard library. It provides a number of
  parameterizing rule definitions, such as options and lists,
  that should be useful in a number of situations.

**********************************************************************/

// -------------------------------------------------------------------
// Options

/*
 * program: option(number)
 *
 * =>
 *
 * program: option_number
 * option_number: %empty
 * option_number: number
 */
%rule option(X): /* empty */
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
%rule preceded(opening, X): opening X { $$ = $2; }
                          ;

/*
 * program: terminated(X, closing)
 *
 * =>
 *
 * program: terminated_X_closing
 * terminated_X_closing: X closing
 */
%rule terminated(X, closing): X closing { $$ = $1; }
                            ;

/*
 * program: delimited(opening, X, closing)
 *
 * =>
 *
 * program: delimited_opening_X_closing
 * delimited_opening_X_closing: opening X closing
 */
%rule delimited(opening, X, closing): opening X closing { $$ = $2; }
                                     ;

// -------------------------------------------------------------------
// Lists

/*
 * program: list(number)
 *
 * =>
 *
 * program: list_number
 * list_number: %empty
 * list_number: list_number number
 */
%rule list(X): /* empty */
             | list(X) X
             ;

/*
 * program: nonempty_list(number)
 *
 * =>
 *
 * program: nonempty_list_number
 * nonempty_list_number: number
 * nonempty_list_number: nonempty_list_number number
 */
%rule nonempty_list(X): X
                      | nonempty_list(X) X
                      ;

/*
 * program: separated_nonempty_list(comma, number)
 *
 * =>
 *
 * program: separated_nonempty_list_comma_number
 * separated_nonempty_list_comma_number: number
 * separated_nonempty_list_comma_number: separated_nonempty_list_comma_number comma number
 */
%rule separated_nonempty_list(separator, X): X
                                           | separated_nonempty_list(separator, X) separator X
                                           ;

/*
 * program: separated_list(comma, number)
 *
 * =>
 *
 * program: separated_list_comma_number
 * separated_list_comma_number: option_separated_nonempty_list_comma_number
 * option_separated_nonempty_list_comma_number: %empty
 * option_separated_nonempty_list_comma_number: separated_nonempty_list_comma_number
 * separated_nonempty_list_comma_number: number
 * separated_nonempty_list_comma_number: comma separated_nonempty_list_comma_number number
 */
%rule separated_list(separator, X): option(separated_nonempty_list(separator, X))
                                  ;

%%

%union{};
