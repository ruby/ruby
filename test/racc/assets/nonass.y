#
# nonassoc test
#

class P

preclow
  nonassoc N
  left P
prechigh

rule

target : exp
exp    : exp N exp
       | exp P exp
       | T

end

---- inner

  def parse
    @src = [[:T,'T'], [:N,'N'], [:T,'T'], [:N,'N'], [:T,'T']]
    do_parse
  end

  def next_token
    @src.shift
  end

---- footer

begin
  P.new.parse
rescue ParseError
  exit 0
else
  $stderr.puts 'parse error not raised: nonassoc not work'
  exit 1
end
