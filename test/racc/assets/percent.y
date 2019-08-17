class ScannerChecker
rule
  target: A
      {
        i = 7
        i %= 4
	raise 'assert failed' unless i == 3
        tmp = %-This is percent string.-
	raise 'assert failed' unless tmp == 'This is percent string.'
        a = 5; b = 3
        assert_equal(2,(a%b))    #A
      # assert_equal(2,(a %b))   # is %-string
        assert_equal(2,(a% b))   #B
        assert_equal(2,(a % b))  #C
      }
end

---- inner ----

  def parse
    @q = [[:A, 'A'], [false, '$']]
    do_parse
  end

  def next_token
    @q.shift
  end

  def assert_equal( expect, real )
    raise "expect #{expect.inspect} but #{real.inspect}" unless expect == real
  end

---- footer ----

parser = ScannerChecker.new.parse
