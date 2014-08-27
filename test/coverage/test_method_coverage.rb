require "test/unit"
require "coverage"
require "tmpdir"

class TestMethodCoverage < Test::Unit::TestCase
  def test_method_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def method_one
              :one
            end

            def method_two
              :two
            end
            method_two; method_two
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        method_coverage = Coverage.result[tmp + '/test.rb'][:methods]

        assert_equal 2, method_coverage.size
        assert_equal 0, method_coverage[1]
        assert_equal 2, method_coverage[5]
      }
    }
  ensure
    $".replace loaded_features
  end
end
