# frozen_string_literal: true

module Test
  module Unit
    module CoreAssertions
      class RactorAssertionsHost
        include Assertions
        include CoreAssertions

        def _assertions
          @_assertions ||= 0
        end

        def _assertions=(n)
          @_assertions = n
        end
      end

      # A pending assert_in_ractor result; see assert_in_ractor(value: false).
      class RactorAssertionsPending
        attr_reader :ractor

        def initialize(ractor, context, reported) # :nodoc:
          @ractor = ractor
          @context = context
          @reported = reported
        end

        def value
          result, assertions, error = @ractor.value
          @context._assertions += assertions
          if error
            if @reported and Test::Unit::AssertionFailedError === error
              # Already reported in full from inside the Ractor; raise
              # only a pointer so the failure is not reported twice.
              raise error.class, "assertion failed in assert_in_ractor Ractor (full report on stderr)", error.backtrace
            end
            raise error
          end
          result
        end
      end

      # Runs the given block inside a Ractor in this process, and returns
      # the block's value. Unlike a bare <tt>Ractor.new</tt>, the block
      # is executed with the assertion methods available, and assertion
      # failures, pend/omit/skip, and errors raised inside the Ractor are
      # re-raised in the caller, so they are reported by the test framework
      # as usual.
      #
      #   assert_in_ractor([1, 2]) do |ary|
      #     assert_equal 2, ary.size
      #   end
      #
      # With <tt>value: false</tt>, returns a RactorAssertionsPending
      # instead of joining immediately, so the caller can coordinate with
      # the running Ractor via its #ractor; call #value on it to join and
      # collect the result.  If the block raises, the error is reported to
      # stderr in full right away (since #value may never be reached), and
      # #value raises only a pointer to that report.
      def assert_in_ractor(*args, value: true, &block)
        omit "Ractor is not supported" unless defined?(Ractor)
        omit "Ractor.shareable_proc is not supported" unless Ractor.respond_to?(:shareable_proc)

        block = Ractor.shareable_proc(&block)
        ractor = Ractor.new(block, !value, args) do |block, report, args|
          host = RactorAssertionsHost.new
          begin
            [host.instance_exec(*args, &block), host._assertions, nil]
          rescue Exception => e
            if report
              # With value: false, #value may never be reached (e.g. the
              # caller is blocked coordinating with this Ractor), so the
              # error is reported here in full, and #value raises only a
              # pointer to this report.
              begin
                $stderr.puts "assert_in_ractor Ractor failed:"
                $stderr.puts e.full_message(highlight: false, order: :top)
              rescue Exception
              end
            end
            [nil, host._assertions, e]
          end
        end
        pending = RactorAssertionsPending.new(ractor, self, !value)
        value ? pending.value : pending
      end
    end
  end
end
