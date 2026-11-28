# frozen_string_literal: false
require 'test/unit'
require_relative '../../lib/jit_support'

module Bug
  module Win32
    class TestCxxCatch < Test::Unit::TestCase
      def test_raise_in_cxx_catch
        assert_raise_in_cxx_catch(%w[--disable=yjit])
      end

      def test_raise_in_cxx_catch_through_yjit
        omit "YJIT is not supported" unless JITSupport.yjit_supported?
        assert_raise_in_cxx_catch(%w[--yjit --yjit-call-threshold=1])
      end

      private

      def assert_raise_in_cxx_catch(args)
        exp = /mswin/ =~ RUBY_PLATFORM ?
          %w[true 0 RuntimeError 0] :
          %w[true 0 RuntimeError]
        assert_in_out_err(args, <<-INPUT, exp, [])
          require '-test-/win32/cxx_catch'
          def raise_in_catch
            Bug::Win32.raise_in_catch
          rescue RuntimeError => e
            e.class
          end
          def throw_and_catch = Bug::Win32.throw_and_catch
          p throw_and_catch
          p Bug::Win32.live_exceptions
          p raise_in_catch
          # longjmp in C++ catch block is undefined behavior according to C++ standard.
          # Destructor of counted_exception is called in MSVC but not in GCC.
          p Bug::Win32.live_exceptions if /mswin/ =~ RUBY_PLATFORM
        INPUT
      end
    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
