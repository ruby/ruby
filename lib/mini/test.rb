############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

##
#
# Totally minimal drop-in replacement for test-unit
#
# TODO: refute -> debunk, prove/rebut, show/deny... lots of possibilities

module Mini
  class Assertion < Exception; end

  file = if __FILE__ =~ /^[^\.]/ then # OMG ruby 1.9 is so lame (rubinius too)
           require 'pathname'
           pwd = Pathname.new(Dir.pwd)
           pn = Pathname.new(File.expand_path(__FILE__))
           pn = File.join(".", pn.relative_path_from(pwd)) unless pn.relative?
           pn.to_s
         else
           __FILE__
         end

  MINI_DIR = File.dirname(File.dirname(file))

  def self.filter_backtrace bt
    return ["No backtrace"] unless bt

    new_bt = []
    bt.each do |line|
      break if line.index(MINI_DIR) == 0
      new_bt << line
    end

    new_bt = bt.reject { |line| line.index(MINI_DIR) == 0 } if
      new_bt.empty?
    new_bt = bt.dup if new_bt.empty?

    new_bt
  end

  module Assertions
    def mu_pp(obj)
      s = obj.inspect
      s = s.force_encoding(Encoding.default_external) if defined? Encoding
      s
    end

    def _assertions= n
      @_assertions = n
    end

    def _assertions
      @_assertions ||= 0
    end

    def assert test, msg = nil
      msg ||= "Failed assertion, no message given."
      self._assertions += 1
      unless test then
        msg = msg.call if Proc === msg
        raise Mini::Assertion, msg
      end
      true
    end

    def assert_block msg = nil
      msg = message(msg) { "Expected block to return true value" }
      assert yield, msg
    end

    def assert_empty obj, msg = nil
      msg = message(msg) { "Expected #{obj.inspect} to be empty" }
      assert_respond_to obj, :empty?
      assert obj.empty?, msg
    end

    def assert_equal exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(exp)}, not #{mu_pp(act)}" }
      assert(exp == act, msg)
    end

    def assert_in_delta exp, act, delta = 0.001, msg = nil
      n = (exp - act).abs
      msg = message(msg) { "Expected #{exp} - #{act} (#{n}) to be < #{delta}" }
      assert delta > n, msg
    end

    def assert_in_epsilon a, b, epsilon = 0.001, msg = nil
      assert_in_delta a, b, [a, b].min * epsilon, msg
    end

    def assert_includes collection, obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(collection)} to include #{mu_pp(obj)}" }
      assert_respond_to collection, :include?
      assert collection.include?(obj), msg
    end

    def assert_instance_of cls, obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to be an instance of #{cls}" }
      flip = (Module === obj) && ! (Module === cls) # HACK for specs
      obj, cls = cls, obj if flip
      assert cls === obj, msg
    end

    def assert_kind_of cls, obj, msg = nil # TODO: merge with instance_of
      msg = message(msg) { "Expected #{mu_pp(obj)} to be a kind of #{cls}" }
      flip = (Module === obj) && ! (Module === cls) # HACK for specs
      obj, cls = cls, obj if flip
      assert obj.kind_of?(cls), msg
    end

    def assert_match exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(act)} to match #{mu_pp(exp)}" }
      assert_respond_to act, :=~
      exp = /#{exp}/ if String === exp && String === act
      assert act =~ exp, msg
    end

    def assert_nil obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to be nil" }
      assert obj.nil?, msg
    end

    def assert_operator o1, op, o2, msg = nil
      msg = message(msg) { "Expected #{mu_pp(o1)} to be #{op} #{mu_pp(o2)}" }
      assert o1.__send__(op, o2), msg
    end

    def assert_raises *exp
      msg = String === exp.last ? exp.pop : nil
      should_raise = false
      begin
        yield
        should_raise = true
      rescue Exception => e
        assert_includes exp, e.class
        exception_details(e, "<#{mu_pp(exp)}> exception expected, not")
        return e
      end

      exp = exp.first if exp.size == 1
      fail "#{mu_pp(exp)} expected but nothing was raised." if should_raise
    end

    def assert_respond_to obj, meth, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to respond to #{meth}" }
      flip = (Symbol === obj) && ! (Symbol === meth) # HACK for specs
      obj, meth = meth, obj if flip
      assert obj.respond_to?(meth), msg
    end

    def assert_same exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(act)} to be the same as #{mu_pp(exp)}" }
      assert exp.equal?(act), msg
    end

    def assert_send send_ary, msg = nil
      recv, msg, *args = send_ary
      msg = message(msg) { "Expected ##{msg} on #{mu_pp(recv)} to return true" }
      assert recv.__send__(msg, *args), msg
    end

    def assert_throws sym, msg = nil
      default = "Expected #{mu_pp(sym)} to have been thrown"
      caught = true
      catch(sym) do
        begin
          yield
        rescue ArgumentError => e     # 1.9 exception
          default += ", not #{e.message.split(/ /).last}"
        rescue NameError => e         # 1.8 exception
          default += ", not #{e.name.inspect}"
        end
        caught = false
      end

      assert caught, message(msg) { default }
    end

    def capture_io
      require 'stringio'

      orig_stdout, orig_stderr         = $stdout.dup, $stderr.dup
      captured_stdout, captured_stderr = StringIO.new, StringIO.new
      $stdout, $stderr                 = captured_stdout, captured_stderr

      yield

      return captured_stdout.string, captured_stderr.string
    ensure
      $stdout = orig_stdout
      $stderr = orig_stderr
    end

    def exception_details e, msg
      "#{msg}\nClass: <#{e.class}>\nMessage: <#{e.message.inspect}>\n---Backtrace---\n#{Mini::filter_backtrace(e.backtrace).join("\n")}\n---------------"
    end

    def fail msg = nil
      msg ||= "Epic Fail!"
      assert false, msg
    end

    alias :flunk :fail

    def message msg = nil, &default
      proc {
        if msg then
          msg = msg.to_s unless String === msg
          msg += '.' unless msg.empty?
          msg += "\n#{default.call}."
          msg.strip
        else
          "#{default.call}."
        end
      }
    end

    # used for counting assertions
    def pass msg = nil
      assert true
    end

    def refute test, msg = nil
      msg ||= "Failed refutation, no message given"
      not assert(! test, msg)
    end

    def refute_empty obj, msg = nil
      msg = message(msg) { "Expected #{obj.inspect} to not be empty" }
      assert_respond_to obj, :empty?
      refute obj.empty?, msg
    end

    def refute_equal exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(act)} to not be equal to #{mu_pp(exp)}" }
      refute exp == act, msg
    end

    def refute_in_delta exp, act, delta = 0.001, msg = nil
      n = (exp - act).abs
      msg = message(msg) { "Expected #{exp} - #{act} (#{n}) to not be < #{delta}" }
      refute delta > n, msg
    end

    def refute_in_epsilon a, b, epsilon = 0.001, msg = nil
      refute_in_delta a, b, a * epsilon, msg
    end

    def refute_includes collection, obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(collection)} to not include #{mu_pp(obj)}" }
      assert_respond_to collection, :include?
      refute collection.include?(obj), msg
    end

    def refute_instance_of cls, obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to not be an instance of #{cls}" }
      flip = (Module === obj) && ! (Module === cls) # HACK for specs
      obj, cls = cls, obj if flip
      refute cls === obj, msg
    end

    def refute_kind_of cls, obj, msg = nil # TODO: merge with instance_of
      msg = message(msg) { "Expected #{mu_pp(obj)} to not be a kind of #{cls}" }
      flip = (Module === obj) && ! (Module === cls) # HACK for specs
      obj, cls = cls, obj if flip
      refute obj.kind_of?(cls), msg
    end

    def refute_match exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(act)} to not match #{mu_pp(exp)}" }
      refute act =~ exp, msg
    end

    def refute_nil obj, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to not be nil" }
      refute obj.nil?, msg
    end

    def refute_operator o1, op, o2, msg = nil
      msg = message(msg) { "Expected #{mu_pp(o1)} to not be #{op} #{mu_pp(o2)}" }
      refute o1.__send__(op, o2), msg
    end

    def refute_respond_to obj, meth, msg = nil
      msg = message(msg) { "Expected #{mu_pp(obj)} to not respond to #{meth}" }
      flip = (Symbol === obj) && ! (Symbol === meth) # HACK for specs
      obj, meth = meth, obj if flip
      refute obj.respond_to?(meth), msg
    end

    def refute_same exp, act, msg = nil
      msg = message(msg) { "Expected #{mu_pp(act)} to not be the same as #{mu_pp(exp)}" }
      refute exp.equal?(act), msg
    end
  end

  class Test
    VERSION = "1.3.0"

    attr_reader :report, :failures, :errors

    @@installed_at_exit ||= false
    @@out = $stdout

    def self.autorun
      at_exit {
        exit_code = Mini::Test.new.run(ARGV)
        exit exit_code if exit_code
      } unless @@installed_at_exit
      @@installed_at_exit = true
    end

    def self.output= stream
      @@out = stream
    end

    def puke klass, meth, e
      if Mini::Assertion === e then
        @failures += 1

        loc = e.backtrace.find { |s| s !~ /in .(assert|refute|flunk|pass|fail|raise)/ }
        loc.sub!(/:in .*$/, '')

        @report << "Failure:\n#{meth}(#{klass}) [#{loc}]:\n#{e.message}\n"
        'F'
      else
        @errors += 1
        bt = Mini::filter_backtrace(e.backtrace).join("\n    ")
        e = "Error:\n#{meth}(#{klass}):\n#{e.class}: #{e.message}\n    #{bt}\n"
        @report << e
        'E'
      end
    end

    def initialize
      @report = []
      @errors = @failures = 0
      @verbose = false
    end

    ##
    # Top level driver, controls all output and filtering.

    def run args
      @verbose = args.delete('-v')

      filter = if args.first =~ /^(-n|--name)$/ then
                 args.shift
                 arg = args.shift
                 arg =~ /\/(.*)\// ? Regexp.new($1) : arg
               else
                 /./ # anything - ^test_ already filtered by #tests
               end

      @@out.puts "Loaded suite #{$0.sub(/\.rb$/, '')}\nStarted"

      start = Time.now
      run_test_suites filter

      @@out.puts
      @@out.puts "Finished in #{'%.6f' % (Time.now - start)} seconds."

      @report.each_with_index do |msg, i|
        @@out.puts "\n%3d) %s" % [i + 1, msg]
      end

      @@out.puts

      format = "%d tests, %d assertions, %d failures, %d errors"
      @@out.puts format % [@test_count, @assertion_count, failures, errors]

      return failures + errors if @test_count > 0 # or return nil...
    end

    def run_test_suites filter = /./
      @test_count, @assertion_count = 0, 0
      old_sync, @@out.sync = @@out.sync, true if @@out.respond_to? :sync=
      TestCase.test_suites.each do |suite|
        suite.test_methods.grep(filter).each do |test|
          inst = suite.new test
          inst._assertions = 0
          @@out.print "#{suite}##{test}: " if @verbose

          t = Time.now if @verbose
          result = inst.run(self)

          @@out.print "%.2f s: " % (Time.now - t) if @verbose
          @@out.print result
          @@out.puts if @verbose
          @test_count += 1
          @assertion_count += inst._assertions
        end
      end
      @@out.sync = old_sync if @@out.respond_to? :sync=
      [@test_count, @assertion_count]
    end

    class TestCase
      attr_reader :name

      def run runner
        result = '.'
        begin
          @passed = nil
          self.setup
          self.__send__ self.name
          @passed = true
        rescue Exception => e
          @passed = false
          result = runner.puke(self.class, self.name, e)
        ensure
          begin
            self.teardown
          rescue Exception => e
            result = runner.puke(self.class, self.name, e)
          end
        end
        result
      end

      def initialize name
        @name = name
        @passed = nil
      end

      def self.reset
        @@test_suites = {}
      end

      reset

      def self.inherited klass
        @@test_suites[klass] = true
      end

      def self.test_order
        :random
      end

      def self.test_suites
        @@test_suites.keys.sort_by { |ts| ts.name }
      end

      def self.test_methods
        methods = public_instance_methods(true).grep(/^test/).map { |m|
          m.to_s
        }.sort

        if self.test_order == :random then
          max = methods.size
          methods = methods.sort_by { rand(max) }
        end

        methods
      end

      def setup; end
      def teardown; end

      def passed?
        @passed
      end

      include Mini::Assertions
    end # class TestCase
  end # class Test
end # module Mini
