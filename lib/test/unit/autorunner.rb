require 'test/unit'
require 'test/unit/ui/testrunnerutilities'
require 'optparse'

module Test
  module Unit
    class AutoRunner
      def self.run(force_standalone=false, default_dir=nil, argv=ARGV, &block)
        r = new(force_standalone || standalone?, &block)
        r.base = default_dir
        r.process_args(argv)
        r.run
      end
      
      def self.standalone?
        return false unless("-e" == $0)
        ObjectSpace.each_object(Class) do |klass|
          return false if(klass < TestCase)
        end
        true
      end

      RUNNERS = {
        :console => proc do |r|
          require 'test/unit/ui/console/testrunner'
          Test::Unit::UI::Console::TestRunner
        end,
        :gtk => proc do |r|
          require 'test/unit/ui/gtk/testrunner'
          Test::Unit::UI::GTK::TestRunner
        end,
        :gtk2 => proc do |r|
          require 'test/unit/ui/gtk2/testrunner'
          Test::Unit::UI::GTK2::TestRunner
        end,
        :fox => proc do |r|
          require 'test/unit/ui/fox/testrunner'
          Test::Unit::UI::Fox::TestRunner
        end,
        :tk => proc do |r|
          require 'test/unit/ui/tk/testrunner'
          Test::Unit::UI::Tk::TestRunner
        end,
      }

      OUTPUT_LEVELS = [
        [:silent, UI::SILENT],
        [:progress, UI::PROGRESS_ONLY],
        [:normal, UI::NORMAL],
        [:verbose, UI::VERBOSE],
      ]

      COLLECTORS = {
        :objectspace => proc do |r|
          require 'test/unit/collector/objectspace'
          c = Collector::ObjectSpace.new
          c.filter = r.filters
          c.collect($0.sub(/\.rb\Z/, ''))
        end,
        :dir => proc do |r|
          require 'test/unit/collector/dir'
          c = Collector::Dir.new
          c.filter = r.filters
          c.pattern.concat(r.pattern) if(r.pattern)
          c.exclude.concat(r.exclude) if(r.exclude)
          c.base = r.base
          $:.push(r.base) if r.base
          c.collect(*(r.to_run.empty? ? ['.'] : r.to_run))
        end,
      }

      attr_reader :suite
      attr_accessor :output_level, :filters, :to_run, :pattern, :exclude, :base, :workdir
      attr_writer :runner, :collector

      def initialize(standalone)
        Unit.run = true
        @standalone = standalone
        @runner = RUNNERS[:console]
        @collector = COLLECTORS[(standalone ? :dir : :objectspace)]
        @filters = []
        @to_run = []
        @output_level = UI::NORMAL
        @workdir = nil
        yield(self) if(block_given?)
      end

      def process_args(args = ARGV)
        begin
          options.order!(args) {|arg| @to_run << arg}
        rescue OptionParser::ParseError => e
          puts e
          puts options
          $! = nil
          abort
        else
          @filters << proc{false} unless(@filters.empty?)
        end
        not @to_run.empty?
      end

      def options
        @options ||= OptionParser.new do |o|
          o.banner = "Test::Unit automatic runner."
          o.banner << "\nUsage: #{$0} [options] [-- untouched arguments]"

          o.on
          o.on('-r', '--runner=RUNNER', RUNNERS,
               "Use the given RUNNER.",
               "(" + keyword_display(RUNNERS) + ")") do |r|
            @runner = r
          end

          if(@standalone)
            o.on('-b', '--basedir=DIR', "Base directory of test suites.") do |b|
              @base = b
            end

            o.on('-w', '--workdir=DIR', "Working directory to run tests.") do |w|
              @workdir = w
            end

            o.on('-a', '--add=TORUN', Array,
                 "Add TORUN to the list of things to run;",
                 "can be a file or a directory.") do |a|
              @to_run.concat(a)
            end

            @pattern = []
            o.on('-p', '--pattern=PATTERN', Regexp,
                 "Match files to collect against PATTERN.") do |e|
              @pattern << e
            end

            @exclude = []
            o.on('-x', '--exclude=PATTERN', Regexp,
                 "Ignore files to collect against PATTERN.") do |e|
              @exclude << e
            end
          end

          o.on('-n', '--name=NAME', String,
               "Runs tests matching NAME.",
               "(patterns may be used).") do |n|
            n = (%r{\A/(.*)/\Z} =~ n ? Regexp.new($1) : n)
            case n
            when Regexp
              @filters << proc{|t| n =~ t.method_name ? true : nil}
            else
              @filters << proc{|t| n == t.method_name ? true : nil}
            end
          end

          o.on('-t', '--testcase=TESTCASE', String,
               "Runs tests in TestCases matching TESTCASE.",
               "(patterns may be used).") do |n|
            n = (%r{\A/(.*)/\Z} =~ n ? Regexp.new($1) : n)
            case n
            when Regexp
              @filters << proc{|t| n =~ t.class.name ? true : nil}
            else
              @filters << proc{|t| n == t.class.name ? true : nil}
            end
          end

          o.on('-I', "--load-path=DIR[#{File::PATH_SEPARATOR}DIR...]",
               "Appends directory list to $LOAD_PATH.") do |dirs|
            $LOAD_PATH.concat(dirs.split(File::PATH_SEPARATOR))
          end

          o.on('-v', '--verbose=[LEVEL]', OUTPUT_LEVELS,
               "Set the output level (default is verbose).",
               "(" + keyword_display(OUTPUT_LEVELS) + ")") do |l|
            @output_level = l || UI::VERBOSE
          end

          o.on('--',
               "Stop processing options so that the",
               "remaining options will be passed to the",
               "test."){o.terminate}

          o.on('-h', '--help', 'Display this help.'){puts o; exit}

          o.on_tail
          o.on_tail('Deprecated options:')

          o.on_tail('--console', 'Console runner (use --runner).') do
            warn("Deprecated option (--console).")
            @runner = RUNNERS[:console]
          end

          o.on_tail('--gtk', 'GTK runner (use --runner).') do
            warn("Deprecated option (--gtk).")
            @runner = RUNNERS[:gtk]
          end

          o.on_tail('--fox', 'Fox runner (use --runner).') do
            warn("Deprecated option (--fox).")
            @runner = RUNNERS[:fox]
          end

          o.on_tail
        end
      end

      def keyword_display(array)
        list = array.collect {|e, *| e.to_s}
        Array === array or list.sort!
        list.collect {|e| e.sub(/^(.)([A-Za-z]+)(?=\w*$)/, '\\1[\\2]')}.join(", ")
      end

      def run
        @suite = @collector[self]
        result = @runner[self] or return false
        Dir.chdir(@workdir) if @workdir
        result.run(@suite, @output_level).passed?
      end
    end
  end
end
