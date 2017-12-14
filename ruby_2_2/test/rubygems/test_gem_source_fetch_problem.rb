require 'rubygems/test_case'

class TestGemSourceFetchProblem < Gem::TestCase

  def test_exception
    source = Gem::Source.new @gem_repo
    error  = RuntimeError.new 'test'

    sf = Gem::SourceFetchProblem.new source, error

    e = assert_raises RuntimeError do
      raise sf
    end

    assert_equal 'test', e.message
  end

end

