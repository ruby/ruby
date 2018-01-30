# frozen_string_literal: true
require 'test/unit'

class TestFuncall < Test::Unit::TestCase
  require '-test-/funcall'

  def test_funcall_extra_args
    assert_equal 'TestFuncall', TestFuncall.extra_args_name,
	 '[ruby-core:85266] [Bug #14425]'
  end
end
