verbose = $VERBOSE
$VERBOSE = true
begin

require 'test/unit'
require 'racc/static'
require 'fileutils'
require 'tempfile'
require 'timeout'

module Racc
  class TestCase < Test::Unit::TestCase
    PROJECT_DIR = File.expand_path(File.join(__dir__, '..'))

    test_dir = File.join(PROJECT_DIR, 'test')
    test_dir = File.join(PROJECT_DIR, 'racc') unless File.exist?(test_dir)
    TEST_DIR = test_dir
    racc = File.join(PROJECT_DIR, 'bin', 'racc')
    racc = File.join(PROJECT_DIR, '..', 'libexec', 'racc') unless File.exist?(racc)
    RACC = racc
    ASSET_DIR = File.join(TEST_DIR, 'assets') # test grammars
    REGRESS_DIR  = File.join(TEST_DIR, 'regress') # known-good generated outputs

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext'),
    ].join(':')

    def setup
      @TEMP_DIR = Dir.mktmpdir("racc")
      @OUT_DIR  = File.join(@TEMP_DIR, 'out')
      @TAB_DIR  = File.join(@TEMP_DIR, 'tab') # generated parsers go here
      @LOG_DIR  = File.join(@TEMP_DIR, 'log')
      @ERR_DIR  = File.join(@TEMP_DIR, 'err')
      FileUtils.mkdir_p([@OUT_DIR, @TAB_DIR, @LOG_DIR, @ERR_DIR])
      FileUtils.cp File.join(TEST_DIR, "src.intp"), @TEMP_DIR
    end

    def teardown
      FileUtils.rm_f(File.join(@TEMP_DIR, "src.intp"))
      FileUtils.rm_rf([@OUT_DIR, @TAB_DIR, @LOG_DIR, @ERR_DIR, @TEMP_DIR])
    end

    def assert_compile(asset, args = [], **opt)
      file = File.basename(asset, '.y')
      args = ([args].flatten) + [
        "#{ASSET_DIR}/#{file}.y",
        '-Do',
        "-O#{@OUT_DIR}/#{file}",
        "-o#{@TAB_DIR}/#{file}",
      ]
      racc(*args, **opt)
    end

    def assert_debugfile(asset, ok)
      file = File.basename(asset, '.y')
      Dir.chdir(@LOG_DIR) do
        File.foreach("#{file}.y") do |line|
          line.strip!
          case line
          when /sr/ then assert_equal "sr#{ok[0]}", line
          when /rr/ then assert_equal "rr#{ok[1]}", line
          when /un/ then assert_equal "un#{ok[2]}", line
          when /ur/ then assert_equal "ur#{ok[3]}", line
          when /ex/ then assert_equal "ex#{ok[4]}", line
          else
            raise TestFailed, 'racc outputs unknown debug report???'
          end
        end
      end
    end

    def assert_exec(asset)
      lib_path = File.expand_path("../../lib", __FILE__)
      file = File.basename(asset, '.y')
      ruby "-I#{lib_path}", "#{@TAB_DIR}/#{file}"
    end

    def strip_version(source)
      source.sub(/This file is automatically generated by Racc \d+\.\d+\.\d+/, '')
    end

    def assert_output_unchanged(asset)
      file = File.basename(asset, '.y')

      # Code to re-generate the expectation files
      # File.write("#{REGRESS_DIR}/#{file}", File.read("#{@TAB_DIR}/#{file}"))

      expected = File.read("#{REGRESS_DIR}/#{file}")
      actual   = File.read("#{@TAB_DIR}/#{file}")
      result   = (strip_version(expected) == strip_version(actual))

      assert(result, proc {`diff -u #{REGRESS_DIR}/#{file} #{@TAB_DIR}/#{file}`})
    end

    def racc(*arg, **opt)
      lib_path = File.expand_path("../../lib", __FILE__)
      ruby "-I#{lib_path}", "-S", RACC, *arg, **opt
    end

    def ruby(*arg, **opt)
      assert_ruby_status(["-C", @TEMP_DIR, *arg], **opt)
    end
  end
end

ensure
$VERBOSE = verbose
end
