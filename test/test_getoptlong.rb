require 'test/unit'
require 'getoptlong'

class TestGetoptLong < Test::Unit::TestCase

  def verify(test_argv, expected_remaining_argv, expected_options)
    # Save ARGV and replace it with a test ARGV.
    argv_saved = ARGV.dup
    ARGV.replace(test_argv)
    # Define options.
    opts = GetoptLong.new(
      ['--xxx', '-x', '--aaa', '-a', GetoptLong::REQUIRED_ARGUMENT],
      ['--yyy', '-y', '--bbb', '-b', GetoptLong::OPTIONAL_ARGUMENT],
      ['--zzz', '-z', '--ccc', '-c', GetoptLong::NO_ARGUMENT]
    )
    opts.quiet = true
    # Gather options.
    actual_options = []
    opts.each do |opt, arg|
      actual_options << "#{opt}: #{arg}"
    end
    # Save remaining test ARGV and restore original ARGV.
    actual_remaining_argv = ARGV.dup
    ARGV.replace(argv_saved)
    # Assert.
    assert_equal(expected_remaining_argv, actual_remaining_argv, 'ARGV')
    assert_equal(expected_options, actual_options, 'Options')
  end

  def test_no_options
    expected_options = []
    expected_argv = %w[foo bar]
    argv = %w[foo bar]
    verify(argv, expected_argv, expected_options)
  end

  def test_required_argument
    expected_options = [
      '--xxx: arg'
    ]
    expected_argv = %w[foo bar]
    options = %w[--xxx --xx --x -x --aaa --aa --a -a]
    options.each do |option|
      argv = ['foo', option, 'arg', 'bar']
      verify(argv, expected_argv, expected_options)
    end
  end

  def test_required_argument_missing
    options = %w[--xxx --xx --x -x --aaa --aa --a -a]
    options.each do |option|
      argv = [option]
      e = assert_raise(GetoptLong::MissingArgument) do
        verify(argv, [], [])
      end
      assert_match('requires an argument', e.message)
    end
  end

  def test_optional_argument
    expected_options = [
      '--yyy: arg'
    ]
    expected_argv = %w[foo bar]
    options = %w[--yyy --y --y -y --bbb --bb --b -b]
    options.each do |option|
      argv = ['foo', 'bar', option, 'arg']
      verify(argv, expected_argv, expected_options)
    end
  end

  def test_optional_argument_missing
    expected_options = [
      '--yyy: '
    ]
    expected_argv = %w[foo bar]
    options = %w[--yyy --y --y -y --bbb --bb --b -b]
    options.each do |option|
      argv = ['foo', 'bar', option]
      verify(argv, expected_argv, expected_options)
    end
  end

  def test_no_argument
    expected_options = [
      '--zzz: '
    ]
    expected_argv = %w[foo bar]
    options = %w[--zzz --zz --z -z --ccc --cc --c -c]
    options.each do |option|
      argv = ['foo', option, 'bar']
      verify(argv, expected_argv, expected_options)
    end
  end

  def test_new_with_empty_array
    e = assert_raise(ArgumentError) do
      GetoptLong.new([])
    end
    assert_match(/no argument-flag/, e.message)
  end

  def test_new_with_bad_array
    e = assert_raise(ArgumentError) do
      GetoptLong.new('foo')
    end
    assert_match(/option list contains non-Array argument/, e.message)
  end

  def test_new_with_empty_subarray
    e = assert_raise(ArgumentError) do
      GetoptLong.new([[]])
    end
    assert_match(/no argument-flag/, e.message)
  end

  def test_new_with_bad_subarray
    e = assert_raise(ArgumentError) do
      GetoptLong.new([1])
    end
    assert_match(/no option name/, e.message)
  end

  def test_new_with_invalid_option
    invalid_options = %w[verbose -verbose -- +]
    invalid_options.each do |invalid_option|
      e = assert_raise(ArgumentError, invalid_option.to_s) do
        arguments = [
          [invalid_option, '-v', GetoptLong::NO_ARGUMENT]
        ]
        GetoptLong.new(*arguments)
      end
      assert_match(/invalid option/, e.message)
    end
  end

  def test_new_with_invalid_alias
    invalid_aliases = %w[v - -- +]
    invalid_aliases.each do |invalid_alias|
      e = assert_raise(ArgumentError, invalid_alias.to_s) do
        arguments = [
          ['--verbose', invalid_alias, GetoptLong::NO_ARGUMENT]
        ]
        GetoptLong.new(*arguments)
      end
      assert_match(/invalid option/, e.message)
    end
  end

  def test_new_with_invalid_flag
    invalid_flags = ['foo']
    invalid_flags.each do |invalid_flag|
      e = assert_raise(ArgumentError, invalid_flag.to_s) do
        arguments = [
          ['--verbose', '-v', invalid_flag]
        ]
        GetoptLong.new(*arguments)
      end
      assert_match(/no argument-flag/, e.message)
    end
  end

end
