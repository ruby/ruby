require "test/unit"
require "coverage"
require "tmpdir"

class TestCoverage < Test::Unit::TestCase
  def test_result_without_start
    assert_raise(RuntimeError) {Coverage.result}
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

  def test_restarting_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def coverage_test_method
              :ok
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        assert_equal 3, Coverage.result[tmp + '/test.rb'].size
        Coverage.start
        coverage_test_method
        assert_equal 0, Coverage.result[tmp + '/test.rb'].size
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
