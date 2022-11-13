# frozen_string_literal: false
require "irb"
require "irb/extend-command"

require_relative "helper"

module TestIRB
  class ExtendCommandTest < TestCase
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
      save_encodings
      IRB.instance_variable_get(:@CONF).clear
      @is_win = (RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/)
    end

    def teardown
      ENV["XDG_CONFIG_HOME"] = @xdg_config_home_backup
      ENV["HOME"] = @home_backup
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
      restore_encodings
    end

    class InfoCommandTest < ExtendCommandTest
      def setup
        super
        @locals_backup = ENV.delete("LANG"), ENV.delete("LC_ALL")
      end

      def teardown
        super
        ENV["LANG"], ENV["LC_ALL"] = @locals_backup
      end

      def test_irb_info_multiline
        FileUtils.touch("#{@tmpdir}/.inputrc")
        FileUtils.touch("#{@tmpdir}/.irbrc")

        out, err = execute_lines(
          "irb_info",
          conf: { USE_MULTILINE: true, USE_SINGLELINE: false }
        )

        expected = %r{
          Ruby\sversion:\s.+\n
          IRB\sversion:\sirb\s.+\n
          InputMethod:\sAbstract\sInputMethod\n
          \.irbrc\spath:\s.+\n
          RUBY_PLATFORM:\s.+\n
          East\sAsian\sAmbiguous\sWidth:\s\d\n
          #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        }x

        assert_empty err
        assert_match expected, out
      end

      def test_irb_info_singleline
        FileUtils.touch("#{@tmpdir}/.inputrc")
        FileUtils.touch("#{@tmpdir}/.irbrc")

        out, err = execute_lines(
          "irb_info",
          conf: { USE_MULTILINE: false, USE_SINGLELINE: true }
        )

        expected = %r{
          Ruby\sversion:\s.+\n
          IRB\sversion:\sirb\s.+\n
          InputMethod:\sAbstract\sInputMethod\n
          \.irbrc\spath:\s.+\n
          RUBY_PLATFORM:\s.+\n
          East\sAsian\sAmbiguous\sWidth:\s\d\n
          #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        }x

        assert_empty err
        assert_match expected, out
      end

      def test_irb_info_multiline_without_rc_files
        inputrc_backup = ENV["INPUTRC"]
        ENV["INPUTRC"] = "unknown_inpurc"
        ext_backup = IRB::IRBRC_EXT
        IRB.__send__(:remove_const, :IRBRC_EXT)
        IRB.const_set(:IRBRC_EXT, "unknown_ext")

        out, err = execute_lines(
          "irb_info",
          conf: { USE_MULTILINE: true, USE_SINGLELINE: false }
        )

        expected = %r{
          Ruby\sversion:\s.+\n
          IRB\sversion:\sirb\s.+\n
          InputMethod:\sAbstract\sInputMethod\n
          RUBY_PLATFORM:\s.+\n
          East\sAsian\sAmbiguous\sWidth:\s\d\n
          #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        }x

        assert_empty err
        assert_match expected, out
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

        out, err = execute_lines(
          "irb_info",
          conf: { USE_MULTILINE: false, USE_SINGLELINE: true }
        )

        expected = %r{
          Ruby\sversion:\s.+\n
          IRB\sversion:\sirb\s.+\n
          InputMethod:\sAbstract\sInputMethod\n
          RUBY_PLATFORM:\s.+\n
          East\sAsian\sAmbiguous\sWidth:\s\d\n
          #{@is_win ? 'Code\spage:\s\d+\n' : ''}
        }x

        assert_empty err
        assert_match expected, out
      ensure
        ENV["INPUTRC"] = inputrc_backup
        IRB.__send__(:remove_const, :IRBRC_EXT)
        IRB.const_set(:IRBRC_EXT, ext_backup)
      end

      def test_irb_info_lang
        FileUtils.touch("#{@tmpdir}/.inputrc")
        FileUtils.touch("#{@tmpdir}/.irbrc")
        ENV["LANG"] = "ja_JP.UTF-8"
        ENV["LC_ALL"] = "en_US.UTF-8"

        out, err = execute_lines(
          "irb_info",
          conf: { USE_MULTILINE: true, USE_SINGLELINE: false }
        )

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

        assert_empty err
        assert_match expected, out
      end
    end

    def test_measure
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> ',
            PROMPT_N: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false
      }

      c = Class.new(Object)
      out, err = execute_lines(
        "3\n",
        "measure\n",
        "3\n",
        "measure :off\n",
        "3\n",
        conf: conf,
        main: c
      )

      assert_empty err
      assert_match(/\A=> 3\nTIME is added\.\n=> nil\nprocessing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
      assert_empty(c.class_variables)
    end

    def test_measure_enabled_by_rc
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> ',
            PROMPT_N: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: true
      }

      out, err = execute_lines(
        "3\n",
        "measure :off\n",
        "3\n",
        conf: conf,
      )

      assert_empty err
      assert_match(/\Aprocessing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end

    def test_measure_enabled_by_rc_with_custom
      measuring_proc = proc { |line, line_no, &block|
        time = Time.now
        result = block.()
        puts 'custom processing time: %fs' % (Time.now - time) if IRB.conf[:MEASURE]
        result
      }
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> ',
            PROMPT_N: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: true,
        MEASURE_PROC: { CUSTOM: measuring_proc }
      }

      out, err = execute_lines(
        "3\n",
        "measure :off\n",
        "3\n",
        conf: conf,
      )
      assert_empty err
      assert_match(/\Acustom processing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end

    def test_measure_with_custom
      measuring_proc = proc { |line, line_no, &block|
        time = Time.now
        result = block.()
        puts 'custom processing time: %fs' % (Time.now - time) if IRB.conf[:MEASURE]
        result
      }
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> ',
            PROMPT_N: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false,
        MEASURE_PROC: { CUSTOM: measuring_proc }
      }
      out, err = execute_lines(
        "3\n",
        "measure\n",
        "3\n",
        "measure :off\n",
        "3\n",
        conf: conf
      )

      assert_empty err
      assert_match(/\A=> 3\nCUSTOM is added\.\n=> nil\ncustom processing time: .+\n=> 3\n=> nil\n=> 3\n/, out)
    end

    def test_measure_with_proc
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> ',
            PROMPT_N: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false,
      }
      c = Class.new(Object)
      out, err = execute_lines(
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
        conf: conf,
        main: c
      )

      assert_empty err
      assert_match(/\A=> 3\nBLOCK is added\.\n=> nil\naaa\n=> 3\nBLOCK is added.\naaa\n=> nil\nbbb\n=> 3\n=> nil\n=> 3\n/, out)
      assert_empty(c.class_variables)
    end

    def test_irb_source
      File.write("#{@tmpdir}/a.rb", "a = 'hi'\n")
      out, err = execute_lines(
        "a = 'bug17564'\n",
        "a\n",
        "irb_source '#{@tmpdir}/a.rb'\n",
        "a\n",
      )
      assert_empty err
      assert_pattern_list([
        /=> "bug17564"\n/,
        /=> "bug17564"\n/,
        /   => "hi"\n/,
        /   => nil\n/,
        /=> "hi"\n/,
      ], out)
    end

    def test_help
      out, _ = execute_lines(
        "help 'String#gsub'\n",
        "\n",
      )

      # the former is what we'd get without document content installed, like on CI
      # the latter is what we may get locally
      possible_rdoc_output = [/Nothing known about String#gsub/, /Returns a copy of self with all occurrences of the given pattern/]
      assert(possible_rdoc_output.any? { |output| output.match?(out) }, "Expect the help command to match one of the possible outputs")
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/cmd/help.rb" }
    end

    def test_help_without_rdoc
      out, _ = without_rdoc do
        execute_lines(
          "help 'String#gsub'\n",
          "\n",
        )
      end

      # if it fails to require rdoc, it only returns the command object
      assert_match(/=> IRB::ExtendCommand::Help\n/, out)
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/cmd/help.rb" }
    end

    def test_irb_load
      File.write("#{@tmpdir}/a.rb", "a = 'hi'\n")
      out, err = execute_lines(
        "a = 'bug17564'\n",
        "a\n",
        "irb_load '#{@tmpdir}/a.rb'\n",
        "a\n",
      )
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
      out, err = execute_lines(
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
      )

      assert_empty err
      assert_match(/^instance variables:\s+@a\n/m, out)
      assert_match(/P#methods:\s+m\n/m, out)
      assert_match(/C#methods:\s+m2\n/m, out)
      assert_match(/M#methods:\s+m1\s+m3\n/m, out)
      assert_match(/M2#methods:\s+m4\n/m, out)
      assert_match(/C.methods:\s+m5\n/m, out)
    end

    def test_ls_grep
      pend if RUBY_ENGINE == 'truffleruby'
      out, err = execute_lines("ls 42\n")
      assert_empty err
      assert_match(/times/, out)
      assert_match(/polar/, out)

      [
        "ls 42, grep: /times/\n",
        "ls 42 -g times\n",
        "ls 42 -G times\n",
      ].each do |line|
        out, err = execute_lines(line)
        assert_empty err
        assert_match(/times/, out)
        assert_not_match(/polar/, out)
      end
    end

    def test_ls_grep_empty
      pend if RUBY_ENGINE == 'truffleruby'
      out, err = execute_lines("ls\n")
      assert_empty err
      assert_match(/whereami/, out)
      assert_match(/show_source/, out)

      [
        "ls grep: /whereami/\n",
        "ls -g whereami\n",
        "ls -G whereami\n",
      ].each do |line|
        out, err = execute_lines(line)
        assert_empty err
        assert_match(/whereami/, out)
        assert_not_match(/show_source/, out)
      end
    end

    def test_ls_with_no_singleton_class
      out, err = execute_lines(
        "ls 42",
      )
      assert_empty err
      assert_match(/Comparable#methods:\s+/, out)
      assert_match(/Numeric#methods:\s+/, out)
      assert_match(/Integer#methods:\s+/, out)
    end

    def test_show_source
      out, err = execute_lines(
        "show_source IRB.conf\n",
      )
      assert_empty err
      assert_match(%r[/irb\.rb], out)
    end

    def test_show_source_method
      out, err = execute_lines(
        "p show_source('IRB.conf')\n",
      )
      assert_empty err
      assert_match(%r[/irb\.rb], out)
    end

    def test_show_source_string
      out, err = execute_lines(
        "show_source 'IRB.conf'\n",
      )
      assert_empty err
      assert_match(%r[/irb\.rb], out)
    end

    def test_show_source_alias
      out, err = execute_lines(
        "$ 'IRB.conf'\n",
        conf: { COMMAND_ALIASES: { :'$' => :show_source } }
      )
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

      out, err = execute_lines(
        "show_source 'TestIRB::ExtendCommandTest#show_source_test_method'\n",
      )

      assert_empty err
      assert_include(out, code)
    end

    def test_whereami
      out, err = execute_lines(
        "whereami\n",
      )
      assert_empty err
      assert_match(/^From: .+ @ line \d+ :\n/, out)
    end

    def test_whereami_alias
      out, err = execute_lines(
        "@\n",
      )
      assert_empty err
      assert_match(/^From: .+ @ line \d+ :\n/, out)
    end

    def test_vars_with_aliases
      @foo = "foo"
      $bar = "bar"
      out, err = execute_lines(
        "@foo\n",
        "$bar\n",
      )
      assert_empty err
      assert_match(/"foo"/, out)
      assert_match(/"bar"/, out)
    ensure
      remove_instance_variable(:@foo)
      $bar = nil
    end

    private

    def execute_lines(*lines, conf: {}, main: self)
      IRB.init_config(nil)
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      IRB.conf.merge!(conf)
      input = TestInputMethod.new(lines)
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
      irb.context.return_format = "=> %s\n"
      IRB.conf[:MAIN_CONTEXT] = irb.context
      capture_output do
        irb.eval_input
      end
    end
  end
end
