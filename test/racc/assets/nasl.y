################################################################################
# Copyright (c) 2011-2014, Tenable Network Security
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
################################################################################

class Nasl::Grammar

preclow
  right ASS_EQ ADD_EQ SUB_EQ MUL_EQ DIV_EQ MOD_EQ SLL_EQ SRA_EQ SRL_EQ
  left OR
  left AND
  left CMP_LT CMP_GT CMP_EQ CMP_NE CMP_GE CMP_LE SUBSTR_EQ SUBSTR_NE REGEX_EQ REGEX_NE
  left BIT_OR
  left BIT_XOR
  left AMPERSAND
  left BIT_SRA BIT_SRL BIT_SLL
  left ADD SUB
  left MUL DIV MOD
  right NOT
  right UMINUS BIT_NOT
  right EXP
  right INCR DECR
prechigh

# Tell the parser generator that we don't wish to use the result variable in the
# action section of rules. Instead, the result of the rule will be the value of
# evaluating the action block.
options no_result_var

# Tell the parser generator that we expect one shift/reduce conflict due to the
# well-known dangling else problem. We could make the grammar solve this
# problem, but this is how the NASL YACC file solves it, so we'll follow suit.
expect 1

rule
  ##############################################################################
  # Aggregate Statements
  ##############################################################################

  start      : roots
             { val[0] }
             | /* Blank */
             { [] }
             ;

  roots      : root roots
             { [val[0]] + val[1] }
             | root
             { [val[0]] }
             ;

  root       : COMMENT export
             { c(*val) }
             | export
             { val[0] }
             | COMMENT function
             { c(*val) }
             | function
             { val[0] }
             | statement
             { val[0] }
             ;

  statement : simple
             { val[0] }
             | compound
             { val[0] }
             ;

  ##############################################################################
  # Root Statements
  ##############################################################################

  export     : EXPORT function
             { n(:Export, *val) }
             ;

  function   : FUNCTION ident LPAREN params RPAREN block
             { n(:Function, *val) }
             | FUNCTION ident LPAREN RPAREN block
             { n(:Function, *val) }
             ;

  simple     : assign
             { val[0] }
             | break
             { val[0] }
             | call
             { val[0] }
             | continue
             { val[0] }
             | decr
             { val[0] }
             | empty
             { val[0] }
             | COMMENT global
             { c(*val) }
             | global
             { val[0] }
             | import
             { val[0] }
             | include
             { val[0] }
             | incr
             { val[0] }
             | local
             { val[0] }
             | rep
             { val[0] }
             | return
             { val[0] }
             ;

  compound   : block
             { val[0] }
             | for
             { val[0] }
             | foreach
             { val[0] }
             | if
             { val[0] }
             | repeat
             { val[0] }
             | while
             { val[0] }
             ;

  ##############################################################################
  # Simple Statements
  ##############################################################################

  assign     : assign_exp SEMICOLON
             { val[0] }
             ;

  break      : BREAK SEMICOLON
             { n(:Break, *val) }
             ;

  call       : call_exp SEMICOLON
             { val[0] }
             ;

  continue   : CONTINUE SEMICOLON
             { n(:Continue, *val) }
             ;

  decr       : decr_exp SEMICOLON
             { val[0] }
             ;

  empty      : SEMICOLON
             { n(:Empty, *val) }
             ;

  global     : GLOBAL var_decls SEMICOLON
             { n(:Global, *val) }
             ;

  incr       : incr_exp SEMICOLON
             { val[0] }
             ;

  import     : IMPORT LPAREN string RPAREN SEMICOLON
             { n(:Import, *val) }
             ;

  include    : INCLUDE LPAREN string RPAREN SEMICOLON
             { n(:Include, *val) }
             ;

  local      : LOCAL var_decls SEMICOLON
             { n(:Local, *val) }
             ;

  rep        : call_exp REP expr SEMICOLON
             { n(:Repetition, *val[0..-1]) }
             ;

  return     : RETURN expr SEMICOLON
             { n(:Return, *val) }
             | RETURN ref SEMICOLON
             { n(:Return, *val) }
             | RETURN SEMICOLON
             { n(:Return, *val) }
             ;

  ##############################################################################
  # Compound Statements
  ##############################################################################

  block      : LBRACE statements RBRACE
             { n(:Block, *val) }
             | LBRACE RBRACE
             { n(:Block, *val) }
             ;

  for        : FOR LPAREN field SEMICOLON expr SEMICOLON field RPAREN statement
             { n(:For, *val) }
             ;

  foreach    : FOREACH ident LPAREN expr RPAREN statement
             { n(:Foreach, val[0], val[1], val[3], val[5]) }
             | FOREACH LPAREN ident IN expr RPAREN statement
             { n(:Foreach, val[0], val[2], val[4], val[6]) }
             ;

  if         : IF LPAREN expr RPAREN statement
             { n(:If, *val) }
             | IF LPAREN expr RPAREN statement ELSE statement
             { n(:If, *val) }
             ;

  repeat     : REPEAT statement UNTIL expr SEMICOLON
             { n(:Repeat, *val) }
             ;

  while      : WHILE LPAREN expr RPAREN statement
             { n(:While, *val) }
             ;

  ##############################################################################
  # Expressions
  ##############################################################################

  assign_exp : lval ASS_EQ expr
             { n(:Assignment, *val) }
             | lval ASS_EQ ref
             { n(:Assignment, *val) }
             | lval ADD_EQ expr
             { n(:Assignment, *val) }
             | lval SUB_EQ expr
             { n(:Assignment, *val) }
             | lval MUL_EQ expr
             { n(:Assignment, *val) }
             | lval DIV_EQ expr
             { n(:Assignment, *val) }
             | lval MOD_EQ expr
             { n(:Assignment, *val) }
             | lval SRL_EQ expr
             { n(:Assignment, *val) }
             | lval SRA_EQ expr
             { n(:Assignment, *val) }
             | lval SLL_EQ expr
             { n(:Assignment, *val) }
             ;

  call_exp   : lval LPAREN args RPAREN
             { n(:Call, *val) }
             | lval LPAREN RPAREN
             { n(:Call, *val) }
             ;

  decr_exp   : DECR lval
             { n(:Decrement, val[0]) }
             | lval DECR
             { n(:Decrement, val[0]) }
             ;

  incr_exp   : INCR lval
             { n(:Increment, val[0]) }
             | lval INCR
             { n(:Increment, val[0]) }
             ;

  expr       : LPAREN expr RPAREN
             { n(:Expression, *val) }
             | expr AND expr
             { n(:Expression, *val) }
             | NOT expr
             { n(:Expression, *val) }
             | expr OR expr
             { n(:Expression, *val) }
             | expr ADD expr
             { n(:Expression, *val) }
             | expr SUB expr
             { n(:Expression, *val) }
             | SUB expr =UMINUS
             { n(:Expression, *val) }
             | BIT_NOT expr
             { n(:Expression, *val) }
             | expr MUL expr
             { n(:Expression, *val) }
             | expr EXP expr
             { n(:Expression, *val) }
             | expr DIV expr
             { n(:Expression, *val) }
             | expr MOD expr
             { n(:Expression, *val) }
             | expr AMPERSAND expr
             { n(:Expression, *val) }
             | expr BIT_XOR expr
             { n(:Expression, *val) }
             | expr BIT_OR expr
             { n(:Expression, *val) }
             | expr BIT_SRA expr
             { n(:Expression, *val) }
             | expr BIT_SRL expr
             { n(:Expression, *val) }
             | expr BIT_SLL expr
             { n(:Expression, *val) }
             | incr_exp
             { val[0] }
             | decr_exp
             { val[0] }
             | expr SUBSTR_EQ expr
             { n(:Expression, *val) }
             | expr SUBSTR_NE expr
             { n(:Expression, *val) }
             | expr REGEX_EQ expr
             { n(:Expression, *val) }
             | expr REGEX_NE expr
             { n(:Expression, *val) }
             | expr CMP_LT expr
             { n(:Expression, *val) }
             | expr CMP_GT expr
             { n(:Expression, *val) }
             | expr CMP_EQ expr
             { n(:Expression, *val) }
             | expr CMP_NE expr
             { n(:Expression, *val) }
             | expr CMP_GE expr
             { n(:Expression, *val) }
             | expr CMP_LE expr
             { n(:Expression, *val) }
             | assign_exp
             { val[0] }
             | string
             { val[0] }
             | call_exp
             { val[0] }
             | lval
             { val[0] }
             | ip
             { val[0] }
             | int
             { val[0] }
             | undef
             { val[0] }
             | list_expr
             { val[0] }
             | array_expr
             { val[0] }
             ;

  ##############################################################################
  # Named Components
  ##############################################################################

  arg        : ident COLON expr
             { n(:Argument, *val) }
             | ident COLON ref
             { n(:Argument, *val) }
             | expr
             { n(:Argument, *val) }
             | ref
             { n(:Argument, *val) }
             ;

  kv_pair    : string COLON expr
             { n(:KeyValuePair, *val) }
             | int COLON expr
             { n(:KeyValuePair, *val) }
             | ident COLON expr
             { n(:KeyValuePair, *val) }
             | string COLON ref
             { n(:KeyValuePair, *val) }
             | int COLON ref
             { n(:KeyValuePair, *val) }
             | ident COLON ref
             { n(:KeyValuePair, *val) }
             ;

  kv_pairs   : kv_pair COMMA kv_pairs
             { [val[0]] + val[2] }
             | kv_pair COMMA
             { [val[0]] }
             | kv_pair
             { [val[0]] }
             ;

  lval       : ident indexes
             { n(:Lvalue, *val) }
             | ident
             { n(:Lvalue, *val) }
             ;

  ref        : AT_SIGN ident
             { n(:Reference, val[1]) }
             ;

  ##############################################################################
  # Anonymous Components
  ##############################################################################

  args       : arg COMMA args
             { [val[0]] + val[2] }
             | arg
             { [val[0]] }
             ;

  array_expr : LBRACE kv_pairs RBRACE
             { n(:Array, *val) }
             | LBRACE RBRACE
             { n(:Array, *val) }
             ;

  field      : assign_exp
             { val[0] }
             | call_exp
             { val[0] }
             | decr_exp
             { val[0] }
             | incr_exp
             { val[0] }
             | /* Blank */
             { nil }
             ;

  index      : LBRACK expr RBRACK
             { val[1] }
             | PERIOD ident
             { val[1] }
             ;

  indexes    : index indexes
             { [val[0]] + val[1] }
             | index
             { [val[0]] }
             ;

  list_elem  : expr
             { val[0] }
             | ref
             { val[0] }
             ;

  list_elems : list_elem COMMA list_elems
             { [val[0]] + val[2] }
             | list_elem
             { [val[0]] }
             ;

  list_expr  : LBRACK list_elems RBRACK
             { n(:List, *val) }
             | LBRACK RBRACK
             { n(:List, *val) }
             ;

  param      : AMPERSAND ident
             { n(:Parameter, val[1], 'reference') }
             | ident
             { n(:Parameter, val[0], 'value') }
             ;

  params     : param COMMA params
             { [val[0]] + val[2] }
             | param
             { [val[0]] }
             ;

  statements : statement statements
             { [val[0]] + val[1] }
             | statement
             { [val[0]] }
             ;

  var_decl   : ident ASS_EQ expr
             { n(:Assignment, *val) }
             | ident ASS_EQ ref
             { n(:Assignment, *val) }
             | ident
             { val[0] }
             ;

  var_decls  : var_decl COMMA var_decls
             { [val[0]] + val[2] }
             | var_decl
             { [val[0]] }
             ;

  ##############################################################################
  # Literals
  ##############################################################################

  ident      : IDENT
             { n(:Identifier, *val) }
             | REP
             { n(:Identifier, *val) }
             | IN
             { n(:Identifier, *val) }
             ;

  int        : INT_DEC
             { n(:Integer, *val) }
             | INT_HEX
             { n(:Integer, *val) }
             | INT_OCT
             { n(:Integer, *val) }
             | FALSE
             { n(:Integer, *val) }
             | TRUE
             { n(:Integer, *val) }
             ;

  ip         : int PERIOD int PERIOD int PERIOD int
             { n(:Ip, *val) }

  string     : DATA
             { n(:String, *val) }
             | STRING
             { n(:String, *val) }
             ;

  undef      : UNDEF
             { n(:Undefined, *val) }
             ;
end

---- header ----

require 'nasl/parser/tree'

require 'nasl/parser/argument'
require 'nasl/parser/array'
require 'nasl/parser/assigment'
require 'nasl/parser/block'
require 'nasl/parser/break'
require 'nasl/parser/call'
require 'nasl/parser/comment'
require 'nasl/parser/continue'
require 'nasl/parser/decrement'
require 'nasl/parser/empty'
require 'nasl/parser/export'
require 'nasl/parser/expression'
require 'nasl/parser/for'
require 'nasl/parser/foreach'
require 'nasl/parser/function'
require 'nasl/parser/global'
require 'nasl/parser/identifier'
require 'nasl/parser/if'
require 'nasl/parser/import'
require 'nasl/parser/include'
require 'nasl/parser/increment'
require 'nasl/parser/integer'
require 'nasl/parser/ip'
require 'nasl/parser/key_value_pair'
require 'nasl/parser/list'
require 'nasl/parser/local'
require 'nasl/parser/lvalue'
require 'nasl/parser/parameter'
require 'nasl/parser/reference'
require 'nasl/parser/repeat'
require 'nasl/parser/repetition'
require 'nasl/parser/return'
require 'nasl/parser/string'
require 'nasl/parser/undefined'
require 'nasl/parser/while'

---- inner ----

def n(cls, *args)
  begin
    Nasl.const_get(cls).new(@tree, *args)
  rescue
    puts "An exception occurred during the creation of a #{cls} instance."
    puts
    puts "The arguments passed to the constructer were:"
    puts args
    puts
    puts @tok.last.context
    puts
    raise
  end
end

def c(*args)
  n(:Comment, *args)
  args[1]
end

def on_error(type, value, stack)
  raise ParseException, "The language's grammar does not permit #{value.name} to appear here", value.context
end

def next_token
  @tok = @tkz.get_token

  if @first && @tok.first == :COMMENT
    n(:Comment, @tok.last)
    @tok = @tkz.get_token
  end
  @first = false

  return @tok
end

def parse(env, code, path)
  @first = true
  @tree = Tree.new(env)
  @tkz = Tokenizer.new(code, path)
  @tree.concat(do_parse)
end

---- footer ----
