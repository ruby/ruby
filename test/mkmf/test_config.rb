# frozen_string_literal: false
$extmk = true

require 'test/unit'
require 'mkmf'

class TestMkmfConfig < Test::Unit::TestCase
  def test_dir_config
    bug8074 = '[Bug #8074]'
    lib = RbConfig.expand(RbConfig::MAKEFILE_CONFIG["libdir"], "exec_prefix"=>"/test/foo")
    assert_separately %w[-rmkmf - -- --with-foo-dir=/test/foo], %{
      assert_equal(%w[/test/foo/include #{lib}], dir_config("foo"), #{bug8074.dump})
    }
  end
end
