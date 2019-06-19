# Copyright (c) 2012-2013 Peter Zotov  <whitequark@whitequark.org>
#              2012 Yaroslav Markin  <yaroslav@markin.net>
#              2012 Nate Gadgibalaev  <nat@xnsv.ru>
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

class Liquor::Parser
  token comma dot endtag ident integer keyword lblock lblock2 lbracket
        linterp lparen op_div op_eq op_gt op_geq op_lt op_leq op_minus
        op_mod op_mul op_neq op_not op_plus pipe plaintext rblock
        rbracket rinterp rparen string tag_ident

  prechigh
    left dot
    nonassoc op_uminus op_not
    left op_mul op_div op_mod
    left op_plus op_minus
    left op_eq op_neq op_lt op_leq op_gt op_geq
    left op_and
    left op_or
  preclow

  expect 15

  start block

rule
  block: /* empty */
      { result = [] }
    | plaintext block
      { result = [ val[0], *val[1] ] }
    | interp block
      { result = [ val[0], *val[1] ] }
    | tag block
      { result = [ val[0], *val[1] ] }

  interp:
      linterp expr rinterp
      { result = [ :interp, retag(val), val[1] ] }
    | linterp filter_chain rinterp
      { result = [ :interp, retag(val), val[1] ] }

  primary_expr:
      ident
    | lparen expr rparen
      { result = [ val[1][0], retag(val), *val[1][2..-1] ] }

  expr:
      integer
    | string
    | tuple
    | ident function_args
      { result = [ :call,   retag(val), val[0], val[1] ] }
    | expr lbracket expr rbracket
      { result = [ :index,  retag(val), val[0], val[2] ] }
    | expr dot ident function_args
      { result = [ :external, retag(val), val[0], val[2], val[3] ] }
    | expr dot ident
      { result = [ :external, retag(val), val[0], val[2], nil ] }
    | op_minus expr =op_uminus
      { result = [ :uminus, retag(val), val[1] ] }
    | op_not expr
      { result = [ :not, retag(val), val[1] ] }
    | expr op_mul expr
      { result = [ :mul, retag(val), val[0], val[2] ] }
    | expr op_div expr
      { result = [ :div, retag(val), val[0], val[2] ] }
    | expr op_mod expr
      { result = [ :mod, retag(val), val[0], val[2] ] }
    | expr op_plus expr
      { result = [ :plus, retag(val), val[0], val[2] ] }
    | expr op_minus expr
      { result = [ :minus, retag(val), val[0], val[2] ] }
    | expr op_eq expr
      { result = [ :eq, retag(val), val[0], val[2] ] }
    | expr op_neq expr
      { result = [ :neq, retag(val), val[0], val[2] ] }
    | expr op_lt expr
      { result = [ :lt, retag(val), val[0], val[2] ] }
    | expr op_leq expr
      { result = [ :leq, retag(val), val[0], val[2] ] }
    | expr op_gt expr
      { result = [ :gt, retag(val), val[0], val[2] ] }
    | expr op_geq expr
      { result = [ :geq, retag(val), val[0], val[2] ] }
    | expr op_and expr
      { result = [ :and, retag(val), val[0], val[2] ] }
    | expr op_or expr
      { result = [ :or, retag(val), val[0], val[2] ] }
    | primary_expr

  tuple:
      lbracket tuple_content rbracket
      { result = [ :tuple, retag(val), val[1].compact ] }

  tuple_content:
      expr comma tuple_content
      { result = [ val[0], *val[2] ] }
    | expr
      { result = [ val[0] ] }
    | /* empty */
      { result = [ ] }

  function_args:
      lparen function_args_inside rparen
      { result = [ :args, retag(val), *val[1] ] }

  function_args_inside:
      expr function_keywords
      { result = [ val[0], val[1][2] ] }
    | function_keywords
      { result = [ nil,    val[0][2] ] }

  function_keywords:
      keyword expr function_keywords
      { name = val[0][2].to_sym
        tail = val[2][2]
        loc  = retag([ val[0], val[1] ])

        if tail.include? name
          @errors << SyntaxError.new("duplicate keyword argument `#{val[0][2]}'",
              tail[name][1])
        end

        hash = {
          name => [ val[1][0], loc, *val[1][2..-1] ]
        }.merge(tail)

        result = [ :keywords, retag([ loc, val[2] ]), hash ]
      }
    | /* empty */
      { result = [ :keywords, nil, {} ] }

  filter_chain:
      expr pipe filter_chain_cont
      { result = [ val[0], *val[2] ].
            reduce { |tree, node| node[3][2] = tree; node }
      }

  filter_chain_cont:
      filter_call pipe filter_chain_cont
      { result = [ val[0], *val[2] ] }
    | filter_call
      { result = [ val[0] ] }

  filter_call:
      ident function_keywords
      { ident_loc = val[0][1]
        empty_args_loc = { line:  ident_loc[:line],
                           start: ident_loc[:end] + 1,
                           end:   ident_loc[:end] + 1, }
        result = [ :call, val[0][1], val[0],
                   [ :args, val[1][1] || empty_args_loc, nil, val[1][2] ] ]
      }

  tag:
      lblock ident expr tag_first_cont
      { result = [ :tag, retag(val), val[1], val[2], *reduce_tag_args(val[3][2]) ] }
    | lblock ident tag_first_cont
      { result = [ :tag, retag(val), val[1], nil,    *reduce_tag_args(val[2][2]) ] }

  # Racc cannot do lookahead across rules. I had to add states
  # explicitly to avoid S/R conflicts. You are not expected to
  # understand this.

  tag_first_cont:
      rblock
      { result = [ :cont,  retag(val), [] ] }
    | keyword tag_first_cont2
      { result = [ :cont,  retag(val), [ val[0], *val[1][2] ] ] }

  tag_first_cont2:
      rblock block lblock2 tag_next_cont
      { result = [ :cont2, val[0][1],  [ [:block, val[0][1], val[1] ], *val[3] ] ] }
    | expr tag_first_cont
      { result = [ :cont2, retag(val), [ val[0], *val[1][2] ] ] }

  tag_next_cont:
      endtag rblock
      { result = [] }
    | keyword tag_next_cont2
      { result = [ val[0], *val[1] ] }

  tag_next_cont2:
      rblock block lblock2 tag_next_cont
      { result = [ [:block, val[0][1], val[1] ], *val[3] ] }
    | expr keyword tag_next_cont3
      { result = [ val[0], val[1], *val[2] ] }

  tag_next_cont3:
      rblock block lblock2 tag_next_cont
      { result = [ [:block, val[0][1], val[1] ], *val[3] ] }
    | expr tag_next_cont
      { result = [ val[0], *val[1] ] }

---- inner
  attr_reader :errors, :ast

  def initialize(tags={})
    super()

    @errors = []
    @ast    = nil
    @tags   = tags
  end

  def success?
    @errors.empty?
  end

  def parse(string, name='(code)')
    @errors.clear
    @name = name
    @ast  = nil

    begin
      @stream = Lexer.lex(string, @name, @tags)
      @ast = do_parse
    rescue Liquor::SyntaxError => e
      @errors << e
    end

    success?
  end

  def next_token
    tok = @stream.shift
    [ tok[0], tok ] if tok
  end

  TOKEN_NAME_MAP = {
    :comma    => ',',
    :dot      => '.',
    :lblock   => '{%',
    :rblock   => '%}',
    :linterp  => '{{',
    :rinterp  => '}}',
    :lbracket => '[',
    :rbracket => ']',
    :lparen   => '(',
    :rparen   => ')',
    :pipe     => '|',
    :op_not   => '!',
    :op_mul   => '*',
    :op_div   => '/',
    :op_mod   => '%',
    :op_plus  => '+',
    :op_minus => '-',
    :op_eq    => '==',
    :op_neq   => '!=',
    :op_lt    => '<',
    :op_leq   => '<=',
    :op_gt    => '>',
    :op_geq   => '>=',
    :keyword  => 'keyword argument name',
    :kwarg    => 'keyword argument',
    :ident    => 'identifier',
  }

  def on_error(error_token_id, error_token, value_stack)
    if token_to_str(error_token_id) == "$end"
      raise Liquor::SyntaxError.new("unexpected end of program", {
        file: @name
      })
    else
      type, (loc, value) = error_token
      type = TOKEN_NAME_MAP[type] || type

      raise Liquor::SyntaxError.new("unexpected token `#{type}'", loc)
    end
  end

  def retag(nodes)
    loc = nodes.map { |node| node[1] }.compact
    first, *, last = loc
    return first if last.nil?

    {
      file:  first[:file],
      line:  first[:line],
      start: first[:start],
      end:    last[:end],
    }
  end

  def reduce_tag_args(list)
    list.each_slice(2).reduce([]) { |args, (k, v)|
      if v[0] == :block
        args << [ :blockarg, retag([ k, v ]), k, v[2] || [] ]
      else
        args << [ :kwarg,    retag([ k, v ]), k, v          ]
      end
    }
  end
