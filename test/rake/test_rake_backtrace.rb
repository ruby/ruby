require File.expand_path('../helper', __FILE__)
require 'open3'

class TestRakeBacktrace < Rake::TestCase

  def setup
    super

    skip 'tmpdir is suppressed in backtrace' if
      Dir.pwd =~ Rake::Backtrace::SUPPRESS_PATTERN
  end

  # TODO: factor out similar code in test_rake_functional.rb
  def rake(*args)
    Open3.popen3(RUBY, "-I", @rake_lib, @rake_exec, *args) { |_, _, err, _|
      err.read
    }
  end

  def invoke(task_name)
    rake task_name.to_s
  end

  def test_single_collapse
    rakefile %q{
      task :foo do
        raise "foooo!"
      end
    }

    lines = invoke(:foo).split("\n")

    assert_equal "rake aborted!", lines[0]
    assert_equal "foooo!", lines[1]
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:3!i, lines
    assert_something_matches %r!\ATasks:!, lines
  end

  def test_multi_collapse
    rakefile %q{
      task :foo do
        Rake.application.invoke_task(:bar)
      end
      task :bar do
        raise "barrr!"
      end
    }

    lines = invoke(:foo).split("\n")

    assert_equal "rake aborted!", lines[0]
    assert_equal "barrr!", lines[1]
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:6!i, lines
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:3!i, lines
    assert_something_matches %r!\ATasks:!, lines
  end

  def test_suppress_option
    rakefile %q{
      task :baz do
        raise "bazzz!"
      end
    }

    lines = rake("baz").split("\n")
    assert_equal "rake aborted!", lines[0]
    assert_equal "bazzz!", lines[1]
    assert_something_matches %r!Rakefile!i, lines

    lines = rake("--suppress-backtrace", ".ak.file", "baz").split("\n")
    assert_equal "rake aborted!", lines[0]
    assert_equal "bazzz!", lines[1]
    refute_match %r!Rakefile!i, lines[2]
  end

  private

  # Assert that the pattern matches at least one line in +lines+.
  def assert_something_matches(pattern, lines)
    lines.each do |ln|
      if pattern =~ ln
        assert_match pattern, ln
        return
      end
    end
    flunk "expected #{pattern.inspect} to match something in:\n    #{lines.join("\n    ")}"
  end

end
