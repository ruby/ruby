# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemSourceFetchProblem < Gem::TestCase
  def test_exception
    source = Gem::Source.new @gem_repo
    error  = RuntimeError.new 'test'

    sf = Gem::SourceFetchProblem.new source, error

    e = assert_raise RuntimeError do
      raise sf
    end

    assert_equal 'test', e.message
  end

  def test_password_redacted
    source = Gem::Source.new 'https://username:secret@gemsource.com'
    error  = RuntimeError.new 'test'

    sf = Gem::SourceFetchProblem.new source, error

    refute_match sf.wordy, 'secret'
  end
end
