# frozen_string_literal: false
require_relative 'base'
require 'tempfile'

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

  def test_with_target_rbconfig
    Tempfile.create(%w"rbconfig .rb", ".") do |tmp|
      tmp.puts <<~'end;'
      module RbConfig
        CONFIG = {}
        MAKEFILE_CONFIG = {}

        def self.fire_update!(key, value); end
        def self.expand(val, config = CONFIG); val; end
      end;
      ::RbConfig::CONFIG.each do |k, v|
        tmp.puts "  CONFIG[#{k.dump}] = #{v.dump}"
      end
      ::RbConfig::MAKEFILE_CONFIG.each do |k, v|
        tmp.puts "  MAKEFILE_CONFIG[#{k.dump}] = #{v.dump}"
      end
      tmp.puts "  CONFIG['testing-only'] = 'ok'"
      tmp.puts "end"
      tmp.close
      assert_separately([], ["--target-rbconfig=#{tmp.path}"], <<-'end;')
        assert_equal("ok", MakeMakefile::RbConfig::CONFIG["testing-only"])
        assert_not_equal(::RbConfig, MakeMakefile::RbConfig)
      end;
    end
  end
end
