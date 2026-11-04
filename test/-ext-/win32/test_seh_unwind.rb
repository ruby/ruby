# frozen_string_literal: false
require 'test/unit'
require_relative '../../lib/jit_support'

module Bug
  module Win32
    class TestSehUnwind < Test::Unit::TestCase
      def test_finally_runs_on_raise
        assert_finally_ran(%w[--disable=yjit])
      end

      def test_finally_runs_on_raise_through_yjit
        omit "YJIT is not supported" unless JITSupport.yjit_supported?
        assert_finally_ran(%w[--yjit --yjit-call-threshold=1])
      end

      def test_raise_in_cxx_catch
        assert_raise_in_cxx_catch(%w[--disable=yjit])
      end

      def test_raise_in_cxx_catch_through_yjit
        omit "YJIT is not supported" unless JITSupport.yjit_supported?
        assert_raise_in_cxx_catch(%w[--yjit --yjit-call-threshold=1])
      end

      private

      def assert_finally_ran(args)
        assert_in_out_err(args, <<-INPUT, %w[true true], [])
          require '-test-/win32/seh_unwind'
          def raise_in_try
            Bug::Win32.raise_in_try
          rescue RuntimeError
            Bug::Win32.finally_ran?
          end
          p raise_in_try
          p raise_in_try
        INPUT
      end

      def assert_raise_in_cxx_catch(args)
        assert_in_out_err(args, <<-INPUT, %w[0 true 0], [])
          require '-test-/win32/cxx_catch'
          def raise_in_catch
            Bug::Win32.raise_in_catch
          rescue RuntimeError
          end
          def throw_and_catch = Bug::Win32.throw_and_catch
          raise_in_catch
          p Bug::Win32.live_exceptions
          p throw_and_catch
          p Bug::Win32.live_exceptions
        INPUT
      end
    end
  end
end if /mswin/ =~ RUBY_PLATFORM
