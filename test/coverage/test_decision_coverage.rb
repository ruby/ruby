require "test/unit"
require "coverage"
require "tmpdir"

class TestDecisionCoverage < Test::Unit::TestCase
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
        decision_coverage = Coverage.result[tmp + '/test.rb'][:decisions]
        assert_equal 5, decision_coverage.size
        assert_equal [1,0], decision_coverage[1]
        assert_equal [0,1], decision_coverage[5]
        assert_equal [1,0], decision_coverage[6]
        assert_equal [0,1], decision_coverage[9]
        assert_equal [0,1], decision_coverage[11]
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
            def foo(arg)
              case
              when arg == 1
                x = :one
              when arg == 2
                x = :two
              else
                x = :none
              end
            end
            foo(2); foo(2); foo(3)

            def bar(arg)
              case arg
              when String
                :string?
              when 1
                :one
              else
                :else
              end
            end
            bar("BAR"); bar("BAZ"); bar(1); bar(7)
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        decision_coverage = Coverage.result[tmp + '/test.rb'][:decisions]
        assert_equal 4, decision_coverage.size
        assert_equal [0,3], decision_coverage[3]
        assert_equal [2,1], decision_coverage[5]
        assert_equal [2,2], decision_coverage[15]
        assert_equal [1,1], decision_coverage[17]
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_when_without_else_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def foo(arg)
              case
              when arg == 1
                x = :one
              when arg == 2
                x = :two
              end
            end
            foo(2); foo(2); foo(3)

            def bar(arg)
              case arg
              when String
                :string?
              when 1
                :one
              end
            end
            bar("BAR"); bar("BAZ"); bar(1); bar(7)
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        decision_coverage = Coverage.result[tmp + '/test.rb'][:decisions]
        assert_equal 4, decision_coverage.size
        assert_equal [0,3], decision_coverage[3]
        assert_equal [2,1], decision_coverage[5]
        assert_equal [2,2], decision_coverage[13]
        assert_equal [1,1], decision_coverage[15]
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_when_with_splats_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            9.times do |i|
              primes = [2,3,5,7]
              composites = [4,6,8,9]

              case i+1
              when *primes
                :prime
              when *composites
                :composite
              end
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        decision_coverage = Coverage.result[tmp + '/test.rb'][:decisions]
        assert_equal 2, decision_coverage.size
        assert_equal [4,5], decision_coverage[6]
        assert_equal [4,1], decision_coverage[8]
      }
    }
  ensure
    $".replace loaded_features
  end

  def test_while_coverage
    loaded_features = $".dup

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            i = 0
            while i < 6
              i += 1
              next if i % 3 == 0  # next should trigger another decision
              if i == 4
                redo  # redo should NOT trigger another decision
              end
            end

            until i < 1
              break if i == 3
              i -= 1
            end
          EOS
        end

        Coverage.start
        require tmp + '/test.rb'
        decision_coverage = Coverage.result[tmp + '/test.rb'][:decisions]
        assert_equal 5, decision_coverage.size
        assert_equal [6,1], decision_coverage[2]
        assert_equal [2,4], decision_coverage[4]
        assert_equal [1,3], decision_coverage[5]
        assert_equal [0,4], decision_coverage[10]
        assert_equal [1,3], decision_coverage[11]
      }
    }
  ensure
    $".replace loaded_features
  end
end
