# frozen_string_literal: false
require "rubygems"
require "irb"
require "irb/extend-command"

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
      IRB.init_config(nil)
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      IRB.conf.merge!(conf)
      input = TestInputMethod.new(lines)
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
      irb.context.return_format = "=> %s\n"
      irb.context.irb_path = irb_path if irb_path
      IRB.conf[:MAIN_CONTEXT] = irb.context
      capture_output do
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
      assert_empty err
      assert_match(/RUBY_PLATFORM/, out)
    end
  end

  class CommnadAliasTest < CommandTestCase
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

  class MeasureTest < CommandTestCase
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

  class ShowSourceTest < CommandTestCase
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
        end unless defined?(show_source_test_method)
      EOS

      out, err = execute_lines(
        "show_source '#{self.class.name}#show_source_test_method'\n",
      )

      assert_empty err
      assert_include(out, code)
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
        "cwws.class",
      )

      assert_empty err
      assert_include(out, self.class.name)
    end
  end

  class PushwsTest < WorkspaceCommandTestCase
    def test_pushws_switches_to_new_workspace_and_pushes_the_current_one_to_the_stack
      out, err = execute_lines(
        "pushws #{self.class}::Foo.new\n",
        "cwws.class",
      )
      assert_empty err
      assert_include(out, "#{self.class}::Foo")
    end

    def test_pushws_extends_the_new_workspace_with_command_bundle
      out, err = execute_lines(
        "pushws Object.new\n",
        "self.singleton_class.ancestors"
      )
      assert_empty err
      assert_include(out, "IRB::ExtendCommandBundle")
    end

    def test_pushws_prints_help_message_when_no_arg_is_given
      out, err = execute_lines(
        "pushws\n",
      )
      assert_empty err
      assert_match(/No other workspace/, out)
    end
  end

  class WorkspacesTest < WorkspaceCommandTestCase
    def test_workspaces_returns_the_array_of_non_main_workspaces
      out, err = execute_lines(
        "pushws #{self.class}::Foo.new\n",
        "workspaces.map { |w| w.class.name }",
      )

      assert_empty err
      # self.class::Foo would be the current workspace
      # self.class would be the old workspace that's pushed to the stack
      assert_include(out, "=> [\"#{self.class}\"]")
    end

    def test_workspaces_returns_empty_array_when_no_workspaces_were_added
      out, err = execute_lines(
        "workspaces.map(&:to_s)",
      )

      assert_empty err
      assert_include(out, "=> []")
    end
  end

  class PopwsTest < WorkspaceCommandTestCase
    def test_popws_replaces_the_current_workspace_with_the_previous_one
      out, err = execute_lines(
        "pushws Foo.new\n",
        "popws\n",
        "cwws.class",
      )
      assert_empty err
      assert_include(out, "=> #{self.class}")
    end

    def test_popws_prints_help_message_if_the_workspace_is_empty
      out, err = execute_lines(
        "popws\n",
      )
      assert_empty err
      assert_match(/workspace stack empty/, out)
    end
  end

  class ChwsTest < WorkspaceCommandTestCase
    def test_chws_replaces_the_current_workspace
      out, err = execute_lines(
        "chws #{self.class}::Foo.new\n",
        "cwws.class",
      )
      assert_empty err
      assert_include(out, "=> #{self.class}::Foo")
    end

    def test_chws_does_nothing_when_receiving_no_argument
      out, err = execute_lines(
        "chws\n",
        "cwws.class",
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


  class ShowCmdsTest < CommandTestCase
    def test_show_cmds
      out, err = execute_lines(
        "show_cmds\n"
      )

      assert_empty err
      assert_match(/List all available commands and their description/, out)
      assert_match(/Start the debugger of debug\.gem/, out)
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
      assert_match(/M2\.methods:\s+m4\nModule#methods:/, out)
      assert_match(/M2#methods:\s+m1\s+m3\n.*M1#methods:\s+m2\n/, out)
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
  end

  class ShowDocTest < CommandTestCase
    def test_help_and_show_doc
      ["help", "show_doc"].each do |cmd|
        out, _ = execute_lines(
          "#{cmd} String#gsub\n",
          "\n",
        )

        # the former is what we'd get without document content installed, like on CI
        # the latter is what we may get locally
        possible_rdoc_output = [/Nothing known about String#gsub/, /gsub\(pattern\)/]
        assert(possible_rdoc_output.any? { |output| output.match?(out) }, "Expect the `#{cmd}` command to match one of the possible outputs. Got:\n#{out}")
      end
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/cmd/help.rb" }
    end

    def test_show_doc_without_rdoc
      out, _ = without_rdoc do
        execute_lines(
          "show_doc String#gsub\n",
          "\n",
        )
      end

      # if it fails to require rdoc, it only returns the command object
      assert_match(/=> IRB::ExtendCommand::Help\n/, out)
    ensure
      # this is the only way to reset the redefined method without coupling the test with its implementation
      EnvUtil.suppress_warning { load "irb/cmd/help.rb" }
    end
  end

  class EditTest < CommandTestCase
    def setup
      @original_editor = ENV["EDITOR"]
      # noop the command so nothing gets executed
      ENV["EDITOR"] = ": code"
    end

    def teardown
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
      # const_source_location is supported after Ruby 2.7
      omit if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0') || RUBY_ENGINE == 'truffleruby'

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
  end
end
