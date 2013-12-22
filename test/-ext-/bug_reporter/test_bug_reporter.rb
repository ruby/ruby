require 'test/unit'
require 'tmpdir'
require_relative "../../ruby/envutil"

class TestBugReporter < Test::Unit::TestCase
  def test_bug_reporter_add
    expected_stderr = /Sample bug reporter: 12345/
    tmpdir = Dir.mktmpdir
    assert_in_out_err(["--disable-gems", "-r-test-/bug_reporter/bug_reporter",
                       "-C", tmpdir],
                      "register_sample_bug_reporter(12345); Process.kill :SEGV, $$",
                      [],
                      expected_stderr, nil)
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
