# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestBugReporter < Test::Unit::TestCase
  def test_bug_reporter_add
    expected_stderr = [
      :*,
      /\[BUG\]\sSegmentation\sfault.*\n/,
      /#{ Regexp.quote(RUBY_DESCRIPTION) }\n\n/,
      :*,
      /Sample bug reporter: 12345/,
      :*
    ]
    tmpdir = Dir.mktmpdir

    args = ["--disable-gems", "-r-test-/bug_reporter/bug_reporter",
            "-C", tmpdir]
    stdin = "register_sample_bug_reporter(12345); Process.kill :SEGV, $$"
    assert_in_out_err(args, stdin, [], expected_stderr, encoding: "ASCII-8BIT")
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
