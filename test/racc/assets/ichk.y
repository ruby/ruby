class Calculator

  prechigh
    left '*' '/'
    left '+' '-'
  preclow

  convert
    NUMBER 'Number'
  end

rule

  target : exp
         | /* none */ { result = 0 }

  exp    : exp '+' exp { result += val[2]; a = 'plus' }
         | exp '-' exp { result -= val[2]; a = "string test" }
         | exp '*' exp { result *= val[2] }
         | exp '/' exp { result /= val[2] }
         | '(' { $emb = true } exp ')'
             {
               raise 'must not happen' unless $emb
               result = val[2]
             }
         | '-' NUMBER  { result = -val[1] }
         | NUMBER

----header

class Number
end

----inner

  def initialize
    @racc_debug_out = $stdout
    @yydebug = false
  end

  def validate(expected, src)
    result = parse(src)
    unless result == expected
      raise "test #{@test_number} fail"
    end
    @test_number += 1
  end

  def parse(src)
    @src = src
    @test_number = 1
    yyparse self, :scan
  end

  def scan(&block)
    @src.each(&block)
  end

----footer

calc = Calculator.new

calc.validate(9, [[Number, 9], nil])

calc.validate(-3,
    [[Number, 5],
     ['*',   '*'],
     [Number, 1],
     ['-',   '*'],
     [Number, 1],
     ['*',   '*'],
     [Number, 8],
     nil])

calc.validate(-1,
    [[Number, 5],
     ['+',   '+'],
     [Number, 2],
     ['-',   '-'],
     [Number, 5],
     ['+',   '+'],
     [Number, 2],
     ['-',   '-'],
     [Number, 5],
     nil])

calc.validate(-4,
    [['-',    'UMINUS'],
     [Number, 4],
     nil])

calc.validate(40,
    [[Number, 7],
     ['*',   '*'],
     ['(',   '('],
     [Number, 4],
     ['+',   '+'],
     [Number, 3],
     [')',   ')'],
     ['-',   '-'],
     [Number, 9],
     nil])
