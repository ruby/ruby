require 'test/unit'
require_relative "../../ruby/envutil"

class TestBugReporter < Test::Unit::TestCase
  def test_bug_reporter_add
    expected_stderr = /Sample bug reporter: 12345/
    assert_in_out_err(["--disable-gems", "-r-test-/bug_reporter/bug_reporter", "-e", "register_sample_bug_reporter(12345); Process.kill :SEGV, $$"], "", [], expected_stderr, nil)
  end
end
