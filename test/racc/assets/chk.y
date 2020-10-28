#
# racc tester
#

class Calcp

  prechigh
    left '*' '/'
    left '+' '-'
  preclow

  convert
    NUMBER 'Number'
  end

rule

  target : exp | /* none */ { result = 0 } ;

  exp    : exp '+' exp { result += val[2]; @plus = 'plus' }
         | exp '-' exp { result -= val[2]; @str = "string test" }
         | exp '*' exp { result *= val[2] }
         | exp '/' exp { result /= val[2] }
         | '(' { $emb = true } exp ')'
             {
               raise 'must not happen' unless $emb
               result = val[2]
             }
         | '-' NUMBER  { result = -val[1] }
         | NUMBER
         ;

end

----header

class Number; end

----inner

  def parse( src )
    $emb = false
    @plus = nil
    @str = nil
    @src = src
    result = do_parse
    if @plus
      raise 'string parse failed' unless @plus == 'plus'
    end
    if @str
      raise 'string parse failed' unless @str == 'string test'
    end
    result
  end

  def next_token
    @src.shift
  end

  def initialize
    @yydebug = true
  end

----footer

$parser = Calcp.new
$test_number = 1

def chk( src, ans )
  result = $parser.parse(src)
  raise "test #{$test_number} fail" unless result == ans
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
