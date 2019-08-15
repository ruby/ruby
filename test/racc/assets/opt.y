#
# check options working
#

class Calcp

  prechigh
    left '*' '/'
    left '+' '-'
  preclow

  convert
    NUMBER 'Number'
  end

  options no_omit_action_call no_result_var

rule

  target : exp | /* none */ { 0 } ;

  exp    : exp '+' exp { chk(val[0] + val[2]) }
         | exp '-' exp { chk(val[0] - val[2]) }
         | exp '*' exp { chk(val[0] * val[2]) }
         | exp '/' exp { chk(val[0] / val[2]) }
         | '(' { $emb = true } exp ')'
             {
               raise 'must not happen' unless $emb
               val[2]
             }
         | '-' NUMBER  { -val[1] }
         | NUMBER
         ;

end

----header

class Number; end

----inner

  def parse( src )
    @src = src
    do_parse
  end

  def next_token
    @src.shift
  end

  def initialize
    @yydebug = true
  end

  def chk( i )
    # p i
    i
  end

----footer

$parser = Calcp.new
$test_number = 1

def chk( src, ans )
  result = $parser.parse(src)
  raise "test #{$test_number} failed" unless result == ans
  $test_number += 1
end

chk(
  [ [Number, 9],
    [false, false],
    [false, false] ], 9
)

chk(
  [ [Number, 5],
    ['*', nil],
    [Number, 1],
    ['-', nil],
    [Number, 1],
    ['*', nil],
    [Number, 8],
    [false, false],
    [false, false] ], -3
)

chk(
  [ [Number, 5],
    ['+', nil],
    [Number, 2],
    ['-', nil],
    [Number, 5],
    ['+', nil],
    [Number, 2],
    ['-', nil],
    [Number, 5],
    [false, false],
    [false, false] ], -1
)

chk(
  [ ['-', nil],
    [Number, 4],
    [false, false],
    [false, false] ], -4
)

chk(
  [ [Number, 7],
    ['*', nil],
    ['(', nil],
    [Number, 4],
    ['+', nil],
    [Number, 3],
    [')', nil],
    ['-', nil],
    [Number, 9],
    [false, false],
    [false, false] ], 40
)
