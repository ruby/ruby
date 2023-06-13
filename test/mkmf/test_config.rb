# frozen_string_literal: false
require_relative 'base'

class TestMkmfConfig < TestMkmf
  def test_dir_config
    bug8074 = '[Bug #8074]'
    lib = RbConfig.expand(RbConfig::MAKEFILE_CONFIG["libdir"], "exec_prefix"=>"/test/foo")
    assert_separately([], %w[--with-foo-dir=/test/foo], <<-"end;")
      assert_equal(%w[/test/foo/include #{lib}], dir_config("foo"), #{bug8074.dump})
    end;
  end

  def test_with_config_with_arg_and_value
    assert_separately([], %w[--with-foo=bar], <<-'end;')
      assert_equal("bar", with_config("foo"))
    end;
  end

  def test_with_config_with_arg_and_no_value
    assert_separately([], %w[--with-foo], <<-'end;')
      assert_equal(true, with_config("foo"))
    end;
  end

  def test_with_config_without_arg
    assert_separately([], %w[--without-foo], <<-'end;')
      assert_equal(false, with_config("foo"))
    end;
  end
end
