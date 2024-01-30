/**********************************************************************

  stdlib.y

  This is lrama's standard library. It provides a number of
  parameterizing rule definitions, such as options and lists,
  that should be useful in a number of situations.

**********************************************************************/

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
