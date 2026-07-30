# frozen_string_literal: false
require_relative 'base'

class TestMkmfLog < TestMkmf
  def test_mkmf_log_is_deterministic
    %w[gcc clang].include?(RbConfig::MAKEFILE_CONFIG["CC"]) \
      or omit 'Only supported with GCC or Clang'

    have_func('non_existent_function')
    have_func('non_existent_function')

    # deterministic: ld: conftest.o: in function `t':
    # non-deterministic: ld: /path/to/ccXXXXXX.o: in function `t':
    ld1, ld2 = MKMFLOG[].scan(/^ld: .*?[.]o: in function `t':/)

    assert_equal ld1, ld2
  end
end
