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
    @config = Reline::Config.new
  end

  def teardown
    Dir.chdir(@pwd)
    FileUtils.rm_rf(@tmpdir)
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
end
