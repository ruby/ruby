# frozen_string_literal: false
require "tmpdir"

require_relative "helper"

module TestIRB
  class RaiseExceptionTest < TestCase
    def test_raise_exception_with_nil_backtrace
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /#<Exception: foo>/, [])
      raise Exception.new("foo").tap {|e| def e.backtrace; nil; end }
IRB
    end

    def test_raise_exception_with_message_exception
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      expected = /#<Exception: foo>\nbacktraces are hidden because bar was raised when processing them/
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, expected, [])
      e = Exception.new("foo")
      def e.message; raise 'bar'; end
      raise e
IRB
    end

    def test_raise_exception_with_message_inspect_exception
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      expected = /Uninspectable exception occurred/
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, expected, [])
      e = Exception.new("foo")
      def e.message; raise; end
      def e.inspect; raise; end
      raise e
IRB
    end

    def test_raise_exception_with_invalid_byte_sequence
      pend if RUBY_ENGINE == 'truffleruby' || /mswin|mingw/ =~ RUBY_PLATFORM
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<~IRB, /A\\xF3B \(StandardError\)/, [])
        raise StandardError, "A\\xf3B"
      IRB
    end

    def test_raise_exception_with_different_encoding_containing_invalid_byte_sequence
      backup_home = ENV["HOME"]
      Dir.mktmpdir("test_irb_raise_no_backtrace_exception_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir

        bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
        File.open("#{tmpdir}/euc.rb", 'w') do |f|
          f.write(<<~EOF)
            # encoding: euc-jp

            def raise_euc_with_invalid_byte_sequence
              raise "\xA4\xA2\\xFF"
            end
          EOF
        end
        env = {}
        %w(LC_MESSAGES LC_ALL LC_CTYPE LANG).each {|n| env[n] = "ja_JP.UTF-8" }
        # TruffleRuby warns when the locale does not exist
        env['TRUFFLERUBYOPT'] = "#{ENV['TRUFFLERUBYOPT']} --log.level=SEVERE" if RUBY_ENGINE == 'truffleruby'
        args = [env] + bundle_exec + %W[-rirb -C #{tmpdir} -W0 -e IRB.start(__FILE__) -- -f --]
        error = /`raise_euc_with_invalid_byte_sequence': あ\\xFF \(RuntimeError\)/
        assert_in_out_err(args, <<~IRB, error, [], encoding: "UTF-8")
          require_relative 'euc'
          raise_euc_with_invalid_byte_sequence
        IRB
      end
    ensure
      ENV["HOME"] = backup_home
    end
  end
end
