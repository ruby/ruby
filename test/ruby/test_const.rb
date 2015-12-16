# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestConst < Test::Unit::TestCase
  TEST1 = 1
  TEST2 = 2

  module Const
    TEST3 = 3
    TEST4 = 4
  end

  module Const2
    TEST3 = 6
    TEST4 = 8
  end

  def test_const
    assert defined?(TEST1)
    assert_equal 1, TEST1
    assert defined?(TEST2)
    assert_equal 2, TEST2

    self.class.class_eval {
      include Const
    }
    assert defined?(TEST1)
    assert_equal 1, TEST1
    assert defined?(TEST2)
    assert_equal 2, TEST2
    assert defined?(TEST3)
    assert_equal 3, TEST3
    assert defined?(TEST4)
    assert_equal 4, TEST4

    self.class.class_eval {
      include Const2
    }
    STDERR.print "intentionally redefines TEST3, TEST4\n" if $VERBOSE
    assert defined?(TEST1)
    assert_equal 1, TEST1
    assert defined?(TEST2)
    assert_equal 2, TEST2
    assert defined?(TEST3)
    assert_equal 6, TEST3
    assert defined?(TEST4)
    assert_equal 8, TEST4
  end

  def test_redefinition
    c = Class.new
    name = "X\u{5b9a 6570}"
    c.const_set(name, 1)
    prev_line = __LINE__ - 1
    EnvUtil.with_default_internal(Encoding::UTF_8) do
      assert_warning(<<-WARNING) {c.const_set(name, 2)}
#{__FILE__}:#{__LINE__-1}: warning: already initialized constant #{c}::#{name}
#{__FILE__}:#{prev_line}: warning: previous definition of #{name} was here
WARNING
    end
  end

  def test_redefinition_memory_leak
    code = <<-PRE
350000.times { FOO = :BAR }
PRE
    assert_no_memory_leak(%w[-W0 -], '', code, 'redefined constant', timeout: 30)
  end
end
