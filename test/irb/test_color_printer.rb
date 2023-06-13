# frozen_string_literal: false
require 'irb/color_printer'
require 'rubygems'
require 'stringio'

require_relative "helper"

module TestIRB
  class ColorPrinterTest < TestCase
    CLEAR     = "\e[0m"
    BOLD      = "\e[1m"
    RED       = "\e[31m"
    GREEN     = "\e[32m"
    BLUE      = "\e[34m"
    CYAN      = "\e[36m"

    def setup
      super
      if IRB.respond_to?(:conf)
        @colorize, IRB.conf[:USE_COLORIZE] = IRB.conf[:USE_COLORIZE], true
      end
      @get_screen_size = Reline.method(:get_screen_size)
      Reline.instance_eval { undef :get_screen_size }
      def Reline.get_screen_size
        [36, 80]
      end
    end

    def teardown
      Reline.instance_eval { undef :get_screen_size }
      Reline.define_singleton_method(:get_screen_size, @get_screen_size)
      if instance_variable_defined?(:@colorize)
        IRB.conf[:USE_COLORIZE] = @colorize
      end
      super
    end

    IRBTestColorPrinter = Struct.new(:a)

    def test_color_printer
      {
        1 => "#{BLUE}#{BOLD}1#{CLEAR}\n",
        "a\nb" => %[#{RED}#{BOLD}"#{CLEAR}#{RED}a\\nb#{CLEAR}#{RED}#{BOLD}"#{CLEAR}\n],
        IRBTestColorPrinter.new('test') => "#{GREEN}#<struct TestIRB::ColorPrinterTest::IRBTestColorPrinter#{CLEAR} a#{GREEN}=#{CLEAR}#{RED}#{BOLD}\"#{CLEAR}#{RED}test#{CLEAR}#{RED}#{BOLD}\"#{CLEAR}#{GREEN}>#{CLEAR}\n",
        Ripper::Lexer.new('1').scan => "[#{GREEN}#<Ripper::Lexer::Elem:#{CLEAR} on_int@1:0 END token: #{RED}#{BOLD}\"#{CLEAR}#{RED}1#{CLEAR}#{RED}#{BOLD}\"#{CLEAR}#{GREEN}>#{CLEAR}]\n",
        Class.new{define_method(:pretty_print){|q| q.text("[__FILE__, __LINE__, __ENCODING__]")}}.new => "[#{CYAN}#{BOLD}__FILE__#{CLEAR}, #{CYAN}#{BOLD}__LINE__#{CLEAR}, #{CYAN}#{BOLD}__ENCODING__#{CLEAR}]\n",
      }.each do |object, result|
        actual = with_term { IRB::ColorPrinter.pp(object, '') }
        assert_equal(result, actual, "Case: IRB::ColorPrinter.pp(#{object.inspect}, '')")
      end
    end

    private

    def with_term
      stdout = $stdout
      io = StringIO.new
      def io.tty?; true; end
      $stdout = io

      env = ENV.to_h.dup
      ENV['TERM'] = 'xterm-256color'

      yield
    ensure
      $stdout = stdout
      ENV.replace(env) if env
    end
  end
end
