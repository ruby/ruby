# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestEnsureAndCallcc < Test::Unit::TestCase
  def test_bug20655_dir_chdir_using_rb_ensure
    need_continuation
    called = 0
    tmp = nil
    Dir.chdir('/tmp') do
      tmp = Dir.pwd
      cont = nil
      callcc{|c| cont = c}
      assert_equal(tmp, Dir.pwd, "BUG #20655: ensure called and pwd was changed unexpectedly")
      called += 1
      cont.call if called < 10
    end
  end

  def test_bug20655_extension_using_rb_ensure
    need_continuation
    require '-test-/ensure_and_callcc'
    assert_equal(0, EnsureAndCallcc.ensure_called)
    EnsureAndCallcc.require_with_ensure(File.join(__dir__, 'required'))
    assert_equal(1, EnsureAndCallcc.ensure_called,
                 "BUG #20655: ensure called unexpectedly in the required script even without exceptions")
  end

  private
  def need_continuation
    unless respond_to?(:callcc, true)
      EnvUtil.suppress_warning {require 'continuation'}
    end
    omit 'requires callcc support' unless respond_to?(:callcc, true)
  end
end
