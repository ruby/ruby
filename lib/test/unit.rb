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
          self.verbose = options[:verbose]
        end

        opts.on '-n', '--name PATTERN', "Filter test names on pattern." do |a|
          options[:filter] = a
        end
      end

      def non_options(files, options)
      end
    end

    module GlobOption
      include Options

      def setup_options(parser, options)
        super
        parser.on '-x', '--exclude PATTERN' do |pattern|
          (options[:reject] ||= []) << pattern
        end
      end

      def non_options(files, options)
        paths = [options.delete(:base_directory), nil].compact
        if reject = options.delete(:reject)
          reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
        end
        files.map! {|f|
          f = f.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
          [*paths, nil].any? do |prefix|
            path = prefix ? "#{prefix}/#{f}" : f
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
        parser.on '-Idirectory' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end
    end

    module RequireFiles
      def non_options(files, options)
        super
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

    def self.new(*args, &block)
      Mini.class_eval do
        include Test::Unit::RequireFiles
      end
      Mini.new(*args, &block)
    end

    class Mini < MiniTest::Unit
      include Test::Unit::GlobOption
      include Test::Unit::LoadPathOption
      include Test::Unit::RunCount
      include Test::Unit::Options

      class << self; undef autorun; end
      def self.autorun
        at_exit {
          Test::Unit::RunCount.run_once {
            exit(Test::Unit::Mini.new.run(ARGV) || true)
          }
        } unless @@installed_at_exit
        @@installed_at_exit = true
      end

      def run(*args)
        super
      end
    end
  end
end

Test::Unit::Mini.autorun
