require 'test/unit'
require 'tmpdir'
require_relative "../../ruby/envutil"

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
    stdin = "register_sample_bug_reporter(12345); Process.kill :SEGV, $$; sleep"
    _, stderr, status = EnvUtil.invoke_ruby(args, stdin, false, true)
    assert_pattern_list(expected_stderr, stderr)
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
