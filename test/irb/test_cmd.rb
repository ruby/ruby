# frozen_string_literal: false
require "test/unit"
require "irb"
require "irb/extend-command"

module TestIRB
  class ExtendCommand < Test::Unit::TestCase
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
      @xdg_config_home_backup = ENV.delete("XDG_CONFIG_HOME")
      @default_encoding = [Encoding.default_external, Encoding.default_internal]
      @stdio_encodings = [STDIN, STDOUT, STDERR].map {|io| [io.external_encoding, io.internal_encoding] }
      IRB.instance_variable_get(:@CONF).clear
      @is_win = (RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/)
    end

    def teardown
      ENV["XDG_CONFIG_HOME"] = @xdg_config_home_backup
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
      lang_backup = ENV.delete("LANG")
      lc_all_backup = ENV.delete("LC_ALL")
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace, TestInputMethod.new([]))
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion:\s.+\n
        IRB\sversion:\sirb\s.+\n
        InputMethod:\sAbstract\sInputMethod\n
        \.irbrc\spath:\s.+\n
        RUBY_PLATFORM:\s.+\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
        #{@is_win ? 'Code\spage:\s\d+\n' : ''}
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["LANG"] = lang_backup
      ENV["LC_ALL"] = lc_all_backup
    end

    def test_irb_info_singleline
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = false
      IRB.conf[:USE_SINGLELINE] = true
      IRB.conf[:VERBOSE] = false
      lang_backup = ENV.delete("LANG")
      lc_all_backup = ENV.delete("LC_ALL")
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace, TestInputMethod.new([]))
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion:\s.+\n
        IRB\sversion:\sirb\s.+\n
        InputMethod:\sAbstract\sInputMethod\n
        \.irbrc\spath:\s.+\n
        RUBY_PLATFORM:\s.+\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
        #{@is_win ? 'Code\spage:\s\d+\n' : ''}
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["LANG"] = lang_backup
      ENV["LC_ALL"] = lc_all_backup
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
      lang_backup = ENV.delete("LANG")
      lc_all_backup = ENV.delete("LC_ALL")
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace, TestInputMethod.new([]))
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion:\s.+\n
        IRB\sversion:\sirb\s.+\n
        InputMethod:\sAbstract\sInputMethod\n
        RUBY_PLATFORM:\s.+\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
        #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
      ENV["LANG"] = lang_backup
      ENV["LC_ALL"] = lc_all_backup
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
      lang_backup = ENV.delete("LANG")
      lc_all_backup = ENV.delete("LC_ALL")
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace, TestInputMethod.new([]))
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion:\s.+\n
        IRB\sversion:\sirb\s.+\n
        InputMethod:\sAbstract\sInputMethod\n
        RUBY_PLATFORM:\s.+\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
        #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
      ENV["LANG"] = lang_backup
      ENV["LC_ALL"] = lc_all_backup
    end

    def test_irb_info_lang
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = true
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      lang_backup = ENV.delete("LANG")
      lc_all_backup = ENV.delete("LC_ALL")
      ENV["LANG"] = "ja_JP.UTF-8"
      ENV["LC_ALL"] = "en_US.UTF-8"
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace, TestInputMethod.new([]))
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sAbstract\sInputMethod\n
        \.irbrc\spath: .+\n
        RUBY_PLATFORM: .+\n
        LANG\senv:\sja_JP\.UTF-8\n
        LC_ALL\senv:\sen_US\.UTF-8\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["LANG"] = lang_backup
      ENV["LC_ALL"] = lc_all_backup
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

    def test_measure_with_proc
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
        "measure { |context, code, line_no, &block|\n",
        "  result = block.()\n",
        "  puts 'aaa' if IRB.conf[:MEASURE]\n",
        "  result\n",
        "}\n",
        "3\n",
        "measure { |context, code, line_no, &block|\n",
        "  result = block.()\n",
        "  puts 'bbb' if IRB.conf[:MEASURE]\n",
        "  result\n",
        "}\n",
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
      assert_match(/\A=> 3\nBLOCK is added\.\n=> nil\naaa\n=> 3\nBLOCK is added.\naaa\n=> nil\nbbb\n=> 3\n=> nil\n=> 3\n/, out)
      assert_empty(c.class_variables)
    end

    def test_irb_source
      IRB.init_config(nil)
      File.write("#{@tmpdir}/a.rb", "a = 'hi'\n")
      input = TestInputMethod.new([
          "a = 'bug17564'\n",
          "a\n",
          "irb_source '#{@tmpdir}/a.rb'\n",
          "a\n",
        ])
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      irb = IRB::Irb.new(IRB::WorkSpace.new(self), input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_pattern_list([
          /=> "bug17564"\n/,
          /=> "bug17564"\n/,
          /   => "hi"\n/,
          /   => nil\n/,
          /=> "hi"\n/,
        ], out)
    end

    def test_irb_load
      IRB.init_config(nil)
      File.write("#{@tmpdir}/a.rb", "a = 'hi'\n")
      input = TestInputMethod.new([
          "a = 'bug17564'\n",
          "a\n",
          "irb_load '#{@tmpdir}/a.rb'\n",
          "a\n",
        ])
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      irb = IRB::Irb.new(IRB::WorkSpace.new(self), input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_pattern_list([
          /=> "bug17564"\n/,
          /=> "bug17564"\n/,
          /   => "hi"\n/,
          /   => nil\n/,
          /=> "bug17564"\n/,
        ], out)
    end

    def test_ls
      input = TestInputMethod.new([
        "class P\n",
        "  def m() end\n",
        "  def m2() end\n",
        "end\n",

        "class C < P\n",
        "  def m1() end\n",
        "  def m2() end\n",
        "end\n",

        "module M\n",
        "  def m1() end\n",
        "  def m3() end\n",
        "end\n",

        "module M2\n",
        "  include M\n",
        "  def m4() end\n",
        "end\n",

        "obj = C.new\n",
        "obj.instance_variable_set(:@a, 1)\n",
        "obj.extend M2\n",
        "def obj.m5() end\n",
        "ls obj\n",
      ])
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(self)
      IRB.conf[:VERBOSE] = false
      irb = IRB::Irb.new(workspace, input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/^instance variables:\s+@a\n/m, out)
      assert_match(/P#methods:\s+m\n/m, out)
      assert_match(/C#methods:\s+m2\n/m, out)
      assert_match(/M#methods:\s+m1\s+m3\n/m, out)
      assert_match(/M2#methods:\s+m4\n/m, out)
      assert_match(/C.methods:\s+m5\n/m, out)
    end

    def test_ls_with_no_singleton_class
      input = TestInputMethod.new([
        "ls 42",
      ])
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(self)
      IRB.conf[:VERBOSE] = false
      irb = IRB::Irb.new(workspace, input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/Comparable#methods:\s+/, out)
      assert_match(/Numeric#methods:\s+/, out)
      assert_match(/Integer#methods:\s+/, out)
    end

    def test_show_source
      input = TestInputMethod.new([
        "show_source 'IRB.conf'\n",
      ])
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(self)
      IRB.conf[:VERBOSE] = false
      irb = IRB::Irb.new(workspace, input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(%r[/irb\.rb], out)
    end

    def test_show_source_end_finder
      pend if RUBY_ENGINE == 'truffleruby'
      eval(code = <<-EOS, binding, __FILE__, __LINE__ + 1)
        def show_source_test_method
          unless true
          end
        end
      EOS
      input = TestInputMethod.new([
        "show_source 'TestIRB::ExtendCommand#show_source_test_method'\n",
      ])
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(self)
      IRB.conf[:VERBOSE] = false
      irb = IRB::Irb.new(workspace, input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_include(out, code)
    end

    def test_whereami
      input = TestInputMethod.new([
        "whereami\n",
      ])
      IRB.init_config(nil)
      workspace = IRB::WorkSpace.new(self)
      IRB.conf[:VERBOSE] = false
      irb = IRB::Irb.new(workspace, input)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      irb.context.return_format = "=> %s\n"
      out, err = capture_output do
        irb.eval_input
      end
      assert_empty err
      assert_match(/^From: .+ @ line \d+ :\n/, out)
    end
  end
end
