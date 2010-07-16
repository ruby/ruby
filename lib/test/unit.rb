# test/unit compatibility layer using minitest.

require 'minitest/unit'
require 'test/unit/assertions'
require 'test/unit/testcase'
require 'optparse'

module Test
  module Unit
    TEST_UNIT_IMPLEMENTATION = 'test/unit compatibility layer using minitest'

    def self.setup_argv(original_argv=ARGV)
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

      ARGV.replace minitest_argv
    end
  end
end

MiniTest::Unit.autorun
