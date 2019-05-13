class P

rule

  a: A
      {
        # comment test

        # comment test

        # string
        @sstring = 'squote string'
        @dstring = 'dquote string'

        # regexp
        @regexp  = /some regexp with spaces/

        # gvar
        /regexp/ === 'some regexp matches to this string'
        @pre_match = $`
        @matched = $&
        @post_match = $'
        @m = $~

        # braces
        @array = []
        [1,2,3].each {|i|
          @array.push i
        }
        3.times { @array.push 10 }
      }

end

---- inner

  def parse
    @sstring = @dstring = nil
    @regexp = nil
    @pre_match = @matched = @post_match = @m = nil

    @src = [[:A, 'A'], [false, '$']]
    do_parse

    assert_equal 'squote string', @sstring
    assert_equal 'dquote string', @dstring
    assert_equal(/some regexp with spaces/, @regexp)
    assert_equal 'some ', @pre_match
    assert_equal 'regexp', @matched
    assert_equal ' matches to this string', @post_match
    assert_instance_of MatchData, @m
  end

  def assert_equal(ok, data)
    unless ok == data
      raise "expected <#{ok.inspect}> but is <#{data.inspect}>"
    end
  end

  def assert_instance_of(klass, obj)
    unless obj.instance_of?(klass)
      raise "expected #{klass} but is #{obj.class}"
    end
  end

  def next_token
    @src.shift
  end

---- footer

P.new.parse
