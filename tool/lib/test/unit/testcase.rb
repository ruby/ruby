# frozen_string_literal: true
require 'test/unit/assertions'

module Test
  module Unit
    # remove silly TestCase class
    remove_const(:TestCase) if defined?(self::TestCase)

    ##
    # Provides a simple set of guards that you can use in your tests
    # to skip execution if it is not applicable. These methods are
    # mixed into TestCase as both instance and class methods so you
    # can use them inside or outside of the test methods.
    #
    #   def test_something_for_mri
    #     skip "bug 1234"  if jruby?
    #     # ...
    #   end
    #
    #   if windows? then
    #     # ... lots of test methods ...
    #   end

    module Guard

      ##
      # Is this running on jruby?

      def jruby? platform = RUBY_PLATFORM
        "java" == platform
      end

      ##
      # Is this running on mri?

      def maglev? platform = defined?(RUBY_ENGINE) && RUBY_ENGINE
        "maglev" == platform
      end

      module_function :maglev?

      ##
      # Is this running on mri?

      def mri? platform = RUBY_DESCRIPTION
        /^ruby/ =~ platform
      end

      ##
      # Is this running on rubinius?

      def rubinius? platform = defined?(RUBY_ENGINE) && RUBY_ENGINE
        "rbx" == platform
      end

      ##
      # Is this running on windows?

      def windows? platform = RUBY_PLATFORM
        /mswin|mingw/ =~ platform
      end

      ##
      # Is this running on mingw?

      def mingw? platform = RUBY_PLATFORM
        /mingw/ =~ platform
      end

    end

    ##
    # Provides before/after hooks for setup and teardown. These are
    # meant for library writers, NOT for regular test authors. See
    # #before_setup for an example.

    module LifecycleHooks
      ##
      # Runs before every test, after setup. This hook is meant for
      # libraries to extend minitest. It is not meant to be used by
      # test developers.
      #
      # See #before_setup for an example.

      def after_setup; end

      ##
      # Runs before every test, before setup. This hook is meant for
      # libraries to extend minitest. It is not meant to be used by
      # test developers.
      #
      # As a simplistic example:
      #
      #   module MyMinitestPlugin
      #     def before_setup
      #       super
      #       # ... stuff to do before setup is run
      #     end
      #
      #     def after_setup
      #       # ... stuff to do after setup is run
      #       super
      #     end
      #
      #     def before_teardown
      #       super
      #       # ... stuff to do before teardown is run
      #     end
      #
      #     def after_teardown
      #       # ... stuff to do after teardown is run
      #       super
      #     end
      #   end
      #
      #   class MiniTest::Unit::TestCase
      #     include MyMinitestPlugin
      #   end

      def before_setup; end

      ##
      # Runs after every test, before teardown. This hook is meant for
      # libraries to extend minitest. It is not meant to be used by
      # test developers.
      #
      # See #before_setup for an example.

      def before_teardown; end

      ##
      # Runs after every test, after teardown. This hook is meant for
      # libraries to extend minitest. It is not meant to be used by
      # test developers.
      #
      # See #before_setup for an example.

      def after_teardown; end
    end

    ##
    # Subclass TestCase to create your own tests. Typically you'll want a
    # TestCase subclass per implementation class.
    #
    # See MiniTest::Assertions

    class TestCase
      include LifecycleHooks
      include Guard
      extend Guard

      attr_reader :__name__ # :nodoc:

      PASSTHROUGH_EXCEPTIONS = [NoMemoryError, SignalException,
                                Interrupt, SystemExit] # :nodoc:

      # kernel resolution can limit the minimum time we can measure
      # [ruby-core:81540]
      MIN_HZ = windows? ? 67 : 100
      MIN_MEASURABLE = 1.0 / MIN_HZ

      ##
      # Runs the tests reporting the status to +runner+

      def run runner
        trap "INFO" do
          runner.report.each_with_index do |msg, i|
            warn "\n%3d) %s" % [i + 1, msg]
          end
          warn ''
          time = runner.start_time ? Time.now - runner.start_time : 0
          warn "Current Test: %s#%s %.2fs" % [self.class, self.__name__, time]
          runner.status $stderr
        end if runner.info_signal

        start_time = Time.now

        result = ""
        srand(runner.options[:seed])

        begin
          @passed = nil
          self.before_setup
          self.setup
          self.after_setup
          self.run_test self.__name__
          result = "." unless io?
          time = Time.now - start_time
          runner.record self.class, self.__name__, self._assertions, time, nil
          @passed = true
        rescue *PASSTHROUGH_EXCEPTIONS
          raise
        rescue Exception => e
          @passed = Skip === e
          time = Time.now - start_time
          runner.record self.class, self.__name__, self._assertions, time, e
          result = runner.puke self.class, self.__name__, e
        ensure
          %w{ before_teardown teardown after_teardown }.each do |hook|
            begin
              self.send hook
            rescue *PASSTHROUGH_EXCEPTIONS
              raise
            rescue Exception => e
              @passed = false
              runner.record self.class, self.__name__, self._assertions, time, e
              result = runner.puke self.class, self.__name__, e
            end
          end
          trap 'INFO', 'DEFAULT' if runner.info_signal
        end
        result
      end

      alias :run_test :__send__

      def initialize name # :nodoc:
        @__name__ = name
        @__io__ = nil
        @passed = nil
        @@current = self # FIX: make thread local
      end

      def self.current # :nodoc:
        @@current # FIX: make thread local
      end

      ##
      # Return the output IO object

      def io
        @__io__ = true
        MiniTest::Unit.output
      end

      ##
      # Have we hooked up the IO yet?

      def io?
        @__io__
      end

      def self.reset # :nodoc:
        @@test_suites = {}
      end

      reset

      ##
      # Make diffs for this TestCase use #pretty_inspect so that diff
      # in assert_equal can be more details. NOTE: this is much slower
      # than the regular inspect but much more usable for complex
      # objects.

      def self.make_my_diffs_pretty!
        require 'pp'

        define_method :mu_pp do |o|
          o.pretty_inspect
        end
      end

      def self.inherited klass # :nodoc:
        @@test_suites[klass] = true
        super
      end

      def self.test_order # :nodoc:
        :sorted
      end

      def self.test_suites # :nodoc:
        suites = @@test_suites.keys

        case self.test_order
        when :random
          # shuffle test suites based on CRC32 of their names
          salt = "\n" + rand(1 << 32).to_s
          crc_tbl = (0..255).map do |i|
            (0..7).inject(i) {|c,| (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
          end
          suites = suites.sort_by do |suite|
            crc32 = 0xffffffff
            "#{suite.name}#{salt}".each_byte do |data|
              crc32 = crc_tbl[(crc32 ^ data) & 0xff] ^ (crc32 >> 8)
            end
            crc32 ^ 0xffffffff
          end
        when :nosort
          suites
        else
          suites.sort_by { |ts| ts.name.to_s }
        end
      end

      def self.test_methods # :nodoc:
        methods = public_instance_methods(true).grep(/^test/).map { |m| m.to_s }

        case self.test_order
        when :parallel
          max = methods.size
          ParallelEach.new methods.sort.sort_by { rand max }
        when :random then
          max = methods.size
          methods.sort.sort_by { rand max }
        when :alpha, :sorted then
          methods.sort
        when :nosort
          methods
        else
          raise "Unknown test_order: #{self.test_order.inspect}"
        end
      end

      ##
      # Returns true if the test passed.

      def passed?
        @passed
      end

      ##
      # Runs before every test. Use this to set up before each test
      # run.

      def setup; end

      ##
      # Runs after every test. Use this to clean up after each test
      # run.

      def teardown; end

      include CoreAssertions

      def on_parallel_worker?
        false
      end

      def run runner
        @options = runner.options
        super runner
      end

      def self.method_added(name)
        super
        return unless name.to_s.start_with?("test_")
        @test_methods ||= {}
        if @test_methods[name]
          warn "test/unit warning: method #{ self }##{ name } is redefined"
        end
        @test_methods[name] = true
      end
    end
  end
end
