# frozen_string_literal: false
require "test/unit"
require "coverage"
require "tmpdir"
require "envutil"

class TestCoverage < Test::Unit::TestCase
  def test_result_without_start
    assert_in_out_err(%w[-rcoverage], <<-"end;", [], /coverage measurement is not enabled/)
      Coverage.result
      p :NG
    end;
  end

  def test_peek_result_without_start
    assert_in_out_err(%w[-rcoverage], <<-"end;", [], /coverage measurement is not enabled/)
      Coverage.peek_result
      p :NG
    end;
  end

  def test_result_with_nothing
    assert_in_out_err(%w[-rcoverage], <<-"end;", ["{}"], [])
      Coverage.start
      p Coverage.result
    end;
  end

  def test_coverage_running?
    assert_in_out_err(%w[-rcoverage], <<-"end;", ["false", "true", "true", "false"], [])
      p Coverage.running?
      Coverage.start
      p Coverage.running?
      Coverage.peek_result
      p Coverage.running?
      Coverage.result
      p Coverage.running?
    end;
  end

  def test_coverage_snapshot
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def coverage_test_snapshot
              :ok
            end
          EOS
        end

        assert_in_out_err(%w[-rcoverage], <<-"end;", ["[1, 0, nil]", "[1, 1, nil]", "[1, 1, nil]"], [])
          Coverage.start
          tmp = Dir.pwd
          require tmp + "/test.rb"
          cov = Coverage.peek_result[tmp + "/test.rb"]
          coverage_test_snapshot
          cov2 = Coverage.peek_result[tmp + "/test.rb"]
          p cov
          p cov2
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_restarting_coverage
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        tmp = Dir.pwd
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def coverage_test_restarting
              :ok
            end
          EOS
        end

        File.open("test2.rb", "w") do |f|
          f.puts <<-EOS
            itself
          EOS
        end

        exp1 = { "#{tmp}/test.rb" => [1, 0, nil] }.inspect
        exp2 = {}.inspect
        exp3 = { "#{tmp}/test2.rb" => [1] }.inspect
        assert_in_out_err(%w[-rcoverage], <<-"end;", [exp1, exp2, exp3], [])
          Coverage.start
          tmp = Dir.pwd
          require tmp + "/test.rb"
          p Coverage.result

          # Restart coverage but '/test.rb' is required before restart,
          # so coverage is not recorded.
          Coverage.start
          coverage_test_restarting
          p Coverage.result

          # Restart coverage and '/test2.rb' is required after restart,
          # so coverage is recorded.
          Coverage.start
          require tmp + "/test2.rb"
          p Coverage.result
        end;
      }
    }
  end

  def test_big_code
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "__id__\n" * 10000
          f.puts "def ignore(x); end"
          f.puts "ignore([1"
          f.puts "])"
        end

        assert_in_out_err(%w[-rcoverage], <<-"end;", ["10003"], [])
          Coverage.start
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + '/test.rb'].size
        end;
      }
    }
  end

  def test_nonpositive_linenumber
    bug12517 = '[ruby-core:76141] [Bug #12517]'
    assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ['{"<compiled>"=>[nil]}'], [], bug12517)
      Coverage.start
      RubyVM::InstructionSequence.compile(":ok", nil, "<compiled>", 0)
      p Coverage.result
    end;
  end

  def test_eval
    bug13305 = '[ruby-core:80079] [Bug #13305]'

    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'REPEATS = 400'
          f.puts 'def add_method(target)'
          f.puts '  REPEATS.times do'
          f.puts '    target.class_eval(<<~RUBY, __FILE__, __LINE__ + 1)'
          f.puts '      def foo'
          f.puts '        #{"\n" * rand(REPEATS)}'
          f.puts '      end'
          f.puts '      1'
          f.puts '    RUBY'
          f.puts '  end'
          f.puts 'end'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["[1, 1, 1, 400, nil, nil, nil, nil, nil, nil, nil]"], [], bug13305)
          Coverage.start
          tmp = Dir.pwd
          require tmp + '/test.rb'
          add_method(Class.new)
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_nocoverage_optimized_line
    assert_ruby_status(%w[], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      def foo(x)
        x # optimized away
        nil
      end
    end;
  end

  def test_branch_coverage_for_if_statement
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'def foo(x)'
          f.puts '  if x == 0'
          f.puts '    0'
          f.puts '  else'
          f.puts '    1'
          f.puts '  end'
          f.puts ''
          f.puts '  unless x == 0'
          f.puts '    0'
          f.puts '  else'
          f.puts '    1'
          f.puts '  end'
          f.puts 'end'
          f.puts 'foo(0)'
          f.puts 'foo(0)'
          f.puts 'foo(1)'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["{:branches=>{[:if, 0, 2]=>{[:then, 1, 3]=>2, [:else, 2, 5]=>1}, [:unless, 3, 8]=>{[:else, 4, 11]=>2, [:then, 5, 9]=>1}}}"], [])
          ENV["COVERAGE_EXPERIMENTAL_MODE"] = "true"
          Coverage.start(branches: true)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_branch_coverage_for_while_statement
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'x = 3'
          f.puts 'while x > 0'
          f.puts '  x -= 1'
          f.puts 'end'
          f.puts 'until x == 10'
          f.puts '  x += 1'
          f.puts 'end'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["{:branches=>{[:while, 0, 2]=>{[:body, 1, 3]=>3}, [:until, 2, 5]=>{[:body, 3, 6]=>10}}}"], [])
          ENV["COVERAGE_EXPERIMENTAL_MODE"] = "true"
          Coverage.start(branches: true)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_branch_coverage_for_case_statement
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'def foo(x)'
          f.puts '  case x'
          f.puts '  when 0'
          f.puts '    0'
          f.puts '  when 1'
          f.puts '    1'
          f.puts '  end'
          f.puts ''
          f.puts '  case'
          f.puts '  when x == 0'
          f.puts '    0'
          f.puts '  when x == 1'
          f.puts '    1'
          f.puts '  end'
          f.puts ''
          f.puts '  case x'
          f.puts '  when 0'
          f.puts '    0'
          f.puts '  when 1'
          f.puts '    1'
          f.puts '  else'
          f.puts '    :other'
          f.puts '  end'
          f.puts ''
          f.puts '  case'
          f.puts '  when x == 0'
          f.puts '    0'
          f.puts '  when x == 1'
          f.puts '    1'
          f.puts '  else'
          f.puts '    :other'
          f.puts '  end'
          f.puts 'end'
          f.puts ''
          f.puts 'foo(0)'
          f.puts 'foo(0)'
          f.puts 'foo(2)'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["{:branches=>{[:case, 0, 2]=>{[:when, 1, 4]=>2, [:when, 2, 6]=>0, [:else, 3, 2]=>1}, [:case, 4, 9]=>{[:when, 5, 11]=>2, [:when, 6, 13]=>0, [:else, 7, 9]=>1}, [:case, 8, 16]=>{[:when, 9, 18]=>2, [:when, 10, 20]=>0, [:else, 11, 22]=>1}, [:case, 12, 25]=>{[:when, 13, 27]=>2, [:when, 14, 29]=>0, [:else, 15, 31]=>1}}}"], [])
          ENV["COVERAGE_EXPERIMENTAL_MODE"] = "true"
          Coverage.start(branches: true)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_branch_coverage_for_safe_method_invocation
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'a = 10'
          f.puts 'b = nil'
          f.puts 'a&.abs'
          f.puts 'b&.hoo'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["{:branches=>{[:\"&.\", 0, 3]=>{[:then, 1, 3]=>1, [:else, 2, 3]=>0}, [:\"&.\", 3, 4]=>{[:then, 4, 4]=>0, [:else, 5, 4]=>1}}}"], [])
          ENV["COVERAGE_EXPERIMENTAL_MODE"] = "true"
          Coverage.start(branches: true)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_method_coverage
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts 'def foo; end'
          f.puts 'def bar'
          f.puts 'end'
          f.puts 'def baz; end'
          f.puts ''
          f.puts 'foo'
          f.puts 'foo'
          f.puts 'bar'
        end

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", ["{:methods=>{[:foo, 0, 1]=>2, [:bar, 1, 2]=>1, [:baz, 2, 4]=>0}}"], [])
          ENV["COVERAGE_EXPERIMENTAL_MODE"] = "true"
          Coverage.start(methods: true)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          p Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end
end
