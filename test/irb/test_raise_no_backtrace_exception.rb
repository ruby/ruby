# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestRaiseNoBacktraceException < Test::Unit::TestCase
    def test_raise_exception
      skip if RUBY_ENGINE == 'truffleruby'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /Exception: foo/, [])
      e = Exception.new("foo")
      puts e.inspect
      def e.backtrace; nil; end
      raise e
IRB
    end

    def test_raise_exception_with_invalid_byte_sequence
      skip if RUBY_ENGINE == 'truffleruby'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<~IRB, /A\\xF3B \(StandardError\)/, [])
        raise StandardError, "A\\xf3B"
      IRB
    end

    def test_raise_exception_with_different_encoding_containing_invalid_byte_sequence
      skip if RUBY_ENGINE == 'truffleruby' || /mswin|mingw/ =~ RUBY_PLATFORM
      backup_home = ENV["HOME"]
      Dir.mktmpdir("test_irb_raise_no_backtrace_exception_#{$$}") do |tmpdir|
        ENV["HOME"] = tmpdir

        bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
        File.open('euc.rb', 'w') do |f|
          f.write(<<~EOF)
            # encoding: euc-jp

            def raise_euc_with_invalid_byte_sequence
              raise "\xA4\xA2\\xFF"
            end
          EOF
        end
        assert_in_out_err(bundle_exec + %w[-rirb -W0 -e ENV[%(LC_ALL)]=%(ja_JP.UTF-8) -e ENV[%(LANG)]=%(ja_JP.UTF-8) -e IRB.start(__FILE__) -- -f --], <<~IRB, /`raise_euc_with_invalid_byte_sequence': あ\\xFF \(RuntimeError\)/, [])
          require_relative 'euc'
          raise_euc_with_invalid_byte_sequence
        IRB
      end
    ensure
      ENV["HOME"] = backup_home
    end
  end
end
