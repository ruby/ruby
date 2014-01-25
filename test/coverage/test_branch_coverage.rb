require "test/unit"
require "coverage"
require "tmpdir"

class TestBranchCoverage < Test::Unit::TestCase
  def test_if_else_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            if 2+2 == 4
              :ok
            end

            :ok unless [].size > 0
            :bad unless [].size == 0

            ary = [1,2,3]
            if ary.include? 4
              :bad
            elsif ary.include? 5
              :also_bad
            else
              :good
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        branch_coverage = Coverage.result[tmp + '/test.rb'][:branches]
        assert_equal 6, branch_coverage.size
        assert_equal 1, branch_coverage[2]
        assert_equal 1, branch_coverage[5]
        assert_equal 0, branch_coverage[6]
        assert_equal 0, branch_coverage[10]
        assert_equal 0, branch_coverage[12]
        assert_equal 1, branch_coverage[14]
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_when_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            case
            when 2 + 2 == 5
              x = :bad
              x = :math
            when 2 + 2 == 4
              x = :good
            else
              x = :also_bad
            end

            case [1,2,3]
            when String
              :string?
            else
              :else
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        branch_coverage = Coverage.result[tmp + '/test.rb'][:branches]
        assert_equal 5, branch_coverage.size
        assert_equal 0, branch_coverage[3]
        assert_equal 1, branch_coverage[6]
        assert_equal 0, branch_coverage[8]
        assert_equal 0, branch_coverage[13]
        assert_equal 1, branch_coverage[15]
      }
    }
  ensure
    $".replace loaded_features
  end
end
