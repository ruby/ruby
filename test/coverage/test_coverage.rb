# frozen_string_literal: false
require "test/unit"
require "coverage"
require "tmpdir"

class TestCoverage < Test::Unit::TestCase
  def test_result_without_start
    assert_raise(RuntimeError) {Coverage.result}
  end

  def test_peek_result_without_start
    assert_raise(RuntimeError) {Coverage.peek_result}
  end

  def test_result_with_nothing
    Coverage.start
    result = Coverage.result
    assert_kind_of(Hash, result)
    result.each do |key, val|
      assert_kind_of(String, key)
      assert_kind_of(Array, val)
    end
  end

  def test_coverage_snapshot
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def TestCoverage.coverage_test_snapshot
              :ok
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        cov = Coverage.peek_result[tmp + '/test.rb']
        TestCoverage.coverage_test_snapshot
        cov2 = Coverage.peek_result[tmp + '/test.rb']
        assert_equal cov[1] + 1, cov2[1]
        assert_equal cov2, Coverage.result[tmp + '/test.rb']
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_restarting_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def TestCoverage.coverage_test_restarting
              :ok
            end
          EOS
        end

        File.open("test2.rb", "w") do |f|
          f.puts <<-EOS
            itself
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        cov = { "#{tmp}/test.rb" => [1, 0, nil] }
        assert_equal cov, Coverage.result

        # Restart coverage but '/test.rb' is required before restart,
        # so coverage is not recorded.
        Coverage.start
        TestCoverage.coverage_test_restarting
        assert_equal({}, Coverage.result)

        # Restart coverage and '/test2.rb' is required after restart,
        # so coverage is recorded.
        Coverage.start
        require tmp + '/test2.rb'
        cov = { "#{tmp}/test2.rb" => [1] }
        assert_equal cov, Coverage.result
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_big_code
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "__id__\n" * 10000
          f.puts "def ignore(x); end"
          f.puts "ignore([1"
          f.puts "])"
        end

        Coverage.start
        require tmp + '/test.rb'
        assert_equal 10003, Coverage.result[tmp + '/test.rb'].size
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_nonpositive_linenumber
    bug12517 = '[ruby-core:76141] [Bug #12517]'
    Coverage.start
    assert_nothing_raised(ArgumentError, bug12517) do
      RubyVM::InstructionSequence.compile(":ok", nil, "<compiled>", 0)
    end
    assert_include Coverage.result, "<compiled>"
  end
end unless ENV['COVERAGE']
