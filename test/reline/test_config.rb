require_relative 'helper'

class Reline::Config::Test < Reline::TestCase
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
    Reline.test_mode
    @config = Reline::Config.new
  end

  def teardown
    Dir.chdir(@pwd)
    FileUtils.rm_rf(@tmpdir)
    Reline.test_reset
    @config.reset
  end

  def test_read_lines
    @config.read_lines(<<~LINES.lines)
      set bell-style on
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_read_lines_with_variable
    @config.read_lines(<<~LINES.lines)
      set disable-completion on
    LINES

    assert_equal true, @config.instance_variable_get(:@disable_completion)
  end

  def test_string_value
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string Emacs
    LINES

    assert_equal 'Emacs', @config.instance_variable_get(:@emacs_mode_string)
  end

  def test_string_value_with_brackets
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string [Emacs]
    LINES

    assert_equal '[Emacs]', @config.instance_variable_get(:@emacs_mode_string)
  end

  def test_string_value_with_brackets_and_quotes
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string "[Emacs]"
    LINES

    assert_equal '[Emacs]', @config.instance_variable_get(:@emacs_mode_string)
  end

  def test_string_value_with_parens
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string (Emacs)
    LINES

    assert_equal '(Emacs)', @config.instance_variable_get(:@emacs_mode_string)
  end

  def test_string_value_with_parens_and_quotes
    @config.read_lines(<<~LINES.lines)
      set show-mode-in-prompt on
      set emacs-mode-string "(Emacs)"
    LINES

    assert_equal '(Emacs)', @config.instance_variable_get(:@emacs_mode_string)
  end

  def test_encoding_is_ascii
    @config.reset
    Reline.core.io_gate.reset(encoding: Encoding::US_ASCII)
    @config = Reline::Config.new

    assert_equal true, @config.convert_meta
  end

  def test_encoding_is_not_ascii
    @config.reset
    Reline.core.io_gate.reset(encoding: Encoding::UTF_8)
    @config = Reline::Config.new

    assert_equal nil, @config.convert_meta
  end

  def test_comment_line
    @config.read_lines([" #a: error\n"])
    assert_not_include @config.key_bindings, nil
  end

  def test_invalid_keystroke
    @config.read_lines(["a: error\n"])
    assert_not_include @config.key_bindings, nil
  end

  def test_bind_key
    assert_equal ['input'.bytes, 'abcde'.bytes], @config.bind_key('"input"', '"abcde"')
  end

  def test_bind_key_with_macro

    assert_equal ['input'.bytes, :abcde], @config.bind_key('"input"', 'abcde')
  end

  def test_bind_key_with_escaped_chars
    assert_equal ['input'.bytes, "\e \\ \" ' \a \b \d \f \n \r \t \v".bytes], @config.bind_key('"input"', '"\\e \\\\ \\" \\\' \\a \\b \\d \\f \\n \\r \\t \\v"')
  end

  def test_bind_key_with_ctrl_chars
    assert_equal ['input'.bytes, "\C-h\C-h".bytes], @config.bind_key('"input"', '"\C-h\C-H"')
    assert_equal ['input'.bytes, "\C-h\C-h".bytes], @config.bind_key('"input"', '"\Control-h\Control-H"')
  end

  def test_bind_key_with_meta_chars
    assert_equal ['input'.bytes, "\M-h\M-H".bytes], @config.bind_key('"input"', '"\M-h\M-H"')
    assert_equal ['input'.bytes, "\M-h\M-H".bytes], @config.bind_key('"input"', '"\Meta-h\Meta-H"')
  end

  def test_bind_key_with_octal_number
    input = %w{i n p u t}.map(&:ord)
    assert_equal [input, "\1".bytes], @config.bind_key('"input"', '"\1"')
    assert_equal [input, "\12".bytes], @config.bind_key('"input"', '"\12"')
    assert_equal [input, "\123".bytes], @config.bind_key('"input"', '"\123"')
    assert_equal [input, "\123".bytes + '4'.bytes], @config.bind_key('"input"', '"\1234"')
  end

  def test_bind_key_with_hexadecimal_number
    input = %w{i n p u t}.map(&:ord)
    assert_equal [input, "\x4".bytes], @config.bind_key('"input"', '"\x4"')
    assert_equal [input, "\x45".bytes], @config.bind_key('"input"', '"\x45"')
    assert_equal [input, "\x45".bytes + '6'.bytes], @config.bind_key('"input"', '"\x456"')
  end

  def test_include
    File.open('included_partial', 'wt') do |f|
      f.write(<<~PARTIAL_LINES)
        set bell-style on
      PARTIAL_LINES
    end
    @config.read_lines(<<~LINES.lines)
      $include included_partial
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_include_expand_path
    home_backup = ENV['HOME']
    File.open('included_partial', 'wt') do |f|
      f.write(<<~PARTIAL_LINES)
        set bell-style on
      PARTIAL_LINES
    end
    ENV['HOME'] = Dir.pwd
    @config.read_lines(<<~LINES.lines)
      $include ~/included_partial
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  ensure
    ENV['HOME'] = home_backup
  end

  def test_if
    @config.read_lines(<<~LINES.lines)
      $if Ruby
      set bell-style audible
      $else
      set bell-style visible
      $endif
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_if_with_false
    @config.read_lines(<<~LINES.lines)
      $if Python
      set bell-style audible
      $else
      set bell-style visible
      $endif
    LINES

    assert_equal :visible, @config.instance_variable_get(:@bell_style)
  end

  def test_if_with_indent
    %w[Ruby Reline].each do |cond|
      @config.read_lines(<<~LINES.lines)
        set bell-style none
          $if #{cond}
            set bell-style audible
          $else
            set bell-style visible
          $endif
      LINES

      assert_equal :audible, @config.instance_variable_get(:@bell_style)
    end
  end

  def test_unclosed_if
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $if Ruby
      LINES
    end
    assert_equal "INPUTRC:1: unclosed if", e.message
  end

  def test_unmatched_else
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $else
      LINES
    end
    assert_equal "INPUTRC:1: unmatched else", e.message
  end

  def test_unmatched_endif
    e = assert_raise(Reline::Config::InvalidInputrc) do
      @config.read_lines(<<~LINES.lines, "INPUTRC")
        $endif
      LINES
    end
    assert_equal "INPUTRC:1: unmatched endif", e.message
  end

  def test_default_key_bindings
    @config.add_default_key_binding('abcd'.bytes, 'EFGH'.bytes)
    @config.read_lines(<<~'LINES'.lines)
      "abcd": "ABCD"
      "ijkl": "IJKL"
    LINES

    expected = { 'abcd'.bytes => 'ABCD'.bytes, 'ijkl'.bytes => 'IJKL'.bytes }
    assert_equal expected, @config.key_bindings
  end

  def test_additional_key_bindings
    @config.read_lines(<<~'LINES'.lines)
      "ef": "EF"
      "gh": "GH"
    LINES

    expected = { 'ef'.bytes => 'EF'.bytes, 'gh'.bytes => 'GH'.bytes }
    assert_equal expected, @config.key_bindings
  end

  def test_additional_key_bindings_with_nesting_and_comment_out
    @config.read_lines(<<~'LINES'.lines)
      #"ab": "AB"
        #"cd": "cd"
      "ef": "EF"
        "gh": "GH"
    LINES

    expected = { 'ef'.bytes => 'EF'.bytes, 'gh'.bytes => 'GH'.bytes }
    assert_equal expected, @config.key_bindings
  end

  def test_additional_key_bindings_for_other_keymap
    @config.read_lines(<<~'LINES'.lines)
      set keymap vi-command
      "ab": "AB"
      set keymap vi-insert
      "cd": "CD"
      set keymap emacs
      "ef": "EF"
      set editing-mode vi # keymap changes to be vi-insert
    LINES

    expected = { 'cd'.bytes => 'CD'.bytes }
    assert_equal expected, @config.key_bindings
  end

  def test_additional_key_bindings_for_auxiliary_emacs_keymaps
    @config.read_lines(<<~'LINES'.lines)
      set keymap emacs
      "ab": "AB"
      set keymap emacs-standard
      "cd": "CD"
      set keymap emacs-ctlx
      "ef": "EF"
      set keymap emacs-meta
      "gh": "GH"
      set editing-mode emacs # keymap changes to be emacs
    LINES

    expected = {
      'ab'.bytes => 'AB'.bytes,
      'cd'.bytes => 'CD'.bytes,
      "\C-xef".bytes => 'EF'.bytes,
      "\egh".bytes => 'GH'.bytes,
    }
    assert_equal expected, @config.key_bindings
  end

  def test_history_size
    @config.read_lines(<<~LINES.lines)
      set history-size 5000
    LINES

    assert_equal 5000, @config.instance_variable_get(:@history_size)
    history = Reline::History.new(@config)
    history << "a\n"
    assert_equal 1, history.size
  end

  def test_empty_inputrc_env
    inputrc_backup = ENV['INPUTRC']
    ENV['INPUTRC'] = ''
    assert_nothing_raised do
      @config.read
    end
  ensure
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_inputrc
    inputrc_backup = ENV['INPUTRC']
    expected = "#{@tmpdir}/abcde"
    ENV['INPUTRC'] = expected
    assert_equal expected, @config.inputrc_path
  ensure
    ENV['INPUTRC'] = inputrc_backup
  end

  def test_inputrc_with_utf8
    # This file is encoded by UTF-8 so this heredoc string is also UTF-8.
    @config.read_lines(<<~'LINES'.lines)
      set editing-mode vi
      set vi-cmd-mode-string 🍸
      set vi-ins-mode-string 🍶
    LINES
    assert_equal '🍸', @config.vi_cmd_mode_string
    assert_equal '🍶', @config.vi_ins_mode_string
  rescue Reline::ConfigEncodingConversionError
    # do nothing
  end

  def test_inputrc_with_eucjp
    @config.read_lines(<<~"LINES".encode(Encoding::EUC_JP).lines)
      set editing-mode vi
      set vi-cmd-mode-string ｫｬｯ
      set vi-ins-mode-string 能
    LINES
    assert_equal 'ｫｬｯ'.encode(Reline.encoding_system_needs), @config.vi_cmd_mode_string
    assert_equal '能'.encode(Reline.encoding_system_needs), @config.vi_ins_mode_string
  rescue Reline::ConfigEncodingConversionError
    # do nothing
  end

  def test_empty_inputrc
    assert_nothing_raised do
      @config.read_lines([])
    end
  end

  def test_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    xdg_config_home = File.expand_path("#{@tmpdir}/.config/example_dir")
    expected = File.expand_path("#{xdg_config_home}/readline/inputrc")
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    ENV['HOME'] = @tmpdir
    ENV['XDG_CONFIG_HOME'] = xdg_config_home
    assert_equal expected, @config.inputrc_path
  ensure
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
  end

  def test_empty_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    ENV['HOME'] = @tmpdir
    ENV['XDG_CONFIG_HOME'] = ''
    expected = File.expand_path('~/.config/readline/inputrc')
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    assert_equal expected, @config.inputrc_path
  ensure
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
  end

  def test_relative_xdg_config_home
    home_backup = ENV['HOME']
    xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    ENV['HOME'] = @tmpdir
    expected = File.expand_path('~/.config/readline/inputrc')
    FileUtils.mkdir_p(File.dirname(expected))
    FileUtils.touch(expected)
    result = Dir.chdir(@tmpdir) do
      xdg_config_home = ".config/example_dir"
      ENV['XDG_CONFIG_HOME'] = xdg_config_home
      inputrc = "#{xdg_config_home}/readline/inputrc"
      FileUtils.mkdir_p(File.dirname(inputrc))
      FileUtils.touch(inputrc)
      @config.inputrc_path
    end
    assert_equal expected, result
    FileUtils.rm(expected)
    ENV['XDG_CONFIG_HOME'] = xdg_config_home_backup
    ENV['HOME'] = home_backup
  end
end

