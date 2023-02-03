require "test/unit"
require "pathname"

begin
  require_relative "../lib/helper"
rescue LoadError # ruby/ruby defines helpers differently
end

module IRB
  class InputMethod; end
end

module TestIRB
  class TestCase < Test::Unit::TestCase
    class TestInputMethod < ::IRB::InputMethod
      attr_reader :list, :line_no

      def initialize(list = [])
        super("test")
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end
    end

    def ruby_core?
      !Pathname(__dir__).join("../../", "irb.gemspec").exist?
    end

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
      begin
        require_relative "../lib/envutil"
      rescue LoadError # ruby/ruby defines EnvUtil differently
      end
      EnvUtil.suppress_warning { ::Kernel.send(:alias_method, :require, :old_require) }
    end
  end
end
