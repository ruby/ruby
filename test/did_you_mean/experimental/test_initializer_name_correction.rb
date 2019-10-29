require 'helper'
require 'stringio'

class InitializerNameCorrectionTest < Test::Unit::TestCase
  def test_corrects_wrong_initializer_name
    assert_output nil, "warning: intialize might be misspelled, perhaps you meant initialize?\n" do
      Class.new { def intialize; end }
    end
  end

  def test_does_not_correct_correct_initializer_name
    assert_output nil, "" do
      Class.new { def initialize; end }
    end
  end

  private

  # From: https://github.com/seattlerb/minitest/blob/381e9654/lib/minitest/assertions.rb#L329
  # Copyright © Ryan Davis, seattle.rb
  def assert_output(stdout = nil, stderr = nil, &block)
    flunk "assert_output requires a block to capture output." unless
      block_given?

    out, err = capture_io(&block)

    err_msg = Regexp === stderr ? :assert_match : :assert_equal if stderr
    out_msg = Regexp === stdout ? :assert_match : :assert_equal if stdout

    y = send err_msg, stderr, err, "In stderr" if err_msg
    x = send out_msg, stdout, out, "In stdout" if out_msg

    (!stdout || x) && (!stderr || y)
  end

  # From: https://github.com/seattlerb/minitest/blob/381e9654/lib/minitest/assertions.rb#L505
  # Copyright © Ryan Davis, seattle.rb
  def capture_io
    captured_stdout, captured_stderr = StringIO.new, StringIO.new

    orig_stdout, orig_stderr = $stdout, $stderr
    $stdout, $stderr         = captured_stdout, captured_stderr

    yield

    return captured_stdout.string, captured_stderr.string
  ensure
    $stdout = orig_stdout
    $stderr = orig_stderr
  end
end
