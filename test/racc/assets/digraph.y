# ? detect digraph bug

class P
  token A B C D
rule
  target : a b c d
  a      : A
         |
  b      : B
         |
  c      : C
         |
  d      : D
         |
end

---- inner

  def parse
    do_parse
  end

  def next_token
    [false, '$']
  end

---- footer

P.new.parse
