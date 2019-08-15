
class ErrTestp

rule

target: lines
      ;

lines: line
     | lines line
     ;

line: A B C D E
    | error E
    ;

end

---- inner

def initialize
  @yydebug = false
  @q = [
    [:A, 'a'],
    # [:B, 'b'],
    [:C, 'c'],
    [:D, 'd'],
    [:E, 'e'],

    [:A, 'a'],
    [:B, 'b'],
    [:C, 'c'],
    [:D, 'd'],
    [:E, 'e'],

    [:A, 'a'],
    [:B, 'b'],
    # [:C, 'c'],
    [:D, 'd'],
    [:E, 'e'],
    [false, nil]
  ]
end

def next_token
  @q.shift
end

def on_error( t, val, values )
  $stderr.puts "error on token '#{val}'(#{t})"
end

def parse
  do_parse
end

---- footer

p = ErrTestp.new
p.parse
