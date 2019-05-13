# Copyright (c) 2014 James Harton
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Huia::Parser

  token
    IDENTIFIER EQUAL PLUS MINUS ASTERISK FWD_SLASH COLON FLOAT INTEGER STRING
    EXPO INDENT OUTDENT OPAREN CPAREN DOT SIGNATURE NL EOF PIPE COMMA NIL TRUE
    FALSE EQUALITY CALL SELF CONSTANT CHAR DOUBLE_TICK_STRING
    DOUBLE_TICK_STRING_END INTERPOLATE_START INTERPOLATE_END BOX LSQUARE
    RSQUARE FACES LFACE RFACE BANG TILDE RETURN NOT_EQUALITY OR AND GT LT
    GTE LTE AT

  prechigh
    left EXPO
    left BANG TILDE
    left ASTERISK FWD_SLASH PERCENT
    left PLUS MINUS

    right EQUAL
  preclow

  rule
    statements:   statement
                | statements statement             { return scope }

    statement:  expr eol                           { return scope.append val[0] }
              | expr                               { return scope.append val[0] }
              | eol                                { return scope }

    eol:        NL | EOF
    nlq:        NL |

    expr:        literal
               | grouped_expr
               | binary_op
               | unary_op
               | method_call
               | constant
               | variable
               | array
               | hash
               | return

    return:            return_expr
                     | return_nil
    return_expr:       RETURN expr                      { return n(:Return, val[1]) }
    return_nil:        RETURN                           { return n(:Return, n(:Nil)) }

    array:             empty_array
                     | array_list

    empty_array:       BOX                              { return n :Array }

    array_list:        LSQUARE array_items RSQUARE      { return val[1] }
    array_items:       expr                             { return n :Array, [val[0]] }
                     | array_items COMMA expr           { val[0].append(val[2]); return val[0] }

    hash:              empty_hash
                     | hash_list
    empty_hash:        FACES                            { return n :Hash }
    hash_list:         LFACE hash_items RFACE           { return val[1] }
    hash_items:        hash_item                        { return n :Hash, val[0] }
                     | hash_items COMMA hash_item       { val[0].append(val[2]); return val[0] }
    hash_item:         expr COLON expr                  { return n :HashItem, val[0], val[2] }

    constant:          CONSTANT                         { return constant val[0] }

    indented:          indented_w_stmts
                     | indented_w_expr
                     | indented_wo_stmts
    indented_w_stmts:  indent statements outdent        { return val[0] }
    indented_w_expr:   indent expr outdent              { return val[0].append(val[1]) }
    indented_wo_stmts: indent outdent                   { return val[0] }
    outdent:           OUTDENT { return pop_scope }


    indent_w_args:     indent_pipe indent_args PIPE nlq INDENT { return val[0] }
    indent_pipe:       PIPE   { return push_scope }
    indent_wo_args:    INDENT { return push_scope }
    indent:            indent_w_args
                     | indent_wo_args

    indent_args:       indent_arg
                     | indent_args COMMA indent_arg
    indent_arg:        arg_var                             { return scope.add_argument val[0] }
                     | arg_var EQUAL expr                  { return n :Assignment, val[0], val[2] }
    arg_var:           IDENTIFIER                          { return n :Variable, val[0] }

    method_call:            method_call_on_object
                          | method_call_on_self
                          | method_call_on_closure
    method_call_on_object:  expr DOT call_signature        { return n :MethodCall, val[0], val[2] }
                          | expr DOT IDENTIFIER            { return n :MethodCall, val[0], n(:CallSignature, val[2]) }
    method_call_on_self:    call_signature                 { return n :MethodCall, scope_instance, val[0] }

    method_call_on_closure: AT call_signature              { return n :MethodCall, this_closure, val[1] }
                          | AT IDENTIFIER                  { return n :MethodCall, this_closure, n(:CallSignature, val[1]) }

    call_signature:         call_arguments
                          | call_simple_name
    call_simple_name:       CALL                           { return n :CallSignature, val[0] }
    call_argument:          SIGNATURE call_passed_arg      { return n :CallSignature, val[0], [val[1]] }
    call_passed_arg:        call_passed_simple
                          | call_passed_indented
    call_passed_simple:     expr
                          | expr NL
    call_passed_indented:   indented
                          | indented NL
    call_arguments:         call_argument                  { return val[0] }
                          | call_arguments call_argument   { return val[0].concat_signature val[1] }

    grouped_expr: OPAREN expr CPAREN            { return n :Expression, val[1] }

    variable:  IDENTIFIER                       { return allocate_local val[0] }

    binary_op: assignment
             | addition
             | subtraction
             | multiplication
             | division
             | exponentiation
             | modulo
             | equality
             | not_equality
             | logical_or
             | logical_and
             | greater_than
             | less_than
             | greater_or_eq
             | less_or_eq

    assignment:     IDENTIFIER EQUAL expr  { return allocate_local_assignment val[0], val[2] }
    addition:       expr PLUS expr         { return binary val[0], val[2], 'plus:' }
    subtraction:    expr MINUS expr        { return binary val[0], val[2], 'minus:' }
    multiplication: expr ASTERISK expr     { return binary val[0], val[2], 'multiplyBy:' }
    division:       expr FWD_SLASH expr    { return binary val[0], val[2], 'divideBy:' }
    exponentiation: expr EXPO expr         { return binary val[0], val[2], 'toThePowerOf:' }
    modulo:         expr PERCENT expr      { return binary val[0], val[2], 'moduloOf:' }
    equality:       expr EQUALITY expr     { return binary val[0], val[2], 'isEqualTo:' }
    not_equality:   expr NOT_EQUALITY expr { return binary val[0], val[2], 'isNotEqualTo:' }
    logical_or:     expr OR expr           { return binary val[0], val[2], 'logicalOr:' }
    logical_and:    expr AND expr          { return binary val[0], val[2], 'logicalAnd:' }
    greater_than:   expr GT expr           { return binary val[0], val[2], 'isGreaterThan:' }
    less_than:      expr LT expr           { return binary val[0], val[2], 'isLessThan:' }
    greater_or_eq:  expr GTE expr          { return binary val[0], val[2], 'isGreaterOrEqualTo:' }
    less_or_eq:     expr LTE expr          { return binary val[0], val[2], 'isLessOrEqualTo:' }

    unary_op:  unary_not
             | unary_plus
             | unary_minus
             | unary_complement

    unary_not:        BANG  expr { return unary val[1], 'unaryNot' }
    unary_plus:       PLUS  expr { return unary val[1], 'unaryPlus' }
    unary_minus:      MINUS expr { return unary val[1], 'unaryMinus' }
    unary_complement: TILDE expr { return unary val[1], 'unaryComplement' }

    literal:   integer
             | float
             | string
             | nil
             | true
             | false
             | self

    float:          FLOAT                       { return n :Float,   val[0] }
    integer:        INTEGER                     { return n :Integer, val[0] }
    nil:            NIL                         { return n :Nil }
    true:           TRUE                        { return n :True }
    false:          FALSE                       { return n :False }
    self:           SELF                        { return n :Self }

    string:         STRING                      { return n :String,  val[0] }
                  | interpolated_string
                  | empty_string

    interpolated_string: DOUBLE_TICK_STRING interpolated_string_contents DOUBLE_TICK_STRING_END { return val[1] }
    interpolation:       INTERPOLATE_START expr INTERPOLATE_END { return val[1] }
    interpolated_string_contents:   interpolated_string_chunk   { return n :InterpolatedString, val[0] }
                                  | interpolated_string_contents interpolated_string_chunk { val[0].append(val[1]); return val[0] }
    interpolated_string_chunk:   chars         { return val[0] }
                               | interpolation { return to_string(val[0]) }
    empty_string: DOUBLE_TICK_STRING DOUBLE_TICK_STRING_END { return n :String, '' }

    chars:   CHAR       { return n :String, val[0] }
           | chars CHAR { val[0].append(val[1]); return val[0] }
end

---- inner

attr_accessor :lexer, :scopes, :state

def initialize lexer
  @lexer  = lexer
  @state  = []
  @scopes = []
  push_scope
end

def ast
  @ast ||= do_parse
  @scopes.first
end

def on_error t, val, vstack
  line = lexer.line
  col  = lexer.column
  message = "Unexpected #{token_to_str t} at #{lexer.filename} line #{line}:#{col}:\n\n"

  start = line - 5 > 0 ? line - 5 : 0
  i_size = line.to_s.size
  (start..(start + 5)).each do |i|
    message << sprintf("\t%#{i_size}d: %s\n", i, lexer.get_line(i))
    message << "\t#{' ' * i_size}  #{'-' * (col - 1)}^\n" if i == line
  end

  raise SyntaxError, message
end

def next_token
  nt = lexer.next_computed_token
  # just use a state stack for now, we'll have to do something
  # more sophisticated soon.
  if nt && nt.first == :state
    if nt.last
      state.push << nt.last
    else
      state.pop
    end
    next_token
  else
    nt
  end
end

def push_scope
  new_scope = Huia::AST::Scope.new scope
  new_scope.file   = lexer.filename
  new_scope.line   = lexer.line
  new_scope.column = lexer.column
  scopes.push new_scope
  new_scope
end

def pop_scope
  scopes.pop
end

def scope
  scopes.last
end

def binary left, right, method
  node(:MethodCall, left, node(:CallSignature, method, [right]))
end

def unary left, method
  node(:MethodCall, left, node(:CallSignature, method))
end

def node type, *args
  Huia::AST.const_get(type).new(*args).tap do |n|
    n.file   = lexer.filename
    n.line   = lexer.line
    n.column = lexer.column
  end
end
alias n node

def allocate_local name
  node(:Variable, name).tap do |n|
    scope.allocate_local n
  end
end

def allocate_local_assignment name, value
  node(:Assignment, name, value).tap do |n|
    scope.allocate_local n
  end
end

def this_closure
  allocate_local('@')
end

def scope_instance
  node(:ScopeInstance, scope)
end

def constant name
  return scope_instance if name == 'self'
  node(:Constant, name)
end

def to_string expr
  node(:MethodCall, expr, node(:CallSignature, 'toString'))
end
