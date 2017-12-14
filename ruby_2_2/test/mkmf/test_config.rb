$extmk = true

require 'test/unit'
require 'mkmf'

class TestMkmf < Test::Unit::TestCase
  class TestConfig < Test::Unit::TestCase
    def test_dir_config
      bug8074 = '[Bug #8074]'
      lib = RbConfig.expand(RbConfig::MAKEFILE_CONFIG["libdir"], "exec_prefix"=>"")
      assert_separately %w[-rmkmf - -- --with-foo-dir=/test/foo], %{
        assert_equal(%w[/test/foo/include /test/foo#{lib}], dir_config("foo"), #{bug8074.dump})
      }
    end
  end
end
