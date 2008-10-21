# test/unit compatibility layer using minitest.

require 'minitest/unit'
require 'pp'

module Test
  module Unit
    TEST_UNIT_IMPLEMENTATION = 'test/unit compatibility layer using minitest'

    def self.setup_argv(original_argv=ARGV)
      minitest_argv = []
      files = []
      reject = []
      original_argv = original_argv.dup
      while arg = original_argv.shift
        case arg
        when '-v'
          minitest_argv << '-v'
        when '-n', '--name'
          minitest_argv << arg
          minitest_argv << original_argv.shift
        when '-x'
          reject << original_argv.shift
        else
          files << arg
        end
      end

      if block_given?
        files = yield files
      end

      files.map! {|f|
        if File.directory? f
          Dir["#{f}/**/test_*.rb"]
        elsif File.file? f
          f
        else
          raise ArgumentError, "file not found: #{f}"
        end
      }
      files.flatten!

      reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
      files.reject! {|f| reject_pat =~ f }
        
      files.each {|f|
        d = File.dirname(File.expand_path(f))
        unless $:.include? d
          $: << d
        end
        begin
          require f
        rescue LoadError
          puts "#{f}: #{$!}"
        end
      }

      ARGV.replace minitest_argv
    end

    module Assertions
      include MiniTest::Assertions

      def mu_pp(obj)
        obj.pretty_inspect.chomp
      end

      def assert_raise(*args, &b)
        assert_raises(*args, &b)
      end

      def assert_nothing_raised(*args)
        if Module === args.last
          msg = nil
        else
          msg = args.pop
        end
        begin
          yield
        rescue Exception => e
          if ((args.empty? && !e.instance_of?(MiniTest::Assertion)) ||
              args.any? {|a| a.instance_of?(Module) ? e.is_a?(a) : e.class == a })
            msg = message(msg) { "Exception raised:\n<#{mu_pp(e)}>" }
            raise MiniTest::Assertion, msg.call, e.backtrace
          else
            raise
          end
        end
        nil
      end

      def assert_nothing_thrown(msg=nil)
        begin
          yield
        rescue ArgumentError => error
          raise error if /\Auncaught throw (.+)\z/m !~ error.message
          msg = message(msg) { "<#{$1}> was thrown when nothing was expected" }
          flunk(msg)
        end
        assert(true, "Expected nothing to be thrown")
      end

      def assert_equal(exp, act, msg = nil)
        msg = message(msg) {
          exp_str = mu_pp(exp)
          act_str = mu_pp(act)
          exp_comment = ''
          act_comment = ''
          if exp_str == act_str
            if exp.is_a?(String) && act.is_a?(String)
              exp_comment = " (#{exp.encoding})"
              act_comment = " (#{act.encoding})"
            elsif exp.is_a?(Time) && act.is_a?(Time)
              exp_comment = " (nsec=#{exp.nsec})"
              act_comment = " (nsec=#{act.nsec})"
            end
          elsif !Encoding.compatible?(exp_str, act_str)
            if exp.is_a?(String) && act.is_a?(String)
              exp_str = exp.dump
              act_str = act.dump
              exp_comment = " (#{exp.encoding})"
              act_comment = " (#{act.encoding})"
            else
              exp_str = exp_str.dump
              act_str = act_str.dump
            end
          end
          "<#{exp_str}>#{exp_comment} expected but was\n<#{act_str}>#{act_comment}"
        }
        assert(exp == act, msg)
      end

      def assert_not_nil(exp, msg=nil)
        msg = message(msg) { "<#{mu_pp(exp)}> expected to not be nil" }
        assert(!exp.nil?, msg)
      end

      def assert_not_equal(exp, act, msg=nil)
        msg = message(msg) { "<#{mu_pp(exp)}> expected to be != to\n<#{mu_pp(act)}>" }
        assert(exp != act, msg)
      end

      def assert_no_match(regexp, string, msg=nil)
        assert_instance_of(Regexp, regexp, "The first argument to assert_no_match should be a Regexp.")
        msg = message(msg) { "<#{mu_pp(regexp)}> expected to not match\n<#{mu_pp(string)}>" }
        assert(regexp !~ string, msg)
      end

      def assert_not_same(expected, actual, message="")
        msg = message(msg) { build_message(message, <<EOT, expected, expected.__id__, actual, actual.__id__) }
<?>
with id <?> expected to not be equal\\? to
<?>
with id <?>.
EOT
        assert(!actual.equal?(expected), msg)
      end

      def build_message(head, template=nil, *arguments)
        template &&= template.chomp
        template.gsub(/\?/) { mu_pp(arguments.shift) }
      end
    end

    class TestCase < MiniTest::Unit::TestCase
      include Assertions
      def self.test_order
        :sorted
      end
    end
  end
end

MiniTest::Unit.autorun
