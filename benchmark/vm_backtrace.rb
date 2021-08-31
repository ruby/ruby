# get last backtrace

begin
  caller(0, 0)
rescue ArgumentError
  alias caller_orig caller
  def caller lev, n
    caller_orig(lev)[0..n]
  end
end

def rec n
  if n < 0
    100_000.times{
      caller(0, 1)
    }
  else
    rec(n-1)
  end
end

rec 50
