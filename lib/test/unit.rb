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
    end

    def self.setup_argv(original_argv=::ARGV)
      minitest_argv = []
      files = []
      reject = []
      original_argv = original_argv.dup
      OptionParser.new do |parser|
        parser.default_argv = original_argv

        parser.on '-v', '--verbose' do |v|
          minitest_argv << '-v' if v
        end

        parser.on '-n', '--name TESTNAME' do |name|
          minitest_argv << '-n'
          minitest_argv << name
        end

        parser.on '-x', '--exclude PATTERN' do |pattern|
          reject << pattern
        end

        parser.on '-Idirectory' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end.parse!
      files = original_argv

      if block_given?
        files = yield files
      end

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

      reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
      files.reject! {|f| reject_pat =~ f }

      MiniTest::Unit._install_at_exit {
        next if RunCount.have_run?
        next if $! # don't run if there was an exception
        exit false unless run(minitest_argv)
      }

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

      minitest_argv
    end

    def self.run(args)
      exit_code = MiniTest::Unit.new.run(args)
      !exit_code || exit_code == 0
    end

    def self.start(argv=::ARGV, &block)
      run(setup_argv(argv, &block))
    end
  end
end

class MiniTest::Unit
  def self.new(*)
    super.extend(Test::Unit::RunCount)
  end

  def self._install_at_exit(&block)
    at_exit(&block) unless @@installed_at_exit
    @@installed_at_exit = true
  end
end
