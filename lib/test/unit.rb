# test/unit compatibility layer using minitest.

require 'minitest/unit'
require 'test/unit/assertions'
require 'test/unit/testcase'
require 'optparse'

module Test
  module Unit
    TEST_UNIT_IMPLEMENTATION = 'test/unit compatibility layer using minitest'

    module RunCount
      @@run_count = 0

      def self.have_run?
        @@run_count.nonzero?
      end

      def run(*)
        @@run_count += 1
        super
      end

      def run_once
        return if have_run?
        return if $! # don't run if there was an exception
        yield
      end
      module_function :run_once
    end

    module Options
      def initialize(&block)
        @init_hook = block
        super(&nil)
      end

      def process_args(args = [])
        options = {}
        OptionParser.new do |opts|
          setup_options(opts, options)
          opts.parse!(args)
        end
        args = @init_hook.call(args, options) if @init_hook
        non_options(args, options)
        options
      end

      private
      def setup_options(opts, options)
        opts.banner  = 'minitest options:'
        opts.version = MiniTest::Unit::VERSION

        opts.on '-h', '--help', 'Display this help.' do
          puts opts
          exit
        end

        opts.on '-s', '--seed SEED', Integer, "Sets random seed" do |m|
          options[:seed] = m.to_i
        end

        opts.on '-v', '--verbose', "Verbose. Show progress processing files." do
          options[:verbose] = true
        end

        opts.on '-n', '--name PATTERN', "Filter test names on pattern." do |a|
          options[:filter] = a
        end
      end

      def non_options(files, options)
        files.each {|f|
          d = File.dirname(path = File.expand_path(f))
          unless $:.include? d
            $: << d
          end
          begin
            require path
          rescue LoadError
            puts "#{f}: #{$!}"
          end
        }
      end
    end

    module GlobOption
      include Options

      def non_options(files, options)
        files.map! {|f|
          f = f.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
          if File.directory? f
            Dir["#{f}/**/test_*.rb"]
          elsif File.file? f
            f
          else
            raise ArgumentError, "file not found: #{f}"
          end
        }
        files.flatten!
        super(files, options)
      end
    end

    module RejectOption
      include Options

      def setup_options(parser, options)
        super
        parser.on '-x', '--exclude PATTERN' do |pattern|
          (options[:reject] ||= []) << pattern
        end
      end

      def non_options(files, options)
        if reject = options.delete(:reject)
          reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
          files.reject! {|f| reject_pat =~ f }
        end
        super(files, options)
      end
    end

    module LoadPathOption
      include Options

      def setup_options(parser, options)
        super
        parser.on '-Idirectory' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end
    end

    def self.new
      Mini.new do |files, options|
        if block_given?
          files = yield files
        end
        files
      end
    end

    class Mini < MiniTest::Unit
      include Test::Unit::GlobOption
      include Test::Unit::RejectOption
      include Test::Unit::LoadPathOption
    end
  end
end

class MiniTest::Unit
  def self.new(*args, &block)
    obj = allocate
      .extend(Test::Unit::RunCount)
      .extend(Test::Unit::Options)
    obj.__send__(:initialize, *args, &block)
    obj
  end

  class << self; undef autorun; end
  def self.autorun
    at_exit {
      Test::Unit::RunCount.run_once {
        exit(Test::Unit::Mini.new.run(ARGV) || true)
      }
    } unless @@installed_at_exit
    @@installed_at_exit = true
  end
end

MiniTest::Unit.autorun
