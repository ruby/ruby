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
      def initialize(*, &block)
        @init_hook = block
        super(&nil)
      end

      def option_parser
        @option_parser ||= OptionParser.new
      end

      def process_args(args = [])
        return @options if @options
        orig_args = args.dup
        options = {}
        opts = option_parser
        setup_options(opts, options)
        opts.parse!(args)
        orig_args -= args
        args = @init_hook.call(args, options) if @init_hook
        non_options(args, options) or return nil
        @help = orig_args.map { |s| s =~ /[\s|&<>$()]/ ? s.inspect : s }.join " "
        @options = options
      end

      private
      def setup_options(opts, options)
        opts.separator 'minitest options:'
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
          self.verbose = options[:verbose]
        end

        opts.on '-n', '--name PATTERN', "Filter test names on pattern." do |a|
          options[:filter] = a
        end
      end

      def non_options(files, options)
        true
      end
    end

    module GlobOption
      include Options

      def setup_options(parser, options)
        super
        parser.on '-b', '--basedir=DIR', 'Base directory of test suites.' do |dir|
          options[:base_directory] = dir
        end
        parser.on '-x', '--exclude PATTERN', 'Exclude test files on pattern.' do |pattern|
          (options[:reject] ||= []) << pattern
        end
      end

      def non_options(files, options)
        paths = [options.delete(:base_directory), nil].compact
        if reject = options.delete(:reject)
          reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
        end
        files << "" if files.empty?
        files.map! {|f|
          f = f.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
          [*(paths if /\A\.\.?(?:\z|\/)/ !~ f), nil].uniq.any? do |prefix|
            if prefix
              path = f.empty? ? prefix : "#{prefix}/#{f}"
            else
              next if f.empty?
              path = f
            end
            if !(match = Dir["#{path}/**/test_*.rb"]).empty?
              if reject
                match.reject! {|n|
                  n[(prefix.length+1)..-1] if prefix
                  reject_pat =~ n
                }
              end
              break match
            elsif !reject or reject_pat !~ f and File.exist? path
              break path
            end
          end or
            raise ArgumentError, "file not found: #{f}"
        }
        files.flatten!
        super(files, options)
      end
    end

    module LoadPathOption
      include Options

      def setup_options(parser, options)
        super
        parser.on '-Idirectory', 'Add library load path' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end
    end

    module GCStressOption
      def setup_options(parser, options)
        super
        parser.on '--[no-]gc-stress', 'Set GC.stress as true' do |flag|
          options[:gc_stress] = flag
        end
      end

      def non_options(files, options)
        if options.delete(:gc_stress)
          MiniTest::Unit::TestCase.class_eval do
            oldrun = instance_method(:run)
            define_method(:run) do |runner|
              begin
                gc_stress, GC.stress = GC.stress, true
                oldrun.bind(self).call(runner)
              ensure
                GC.stress = gc_stress
              end
            end
          end
        end
        super
      end
    end

    module RequireFiles
      def non_options(files, options)
        return false if !super or files.empty?
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

    class Runner < MiniTest::Unit
      include Test::Unit::Options
      include Test::Unit::RequireFiles
      include Test::Unit::GlobOption
      include Test::Unit::LoadPathOption
      include Test::Unit::GCStressOption
      include Test::Unit::RunCount

      class << self; undef autorun; end
      def self.autorun
        at_exit {
          Test::Unit::RunCount.run_once {
            exit(Test::Unit::Runner.new.run(ARGV) || true)
          }
        } unless @@installed_at_exit
        @@installed_at_exit = true
      end

      def _run_suites suites, type
        @interrupt = nil
        result = []
        suites.each {|suite|
          begin
            result << _run_suite(suite, type)
          rescue Interrupt => e
            @interrupt = e
            break
          end
        }
        result
      end

      def status(*args)
        result = super
        raise @interrupt if @interrupt
        result
      end
    end

    class AutoRunner
      attr_accessor :to_run, :options

      def initialize(force_standalone = false, default_dir = nil, argv = ARGV)
        @runner = Runner.new do |files, options|
          options[:base_directory] ||= default_dir
          @to_run = files
          yield self if block_given?
          files
        end
        @options = @runner.option_parser
        @argv = argv
      end

      def process_args(*args)
        @runner.process_args(*args)
      end

      def run
        @runner.run(@argv) || true
      end

      def self.run(*args)
        new(*args).run
      end
    end
  end
end

Test::Unit::Runner.autorun
