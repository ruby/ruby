# Copyright (c) 2011 SUSE
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

class Machete::Parser

token NIL
token TRUE
token FALSE
token INTEGER
token SYMBOL
token STRING
token REGEXP
token ANY
token EVEN
token ODD
token METHOD_NAME
token CLASS_NAME

start expression

rule

expression : primary
           | expression "|" primary {
               result = if val[0].is_a?(ChoiceMatcher)
                 ChoiceMatcher.new(val[0].alternatives << val[2])
               else
                 ChoiceMatcher.new([val[0], val[2]])
               end
             }

primary : node
        | array
        | literal
        | any

node : CLASS_NAME {
         result = NodeMatcher.new(val[0].to_sym)
       }
     | CLASS_NAME "<" attrs ">" {
         result = NodeMatcher.new(val[0].to_sym, val[2])
       }

attrs : attr
      | attrs "," attr { result = val[0].merge(val[2]) }

attr : method_name "=" expression { result = { val[0].to_sym => val[2] } }
     | method_name "^=" SYMBOL {
         result = {
           val[0].to_sym => SymbolRegexpMatcher.new(
             Regexp.new("^" + Regexp.escape(symbol_value(val[2]).to_s))
           )
         }
       }
     | method_name "$=" SYMBOL {
         result = {
           val[0].to_sym => SymbolRegexpMatcher.new(
             Regexp.new(Regexp.escape(symbol_value(val[2]).to_s) + "$")
           )
         }
       }
     | method_name "*=" SYMBOL {
         result = {
           val[0].to_sym => SymbolRegexpMatcher.new(
             Regexp.new(Regexp.escape(symbol_value(val[2]).to_s))
           )
         }
       }
     | method_name "^=" STRING {
         result = {
           val[0].to_sym => StringRegexpMatcher.new(
             Regexp.new("^" + Regexp.escape(string_value(val[2])))
           )
         }
       }
     | method_name "$=" STRING {
         result = {
           val[0].to_sym => StringRegexpMatcher.new(
             Regexp.new(Regexp.escape(string_value(val[2])) + "$")
           )
         }
       }
     | method_name "*=" STRING {
         result = {
           val[0].to_sym => StringRegexpMatcher.new(
             Regexp.new(Regexp.escape(string_value(val[2])))
           )
         }
       }
     | method_name "*=" REGEXP {
         result = {
           val[0].to_sym => IndifferentRegexpMatcher.new(
             Regexp.new(regexp_value(val[2]))
           )
         }
       }

# Hack to overcome the fact that some tokens will lex as simple tokens, not
# METHOD_NAME tokens, and that "reserved words" will lex as separate kinds of
# tokens.
method_name : METHOD_NAME
            | NIL
            | TRUE
            | FALSE
            | ANY
            | EVEN
            | ODD
            | "*"
            | "+"
            | "<"
            | ">"
            | "^"
            | "|"

array : "[" items_opt "]" { result = ArrayMatcher.new(val[1]) }

items_opt : /* empty */ { result = [] }
          | items

items : item           { result = [val[0]] }
      | items "," item { result = val[0] << val[2] }

item : expression
     | expression quantifier { result = Quantifier.new(val[0], *val[1]) }

quantifier : "*" { result = [0, nil, 1] }
           | "+" { result = [1, nil, 1] }
           | "?" { result = [0, 1, 1] }
           | "{" INTEGER "}" {
             result = [integer_value(val[1]), integer_value(val[1]), 1]
           }
           | "{" INTEGER "," "}" {
             result = [integer_value(val[1]), nil, 1]
           }
           | "{" "," INTEGER "}" {
             result = [0, integer_value(val[2]), 1]
           }
           | "{" INTEGER "," INTEGER "}" {
             result = [integer_value(val[1]), integer_value(val[3]), 1]
           }
           | "{" EVEN "}" { result = [0, nil, 2] }
           | "{" ODD "}"  { result = [1, nil, 2] }

literal : NIL     { result = LiteralMatcher.new(nil) }
        | TRUE    { result = LiteralMatcher.new(true) }
        | FALSE   { result = LiteralMatcher.new(false) }
        | INTEGER { result = LiteralMatcher.new(integer_value(val[0])) }
        | SYMBOL  { result = LiteralMatcher.new(symbol_value(val[0])) }
        | STRING  { result = LiteralMatcher.new(string_value(val[0])) }
        | REGEXP  { result = LiteralMatcher.new(regexp_value(val[0])) }

any : ANY { result = AnyMatcher.new }

---- inner

include Matchers

class SyntaxError < StandardError; end

def parse(input)
  @input = input
  @pos = 0

  do_parse
end

private

def integer_value(value)
  if value =~ /^0[bB]/
    value[2..-1].to_i(2)
  elsif value =~ /^0[oO]/
    value[2..-1].to_i(8)
  elsif value =~ /^0[dD]/
    value[2..-1].to_i(10)
  elsif value =~ /^0[xX]/
    value[2..-1].to_i(16)
  elsif value =~ /^0/
    value.to_i(8)
  else
    value.to_i
  end
end

def symbol_value(value)
  value[1..-1].to_sym
end

def string_value(value)
  quote = value[0..0]
  if quote == "'"
    value[1..-2].gsub("\\\\", "\\").gsub("\\'", "'")
  elsif quote == '"'
    value[1..-2].
      gsub("\\\\", "\\").
      gsub('\\"', '"').
      gsub("\\n", "\n").
      gsub("\\t", "\t").
      gsub("\\r", "\r").
      gsub("\\f", "\f").
      gsub("\\v", "\v").
      gsub("\\a", "\a").
      gsub("\\e", "\e").
      gsub("\\b", "\b").
      gsub("\\s", "\s").
      gsub(/\\([0-7]{1,3})/) { $1.to_i(8).chr }.
      gsub(/\\x([0-9a-fA-F]{1,2})/) { $1.to_i(16).chr }
  else
    raise "Unknown quote: #{quote.inspect}."
  end
end

REGEXP_OPTIONS = {
  'i' => Regexp::IGNORECASE,
  'm' => Regexp::MULTILINE,
  'x' => Regexp::EXTENDED
}

def regexp_value(value)
  /\A\/(.*)\/([imx]*)\z/ =~ value
  pattern, options = $1, $2

  Regexp.new(pattern, options.chars.map { |ch| REGEXP_OPTIONS[ch] }.inject(:|))
end

# "^" needs to be here because if it were among operators recognized by
# METHOD_NAME, "^=" would be recognized as two tokens.
SIMPLE_TOKENS = [
  "|",
  "<",
  ">",
  ",",
  "=",
  "^=",
  "^",
  "$=",
  "[",
  "]",
  "*=",
  "*",
  "+",
  "?",
  "{",
  "}"
]

COMPLEX_TOKENS = [
  [:NIL,   /^nil/],
  [:TRUE,  /^true/],
  [:FALSE, /^false/],
  # INTEGER needs to be before METHOD_NAME, otherwise e.g. "+1" would be
  # recognized as two tokens.
  [
    :INTEGER,
    /^
      [+-]?                               # sign
      (
        0[bB][01]+(_[01]+)*               # binary (prefixed)
        |
        0[oO][0-7]+(_[0-7]+)*             # octal (prefixed)
        |
        0[dD]\d+(_\d+)*                   # decimal (prefixed)
        |
        0[xX][0-9a-fA-F]+(_[0-9a-fA-F]+)* # hexadecimal (prefixed)
        |
        0[0-7]*(_[0-7]+)*                 # octal (unprefixed)
        |
        [1-9]\d*(_\d+)*                   # decimal (unprefixed)
      )
    /x
  ],
  [
    :SYMBOL,
    /^
      :
      (
        # class name
        [A-Z][a-zA-Z0-9_]*
        |
        # regular method name
        [a-z_][a-zA-Z0-9_]*[?!=]?
        |
        # instance variable name
        @[a-zA-Z_][a-zA-Z0-9_]*
        |
        # class variable name
        @@[a-zA-Z_][a-zA-Z0-9_]*
        |
        # operator (sorted by length, then alphabetically)
        (<=>|===|\[\]=|\*\*|\+@|-@|<<|<=|==|=~|>=|>>|\[\]|[%&*+\-\/<>^`|~])
      )
    /x
  ],
  [
    :STRING,
    /^
      (
        '                 # sinqle-quoted string
          (
            \\[\\']           # escape
            |
            [^']              # regular character
          )*
        '
        |
        "                 # double-quoted string
          (
            \\                # escape
            (
              [\\"ntrfvaebs]    # one-character escape
              |
              [0-7]{1,3}        # octal number escape
              |
              x[0-9a-fA-F]{1,2} # hexadecimal number escape
            )
            |
            [^"]              # regular character
          )*
        "
      )
    /x
  ],
  [
    :REGEXP,
    /^
      \/
        (
          \\                                          # escape
          (
            [\\\/ntrfvaebs\(\)\[\]\{\}\-\.\?\*\+\|\^\$] # one-character escape
            |
            [0-7]{2,3}                                  # octal number escape
            |
            x[0-9a-fA-F]{1,2}                           # hexadecimal number escape
          )
          |
          [^\/]                                       # regular character
        )*
      \/
      [imx]*
    /x
  ],
  # ANY, EVEN and ODD need to be before METHOD_NAME, otherwise they would be
  # recognized as method names.
  [:ANY,  /^any/],
  [:EVEN, /^even/],
  [:ODD,  /^odd/],
  # We exclude "*", "+", "<", ">", "^" and "|" from method names since they are
  # lexed as simple tokens. This is because they have also other meanings in
  # Machette patterns beside Ruby method names.
  [
    :METHOD_NAME,
    /^
      (
        # regular name
        [a-z_][a-zA-Z0-9_]*[?!=]?
        |
        # operator (sorted by length, then alphabetically)
        (<=>|===|\[\]=|\*\*|\+@|-@|<<|<=|==|=~|>=|>>|\[\]|[%&\-\/`~])
      )
    /x
  ],
  [:CLASS_NAME, /^[A-Z][a-zA-Z0-9_]*/]
]

def next_token
  skip_whitespace

  return false if remaining_input.empty?

  # Complex tokens need to be before simple tokens, otherwise e.g. "<<" would be
  # recognized as two tokens.

  COMPLEX_TOKENS.each do |type, regexp|
    if remaining_input =~ regexp
      @pos += $&.length
      return [type, $&]
    end
  end

  SIMPLE_TOKENS.each do |token|
    if remaining_input[0...token.length] == token
      @pos += token.length
      return [token, token]
    end
  end

  raise SyntaxError, "Unexpected character: #{remaining_input[0..0].inspect}."
end

def skip_whitespace
  if remaining_input =~ /\A^[ \t\r\n]+/
    @pos += $&.length
  end
end

def remaining_input
  @input[@pos..-1]
end

def on_error(error_token_id, error_value, value_stack)
  raise SyntaxError, "Unexpected token: #{error_value.inspect}."
end
