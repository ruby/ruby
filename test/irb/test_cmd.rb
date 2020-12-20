# frozen_string_literal: false
require "test/unit"
require "irb"
require "irb/extend-command"

module TestIRB
  class ExtendCommand < Test::Unit::TestCase
    def setup
      @pwd = Dir.pwd
      @tmpdir = File.join(Dir.tmpdir, "test_reline_config_#{$$}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      Dir.chdir(@tmpdir)
      @home_backup = ENV["HOME"]
      ENV["HOME"] = @tmpdir
      @default_encoding = [Encoding.default_external, Encoding.default_internal]
      @stdio_encodings = [STDIN, STDOUT, STDERR].map {|io| [io.external_encoding, io.internal_encoding] }
      IRB.instance_variable_get(:@CONF).clear
    end

    def teardown
      ENV["HOME"] = @home_backup
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
      EnvUtil.suppress_warning {
        Encoding.default_external, Encoding.default_internal = *@default_encoding
        [STDIN, STDOUT, STDERR].zip(@stdio_encodings) do |io, encs|
          io.set_encoding(*encs)
        end
      }
    end

    def test_irb_info_multiline
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = true
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReidlineInputMethod\swith\sReline .+ and .+\n
        \.irbrc\spath: .+
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    end

    def test_irb_info_singleline
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = false
      IRB.conf[:USE_SINGLELINE] = true
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReadlineInputMethod\swith .+ and .+\n
        \.irbrc\spath: .+
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    end

    def test_irb_info_multiline_without_rc_files
      inputrc_backup = ENV["INPUTRC"]
      ENV["INPUTRC"] = "unknown_inpurc"
      ext_backup = IRB::IRBRC_EXT
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, "unknown_ext")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = true
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReidlineInputMethod\swith\sReline\s[^ ]+(?!\sand\s.+)\n
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
    end

    def test_irb_info_singleline_without_rc_files
      inputrc_backup = ENV["INPUTRC"]
      ENV["INPUTRC"] = "unknown_inpurc"
      ext_backup = IRB::IRBRC_EXT
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, "unknown_ext")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = false
      IRB.conf[:USE_SINGLELINE] = true
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReadlineInputMethod\swith\s(?~.*\sand\s.+)\n
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
    end

    class TestInputMethod < ::IRB::InputMethod
      attr_reader :list, :line_no

      def initialize(list = [])
        super("test")
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end
    end

    def test_measure
      IRB.init_config(nil)
      IRB.conf[:PROMPT] = {
        DEFAULT: {
          PROMPT_I: '> ',
          PROMPT_S: '> ',
          PROMPT_C: '> ',
          PROMPT_N: '> '
        }
      }
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :DEFAULT
      IRB.conf[:MEASURE] = false
      input = TestInputMethod.new([
        "3\n",
        "measure\n",
        "3\n",
        "measure :off\n",
        "3\n",
      ])
      c = Class.new(Object)
      irb = IRB::Irb.new(IRB::WorkSpace.new(c.new), input)
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/\A=> 3\nTIME is added\.\n=> nil\nprocessing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
      assert_empty(c.class_variables)
    end

    def test_measure_enabled_by_rc
      IRB.init_config(nil)
      IRB.conf[:PROMPT] = {
        DEFAULT: {
          PROMPT_I: '> ',
          PROMPT_S: '> ',
          PROMPT_C: '> ',
          PROMPT_N: '> '
        }
      }
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :DEFAULT
      IRB.conf[:MEASURE] = true
      input = TestInputMethod.new([
        "3\n",
        "measure :off\n",
        "3\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/\Aprocessing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end

    def test_measure_enabled_by_rc_with_custom
      IRB.init_config(nil)
      IRB.conf[:PROMPT] = {
        DEFAULT: {
          PROMPT_I: '> ',
          PROMPT_S: '> ',
          PROMPT_C: '> ',
          PROMPT_N: '> '
        }
      }
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :DEFAULT
      IRB.conf[:MEASURE] = true
      IRB.conf[:MEASURE_PROC][:CUSTOM] = proc { |line, line_no, &block|
        time = Time.now
        result = block.()
        puts 'custom processing time: %fs' % (Time.now - time) if IRB.conf[:MEASURE]
        result
      }
      input = TestInputMethod.new([
        "3\n",
        "measure :off\n",
        "3\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/\Acustom processing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end

    def test_measure_with_custom
      IRB.init_config(nil)
      IRB.conf[:PROMPT] = {
        DEFAULT: {
          PROMPT_I: '> ',
          PROMPT_S: '> ',
          PROMPT_C: '> ',
          PROMPT_N: '> '
        }
      }
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :DEFAULT
      IRB.conf[:MEASURE] = false
      IRB.conf[:MEASURE_PROC][:CUSTOM] = proc { |line, line_no, &block|
        time = Time.now
        result = block.()
        puts 'custom processing time: %fs' % (Time.now - time) if IRB.conf[:MEASURE]
        result
      }
      input = TestInputMethod.new([
        "3\n",
        "measure\n",
        "3\n",
        "measure :off\n",
        "3\n",
      ])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/\A=> 3\nCUSTOM is added\.\n=> nil\ncustom processing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end
  end
end
