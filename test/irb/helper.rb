require "test/unit"

module TestIRB
  class TestCase < Test::Unit::TestCase
    def save_encodings
      @default_encoding = [Encoding.default_external, Encoding.default_internal]
      @stdio_encodings = [STDIN, STDOUT, STDERR].map {|io| [io.external_encoding, io.internal_encoding] }
    end

    def restore_encodings
      EnvUtil.suppress_warning do
        Encoding.default_external, Encoding.default_internal = *@default_encoding
        [STDIN, STDOUT, STDERR].zip(@stdio_encodings) do |io, encs|
          io.set_encoding(*encs)
        end
      end
    end

    def without_rdoc(&block)
      ::Kernel.send(:alias_method, :old_require, :require)

      ::Kernel.define_method(:require) do |name|
        raise LoadError, "cannot load such file -- rdoc (test)" if name.match?("rdoc") || name.match?(/^rdoc\/.*/)
        ::Kernel.send(:old_require, name)
      end

      yield
    ensure
      EnvUtil.suppress_warning { ::Kernel.send(:alias_method, :require, :old_require) }
    end
  end
end
