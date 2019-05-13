#
# yyerror/yyerrok/yyaccept test
#

class A
rule

target: a b c

a:
    {
      yyerror
      raise ArgumentError, "yyerror failed"
    }
 | error

b:
    {
      yyerrok
    }

c:
    {
      yyaccept
      raise ArgumentError, "yyaccept failed"
    }

end

---- inner

  def parse
    do_parse
  end

  def next_token
    [false, '$end']
  end

  def on_error( *args )
    $stderr.puts "on_error called: args=#{args.inspect}"
  end

---- footer

A.new.parse
