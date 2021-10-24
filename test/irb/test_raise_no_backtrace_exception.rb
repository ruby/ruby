# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      pend if RUBY_ENGINE == 'truffleruby'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      puts e.inspect
      def e.backtrace; nil; end
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
      pend if RUBY_ENGINE == 'truffleruby'
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
