# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'
require_relative '../../lib/jit_support'

class TestBugReporter < Test::Unit::TestCase
  def yjit_enabled?
    defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
  end

  def test_bug_reporter_add
    pend "macOS 15 is not working with this test" if /darwin/ =~ RUBY_PLATFORM && /15/ =~ `sw_vers -productVersion`

    omit if ENV['RUBY_ON_BUG']

    description = RUBY_DESCRIPTION
    description = description.sub(/\+MJIT /, '') unless JITSupport.mjit_force_enabled?
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
    args.push("--yjit") if yjit_enabled? # We want the printed description to match this process's RUBY_DESCRIPTION
    stdin = "#{no_core}register_sample_bug_reporter(12345); Process.kill :SEGV, $$"
    assert_in_out_err(args, stdin, [], expected_stderr, encoding: "ASCII-8BIT")
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
