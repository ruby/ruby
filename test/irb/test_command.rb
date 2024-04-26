# frozen_string_literal: false
require "irb"

require_relative "helper"

module TestIRB
  class CommandTestCase < TestCase
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
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
      @is_win = (RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/)
    end

    def teardown
      ENV["XDG_CONFIG_HOME"] = @xdg_config_home_backup
      ENV["HOME"] = @home_backup
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
      restore_encodings
    end

    def execute_lines(*lines, conf: {}, main: self, irb_path: nil)
      capture_output do
        IRB.init_config(nil)
        IRB.conf[:VERBOSE] = false
        IRB.conf[:PROMPT_MODE] = :SIMPLE
        IRB.conf[:USE_PAGER] = false
        IRB.conf.merge!(conf)
        input = TestInputMethod.new(lines)
        irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
        irb.context.return_format = "=> %s\n"
        irb.context.irb_path = irb_path if irb_path
        IRB.conf[:MAIN_CONTEXT] = irb.context
        irb.eval_input
      end
    end
  end

  class FrozenObjectTest < CommandTestCase
    def test_calling_command_on_a_frozen_main
      main = Object.new.freeze

      out, err = execute_lines(
        "irb_info",
        main: main
      )
      assert_empty(err)
      assert_match(/RUBY_PLATFORM/, out)
    end
  end

  class InfoTest < CommandTestCase
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
      FileUtils.touch("#{@tmpdir}/_irbrc")

      out, err = execute_lines(
        "irb_info",
        conf: { USE_MULTILINE: true, USE_SINGLELINE: false }
      )

      expected = %r{
        Ruby\sversion:\s.+\n
        IRB\sversion:\sirb\s.+\n
        InputMethod:\sAbstract\sInputMethod\n
        Completion: .+\n
        \.irbrc\spaths:.*\.irbrc.*_irbrc\n
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
        Completion: .+\n
        \.irbrc\spaths:\s.+\n
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
        Completion: .+\n
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
        Completion: .+\n
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
        Completion: .+\n
        \.irbrc\spaths: .+\n
        RUBY_PLATFORM: .+\n
        LANG\senv:\sja_JP\.UTF-8\n
        LC_ALL\senv:\sen_US\.UTF-8\n
        East\sAsian\sAmbiguous\sWidth:\s\d\n
      }x

      assert_empty err
      assert_match expected, out
    end
  end

  class MeasureTest < CommandTestCase
    def test_measure
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false
      }

      c = Class.new(Object)
      out, err = execute_lines(
        "measure\n",
        "3\n",
        "measure :off\n",
        "3\n",
        "measure :on\n",
        "3\n",
        "measure :off\n",
        "3\n",
        conf: conf,
        main: c
      )

      assert_empty err
      assert_match(/\A(TIME is added\.\n=> nil\nprocessing time: .+\n=> 3\n=> nil\n=> 3\n){2}/, out)
      assert_empty(c.class_variables)
    end

    def test_measure_keeps_previous_value
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false
      }

      c = Class.new(Object)
      out, err = execute_lines(
        "measure\n",
        "3\n",
        "_\n",
        conf: conf,
        main: c
      )

      assert_empty err
      assert_match(/\ATIME is added\.\n=> nil\nprocessing time: .+\n=> 3\nprocessing time: .+\n=> 3/, out)
      assert_empty(c.class_variables)
    end

    def test_measure_enabled_by_rc
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> '
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
            PROMPT_C: '> '
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
            PROMPT_C: '> '
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

    def test_measure_toggle
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false,
        MEASURE_PROC: {
          FOO: proc { |&block| puts 'foo'; block.call },
          BAR: proc { |&block| puts 'bar'; block.call }
        }
      }
      out, err = execute_lines(
        "measure :foo\n",
        "1\n",
        "measure :on, :bar\n",
        "2\n",
        "measure :off, :foo\n",
        "3\n",
        "measure :off, :bar\n",
        "4\n",
        conf: conf
      )

      assert_empty err
      assert_match(/\AFOO is added\.\n=> nil\nfoo\n=> 1\nBAR is added\.\n=> nil\nbar\nfoo\n=> 2\n=> nil\nbar\n=> 3\n=> nil\n=> 4\n/, out)
    end

    def test_measure_with_proc_warning
      conf = {
        PROMPT: {
          DEFAULT: {
            PROMPT_I: '> ',
            PROMPT_S: '> ',
            PROMPT_C: '> '
          }
        },
        PROMPT_MODE: :DEFAULT,
        MEASURE: false,
      }
      c = Class.new(Object)
      out, err = execute_lines(
        "3\n",
        "measure do\n",
        "3\n",
        conf: conf,
        main: c
      )

      assert_match(/to add custom measure/, err)
      assert_match(/\A=> 3\n=> nil\n=> 3\n/, out)
      assert_empty(c.class_variables)
    end
  end

  class IrbSourceTest < CommandTestCase
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

    def test_irb_source_without_argument
      out, err = execute_lines(
        "irb_source\n",
      )
      assert_empty err
      assert_match(/Please specify the file name./, out)
    end
  end

  class IrbLoadTest < CommandTestCase
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

    def test_irb_load_without_argument
      out, err = execute_lines(
        "irb_load\n",
      )

      assert_empty err
      assert_match(/Please specify the file name./, out)
    end
  end

  class WorkspaceCommandTestCase < CommandTestCase
    def setup
      super
      # create Foo under the test class's namespace so it doesn't pollute global namespace
      self.class.class_eval <<~RUBY
        class Foo; end
      RUBY
    end
  end

  class CwwsTest < WorkspaceCommandTestCase
    def test_cwws_returns_the_current_workspace_object
      out, err = execute_lines(
        "cwws",
        "self.class"
      )

      assert_empty err
      assert_include(out, self.class.name)
    end
  end

  class PushwsTest < WorkspaceCommandTestCase
    def test_pushws_switches_to_new_workspace_and_pushes_the_current_one_to_the_stack
      out, err = execute_lines(
        "pushws #{self.class}::Foo.new",
        "self.class",
        "popws",
        "self.class"
      )
      assert_empty err

      assert_match(/=> #{self.class}::Foo\n/, out)
      assert_match(/=> #{self.class}\n$/, out)
    end

    def test_pushws_extends_the_new_workspace_with_command_bundle
      out, err = execute_lines(
        "pushws Object.new",
        "self.singleton_class.ancestors"
      )
      assert_empty err
      assert_include(out, "IRB::ExtendCommandBundle")
    end

    def test_pushws_prints_workspace_stack_when_no_arg_is_given
      out, err = execute_lines(
        "pushws",
      )
      assert_empty err
      assert_include(out, "[#<TestIRB::PushwsTe...>]")
    end

    def test_pushws_without_argument_swaps_the_top_two_workspaces
      out, err = execute_lines(
        "pushws #{self.class}::Foo.new",
        "self.class",
        "pushws",
        "self.class"
      )
      assert_empty err
      assert_match(/=> #{self.class}::Foo\n/, out)
      assert_match(/=> #{self.class}\n$/, out)
    end
  end

  class WorkspacesTest < WorkspaceCommandTestCase
    def test_workspaces_returns_the_stack_of_workspaces
      out, err = execute_lines(
        "pushws #{self.class}::Foo.new\n",
        "workspaces",
      )

      assert_empty err
      assert_match(/\[#<TestIRB::Workspac...>, #<TestIRB::Workspac...>\]\n/, out)
    end
  end

  class PopwsTest < WorkspaceCommandTestCase
    def test_popws_replaces_the_current_workspace_with_the_previous_one
      out, err = execute_lines(
        "pushws Foo.new\n",
        "popws\n",
        "cwws\n",
        "_.class",
      )
      assert_empty err
      assert_include(out, "=> #{self.class}")
    end

    def test_popws_prints_help_message_if_the_workspace_is_empty
      out, err = execute_lines(
        "popws\n",
      )
      assert_empty err
      assert_match(/\[#<TestIRB::PopwsTes...>\]\n/, out)
    end
  end

  class ChwsTest < WorkspaceCommandTestCase
    def test_chws_replaces_the_current_workspace
      out, err = execute_lines(
        "chws #{self.class}::Foo.new\n",
        "cwws\n",
        "_.class",
      )
      assert_empty err
      assert_include(out, "=> #{self.class}::Foo")
    end

    def test_chws_does_nothing_when_receiving_no_argument
      out, err = execute_lines(
        "chws\n",
        "cwws\n",
        "_.class",
      )
      assert_empty err
      assert_include(out, "=> #{self.class}")
    end
  end

  class WhereamiTest < CommandTestCase
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
  end

  class LsTest < CommandTestCase
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

    def test_ls_class
      out, err = execute_lines(
        "module M1\n",
        "  def m2; end\n",
        "  def m3; end\n",
        "end\n",

        "class C1\n",
        "  def m1; end\n",
        "  def m2; end\n",
        "end\n",

        "class C2 < C1\n",
        "  include M1\n",
        "  def m3; end\n",
        "  def m4; end\n",
        "  def self.m3; end\n",
        "  def self.m5; end\n",
        "end\n",
        "ls C2"
      )

      assert_empty err
      assert_match(/C2.methods:\s+m3\s+m5\n/, out)
      assert_match(/C2#methods:\s+m3\s+m4\n.*M1#methods:\s+m2\n.*C1#methods:\s+m1\n/, out)
      assert_not_match(/Module#methods/, out)
      assert_not_match(/Class#methods/, out)
    end

    def test_ls_module
      out, err = execute_lines(
        "module M1\n",
        "  def m1; end\n",
        "  def m2; end\n",
        "end\n",

        "module M2\n",
        "  include M1\n",
        "  def m1; end\n",
        "  def m3; end\n",
        "  def self.m4; end\n",
        "end\n",
        "ls M2"
      )

      assert_empty err
      assert_match(/M2\.methods:\s+m4\n/, out)
      assert_match(/M2#methods:\s+m1\s+m3\n.*M1#methods:\s+m2\n/, out)
      assert_not_match(/Module#methods/, out)
    end

    def test_ls_instance
      out, err = execute_lines(
        "class Foo; def bar; end; end\n",
        "ls Foo.new"
      )

      assert_empty err
      assert_match(/Foo#methods:\s+bar/, out)
      # don't duplicate
      assert_not_match(/Foo#methods:\s+bar\n.*Foo#methods/, out)
    end

    def test_ls_grep
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
      out, err = execute_lines("ls\n")
      assert_empty err
      assert_match(/assert/, out)
      assert_match(/refute/, out)

      [
        "ls grep: /assert/\n",
        "ls -g assert\n",
        "ls -G assert\n",
      ].each do |line|
        out, err = execute_lines(line)
        assert_empty err
        assert_match(/assert/, out)
        assert_not_match(/refute/, out)
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
  end

  class ShowDocTest < CommandTestCase
    def test_show_doc
      out, err = execute_lines(
        "show_doc String#gsub\n",
        "\n",
      )

      # the former is what we'd get without document content installed, like on CI
      # the latter is what we may get locally
      possible_rdoc_output = [/Nothing known about String#gsub/, /gsub\(pattern\)/]
      assert_not_include err, "[Deprecation]"
      assert(possible_rdoc_output.any? { |output| output.match?(out) }, "Expect the `show_doc` command to match one of the possible outputs. Got:\n#{out}")
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/command/help.rb" }
    end

    def test_show_doc_without_rdoc
      out, err = without_rdoc do
        execute_lines(
          "show_doc String#gsub\n",
          "\n",
        )
      end

      # if it fails to require rdoc, it only returns the command object
      assert_match(/=> nil\n/, out)
      assert_include(err, "Can't display document because `rdoc` is not installed.\n")
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/command/help.rb" }
    end
  end

  class EditTest < CommandTestCase
    def setup
      @original_visual = ENV["VISUAL"]
      @original_editor = ENV["EDITOR"]
      # noop the command so nothing gets executed
      ENV["VISUAL"] = ": code"
      ENV["EDITOR"] = ": code2"
    end

    def teardown
      ENV["VISUAL"] = @original_visual
      ENV["EDITOR"] = @original_editor
    end

    def test_edit_without_arg
      out, err = execute_lines(
        "edit",
        irb_path: __FILE__
      )

      assert_empty err
      assert_match("path: #{__FILE__}", out)
      assert_match("command: ': code'", out)
    end

    def test_edit_without_arg_and_non_existing_irb_path
      out, err = execute_lines(
        "edit",
        irb_path: '/path/to/file.rb(irb)'
      )

      assert_empty err
      assert_match(/Can not find file: \/path\/to\/file\.rb\(irb\)/, out)
    end

    def test_edit_with_path
      out, err = execute_lines(
        "edit #{__FILE__}"
      )

      assert_empty err
      assert_match("path: #{__FILE__}", out)
      assert_match("command: ': code'", out)
    end

    def test_edit_with_non_existing_path
      out, err = execute_lines(
        "edit test_cmd_non_existing_path.rb"
      )

      assert_empty err
      assert_match(/Can not find file: test_cmd_non_existing_path\.rb/, out)
    end

    def test_edit_with_constant
      out, err = execute_lines(
        "edit IRB::Irb"
      )

      assert_empty err
      assert_match(/path: .*\/lib\/irb\.rb/, out)
      assert_match("command: ': code'", out)
    end

    def test_edit_with_class_method
      out, err = execute_lines(
        "edit IRB.start"
      )

      assert_empty err
      assert_match(/path: .*\/lib\/irb\.rb/, out)
      assert_match("command: ': code'", out)
    end

    def test_edit_with_instance_method
      out, err = execute_lines(
        "edit IRB::Irb#run"
      )

      assert_empty err
      assert_match(/path: .*\/lib\/irb\.rb/, out)
      assert_match("command: ': code'", out)
    end

    def test_edit_with_editor_env_var
      ENV.delete("VISUAL")

      out, err = execute_lines(
        "edit",
        irb_path: __FILE__
      )

      assert_empty err
      assert_match("path: #{__FILE__}", out)
      assert_match("command: ': code2'", out)
    end
  end

  class HistoryCmdTest < CommandTestCase
    def teardown
      TestInputMethod.send(:remove_const, "HISTORY") if defined?(TestInputMethod::HISTORY)
      super
    end

    def test_history
      TestInputMethod.const_set("HISTORY", %w[foo bar baz])

      out, err = without_rdoc do
        execute_lines("history")
      end

      assert_include(out, <<~EOF)
        2: baz
        1: bar
        0: foo
      EOF
      assert_empty err
    end

    def test_multiline_history_with_truncation
      TestInputMethod.const_set("HISTORY", ["foo", "bar", <<~INPUT])
        [].each do |x|
          puts x
        end
      INPUT

      out, err = without_rdoc do
        execute_lines("hist")
      end

      assert_include(out, <<~EOF)
        2: [].each do |x|
             puts x
           ...
        1: bar
        0: foo
      EOF
      assert_empty err
    end

    def test_history_grep
      TestInputMethod.const_set("HISTORY", ["foo", "bar", <<~INPUT])
        [].each do |x|
          puts x
        end
      INPUT

      out, err = without_rdoc do
        execute_lines("hist -g each\n")
      end

      assert_include(out, <<~EOF)
        2: [].each do |x|
             puts x
           ...
      EOF
      assert_empty err
    end

  end

  class HelperMethodInsallTest < CommandTestCase
    def test_helper_method_install
      IRB::ExtendCommandBundle.module_eval do
        def foobar
          "test_helper_method_foobar"
        end
      end

      out, err = execute_lines("foobar.upcase")
      assert_empty err
      assert_include(out, '=> "TEST_HELPER_METHOD_FOOBAR"')
    ensure
      IRB::ExtendCommandBundle.remove_method :foobar
    end
  end
end
