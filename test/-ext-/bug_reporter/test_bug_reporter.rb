# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestBugReporter < Test::Unit::TestCase
  def test_bug_reporter_add
    omit if ENV['RUBY_ON_BUG']

    description = RUBY_DESCRIPTION
    expected_stderr = [
      :*,
      /\[BUG\]\sSegmentation\sfault.*\n/,
      /#{ Regexp.quote(description) }\n\n/,
      :*,
      /Sample bug reporter: 12345/,
      :*
    ]
    tmpdir = Dir.mktmpdir

    no_core = "Process.setrlimit(Process::RLIMIT_CORE, 0); " if defined?(Process.setrlimit) && defined?(Process::RLIMIT_CORE)
    args = ["--disable-gems", "-r-test-/bug_reporter",
            "-C", tmpdir]
    stdin = "#{no_core}register_sample_bug_reporter(12345); Process.kill :SEGV, $$"
    assert_in_out_err(args, stdin, [], expected_stderr, encoding: "ASCII-8BIT")
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
