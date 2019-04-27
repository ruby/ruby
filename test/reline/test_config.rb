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
  end

  def test_read_lines
    @config.read_lines(<<~LINES.split(/(?<=\n)/))
      set bell-style on
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_bind_key
    key, func = @config.bind_key('"input"', '"abcde"')

    assert_equal 'input', key
    assert_equal 'abcde', func
  end

  def test_bind_key_with_macro
    key, func = @config.bind_key('"input"', 'abcde')

    assert_equal 'input', key
    assert_equal :abcde, func
  end

  def test_bind_key_with_escaped_chars
    assert_equal ['input', "\e \\ \" ' \a \b \d \f \n \r \t \v"], @config.bind_key('"input"', '"\\e \\\\ \\" \\\' \\a \\b \\d \\f \\n \\r \\t \\v"')
  end

  def test_bind_key_with_ctrl_chars
    assert_equal ['input', "\C-h\C-h"], @config.bind_key('"input"', '"\C-h\C-H"')
  end

  def test_bind_key_with_meta_chars
    assert_equal ['input', "\M-h\M-H".force_encoding('ASCII-8BIT')], @config.bind_key('"input"', '"\M-h\M-H"')
  end

  def test_bind_key_with_octal_number
    assert_equal ['input', "\1"], @config.bind_key('"input"', '"\1"')
    assert_equal ['input', "\12"], @config.bind_key('"input"', '"\12"')
    assert_equal ['input', "\123"], @config.bind_key('"input"', '"\123"')
    assert_equal ['input', ["\123", '4'].join], @config.bind_key('"input"', '"\1234"')
  end

  def test_bind_key_with_hexadecimal_number
    assert_equal ['input', "\x4"], @config.bind_key('"input"', '"\x4"')
    assert_equal ['input', "\x45"], @config.bind_key('"input"', '"\x45"')
    assert_equal ['input', ["\x45", '6'].join], @config.bind_key('"input"', '"\x456"')
  end

  def test_include
    File.open('included_partial', 'wt') do |f|
      f.write(<<~PARTIAL_LINES)
        set bell-style on
      PARTIAL_LINES
    end
    @config.read_lines(<<~LINES.split(/(?<=\n)/))
      $include included_partial
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_if
    @config.read_lines(<<~LINES.split(/(?<=\n)/))
      $if Ruby
      set bell-style audible
      $else
      set bell-style visible
      $endif
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end

  def test_if_with_false
    @config.read_lines(<<~LINES.split(/(?<=\n)/))
      $if Python
      set bell-style audible
      $else
      set bell-style visible
      $endif
    LINES

    assert_equal :visible, @config.instance_variable_get(:@bell_style)
  end

  def test_if_with_indent
    @config.read_lines(<<~LINES.split(/(?<=\n)/))
      set bell-style none
        $if Ruby
          set bell-style audible
        $else
          set bell-style visible
        $endif
    LINES

    assert_equal :audible, @config.instance_variable_get(:@bell_style)
  end
end
