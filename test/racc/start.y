class S

start st

rule

n: D { result = 'no' }
st : A B C n { result = 'ok' }

end

---- inner

  def parse
    do_parse
  end

---- footer

S.new.parse == 'ok' or raise 'start stmt not worked'
