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

  def test_coverage_optimized_branch
    result = {
      :branches => {
        [:"&.", 0, 1, 0, 1, 8] => {
          [:then, 1, 1, 0, 1, 8] => 0,
          [:else, 2, 1, 0, 1, 8] => 1,
        },
      },
    }
    assert_coverage(<<~"end;", { branches: true }, result) # Bug #15476
      nil&.foo
    end;
  end

  def assert_coverage(code, opt, stdout)
    stdout = [stdout] unless stdout.is_a?(Array)
    stdout = stdout.map {|s| s.to_s }
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.write("test.rb", code)

        assert_in_out_err(%w[-W0 -rcoverage], <<-"end;", stdout, [])
          Coverage.start(#{ opt })
          tmp = Dir.pwd
          require tmp + '/test.rb'
          r = Coverage.result[tmp + "/test.rb"]
          if r[:methods]
            h = {}
            r[:methods].keys.sort_by {|key| key.drop(1) }.each do |key|
              h[key] = r[:methods][key]
            end
            r[:methods].replace h
          end
          p r
        end;
      }
    }
  end

  def test_line_coverage_for_multiple_lines
    result = {
      :lines => [nil, 1, nil, nil, nil, 1, nil, nil, nil, 1, nil, 1, nil, nil, nil, nil, 1, 1, nil, 1, nil, nil, nil, nil, 1]
    }
    assert_coverage(<<~"end;", { lines: true }, result) # Bug #14191
      FOO = [
        { foo: 'bar' },
        { bar: 'baz' }
      ]

      'some string'.split
                   .map(&:length)

      some =
        'value'

      Struct.new(
        :foo,
        :bar
      ).new

      class Test
        def foo(bar)
          {
            foo: bar
          }
        end
      end

      Test.new.foo(Object.new)
    end;
  end

  def test_branch_coverage_for_if_statement
    result = {
      :branches => {
        [:if    ,  0,  2, 2,  6,  5] => {[:then,  1,  3,  4,  3,  5]=>2, [:else,  2,  5,  4,  5,  5]=>1},
        [:unless,  3,  8, 2, 12,  5] => {[:else,  4, 11,  4, 11,  5]=>2, [:then,  5,  9,  4,  9,  5]=>1},
        [:if    ,  6, 14, 2, 16,  5] => {[:then,  7, 15,  4, 15,  5]=>2, [:else,  8, 14,  2, 16,  5]=>1},
        [:unless,  9, 18, 2, 20,  5] => {[:else, 10, 18,  2, 20,  5]=>2, [:then, 11, 19,  4, 19,  5]=>1},
        [:if    , 12, 22, 2, 22, 13] => {[:then, 13, 22,  2, 22,  3]=>2, [:else, 14, 22,  2, 22, 13]=>1},
        [:unless, 15, 23, 2, 23, 17] => {[:else, 16, 23,  2, 23, 17]=>2, [:then, 17, 23,  2, 23,  3]=>1},
        [:if    , 18, 25, 2, 25, 16] => {[:then, 19, 25, 11, 25, 12]=>2, [:else, 20, 25, 15, 25, 16]=>1},
      }
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      def foo(x)
        if x == 0
          0
        else
          1
        end

        unless x == 0
          0
        else
          1
        end

        if x == 0
          0
        end

        unless x == 0
          0
        end

        0 if x == 0
        0 unless x == 0

        x == 0 ? 0 : 1
      end

      foo(0)
      foo(0)
      foo(1)
    end;
  end

  def test_branch_coverage_for_while_statement
    result = {
      :branches => {
        [:while, 0,  2, 0,  4,  3] => {[:body, 1,  3, 2,  3, 8]=> 3},
        [:until, 2,  5, 0,  7,  3] => {[:body, 3,  6, 2,  6, 8]=>10},
        [:while, 4, 10, 0, 10, 18] => {[:body, 5, 10, 0, 10, 6]=> 3},
        [:until, 6, 11, 0, 11, 20] => {[:body, 7, 11, 0, 11, 6]=>10},
      }
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      x = 3
      while x > 0
        x -= 1
      end
      until x == 10
        x += 1
      end

      y = 3
      y -= 1 while y > 0
      y += 1 until y == 10
    end;
  end

  def test_branch_coverage_for_case_statement
    result = {
      :branches => {
        [:case,  0,  2, 2,  7, 5] => {[:when,  1,  4, 4,  4, 5]=>2, [:when,  2,  6, 4,  6, 5]=>0, [:else,  3,  2, 2,  7,  5]=>1},
        [:case,  4,  9, 2, 14, 5] => {[:when,  5, 11, 4, 11, 5]=>2, [:when,  6, 13, 4, 13, 5]=>0, [:else,  7,  9, 2, 14,  5]=>1},
        [:case,  8, 16, 2, 23, 5] => {[:when,  9, 18, 4, 18, 5]=>2, [:when, 10, 20, 4, 20, 5]=>0, [:else, 11, 22, 4, 22, 10]=>1},
        [:case, 12, 25, 2, 32, 5] => {[:when, 13, 27, 4, 27, 5]=>2, [:when, 14, 29, 4, 29, 5]=>0, [:else, 15, 31, 4, 31, 10]=>1},
      }
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      def foo(x)
        case x
        when 0
          0
        when 1
          1
        end

        case
        when x == 0
          0
        when x == 1
          1
        end

        case x
        when 0
          0
        when 1
          1
        else
          :other
        end

        case
        when x == 0
          0
        when x == 1
          1
        else
          :other
        end
      end

      foo(0)
      foo(0)
      foo(2)
    end;
  end

  def test_branch_coverage_for_safe_method_invocation
    result = {
      :branches=>{
        [:"&.", 0, 6, 0, 6,  6] => {[:then,  1, 6, 0, 6,  6]=>1, [:else,  2, 6, 0, 6,  6]=>0},
        [:"&.", 3, 7, 0, 7,  6] => {[:then,  4, 7, 0, 7,  6]=>0, [:else,  5, 7, 0, 7,  6]=>1},
        [:"&.", 6, 8, 0, 8, 10] => {[:then,  7, 8, 0, 8, 10]=>1, [:else,  8, 8, 0, 8, 10]=>0},
        [:"&.", 9, 9, 0, 9, 10] => {[:then, 10, 9, 0, 9, 10]=>0, [:else, 11, 9, 0, 9, 10]=>1},
      }
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      class Dummy; def foo; end; def foo=(x); end; end
      a = Dummy.new
      b = nil
      c = Dummy.new
      d = nil
      a&.foo
      b&.foo
      c&.foo = 1
      d&.foo = 1
    end;
  end

  def test_method_coverage
    result = {
      :methods => {
        [Object, :bar, 2, 0, 3, 3] => 1,
        [Object, :baz, 4, 1, 4, 13] => 0,
        [Object, :foo, 1, 0, 1, 12] => 2,
      }
    }
    assert_coverage(<<~"end;", { methods: true }, result)
      def foo; end
      def bar
      end
       def baz; end

      foo
      foo
      bar
    end;
  end

  def test_method_coverage_for_define_method
    result = {
      :methods => {
        [Object, :a, 6, 18, 6, 25] => 2,
        [Object, :b, 7, 18, 8, 3] => 0,
        [Object, :bar, 2, 20, 3, 1] => 1,
        [Object, :baz, 4, 9, 4, 11] => 0,
        [Object, :foo, 1, 20, 1, 22] => 2,
      }
    }
    assert_coverage(<<~"end;", { methods: true }, result)
      define_method(:foo) {}
      define_method(:bar) {
      }
      f = proc {}
      define_method(:baz, &f)
      define_method(:a) do; end
      define_method(:b) do
      end

      foo
      foo
      bar
      a
      a
    end;
  end

  class DummyConstant < String
    def inspect
      self
    end
  end

  def test_method_coverage_for_alias
    _C = DummyConstant.new("C")
    _M = DummyConstant.new("M")
    code = <<~"end;"
      module M
        def foo
        end
        alias bar foo
      end
      class C
        include M
        def baz
        end
        alias qux baz
      end
    end;

    result = {
      :methods => {
        [_C, :baz, 8, 2, 9, 5] => 0,
        [_M, :foo, 2, 2, 3, 5] => 0,
      }
    }
    assert_coverage(code, { methods: true }, result)

    result = {
      :methods => {
        [_C, :baz, 8, 2, 9, 5] => 12,
        [_M, :foo, 2, 2, 3, 5] =>  3,
      }
    }
    assert_coverage(code + <<~"end;", { methods: true }, result)
      obj = C.new
      1.times { obj.foo }
      2.times { obj.bar }
      4.times { obj.baz }
      8.times { obj.qux }
    end;
  end

  def test_method_coverage_for_singleton_class
    _singleton_Foo = DummyConstant.new("#<Class:Foo>")
    _Foo = DummyConstant.new("Foo")
    code = <<~"end;"
      class Foo
        def foo
        end
        alias bar foo
        def self.baz
        end
        class << self
          alias qux baz
        end
      end

      1.times { Foo.new.foo }
      2.times { Foo.new.bar }
      4.times { Foo.baz }
      8.times { Foo.qux }
    end;

    result = {
      :methods => {
        [_singleton_Foo, :baz, 5, 2, 6, 5] => 12,
        [_Foo, :foo, 2, 2, 3, 5] => 3,
      }
    }
    assert_coverage(code, { methods: true }, result)
  end

  def test_oneshot_line_coverage
    result = {
      :oneshot_lines => [2, 6, 10, 12, 17, 18, 25, 20]
    }
    assert_coverage(<<~"end;", { oneshot_lines: true }, result)
      FOO = [
        { foo: 'bar' }, # 2
        { bar: 'baz' }
      ]

      'some string'.split # 6
                   .map(&:length)

      some =
        'value' # 10

      Struct.new( # 12
        :foo,
        :bar
      ).new

      class Test # 17
        def foo(bar) # 18
          {
            foo: bar # 20
          }
        end
      end

      Test.new.foo(Object.new) # 25
    end;
  end

  def test_clear_with_lines
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "def foo(x)"
          f.puts "  if x > 0"
          f.puts "    :pos"
          f.puts "  else"
          f.puts "    :non_pos"
          f.puts "  end"
          f.puts "end"
        end

        exp = [
          "{:lines=>[1, 0, 0, nil, 0, nil, nil]}",
          "{:lines=>[0, 1, 1, nil, 0, nil, nil]}",
          "{:lines=>[0, 1, 0, nil, 1, nil, nil]}",
        ]
        assert_in_out_err(%w[-rcoverage], <<-"end;", exp, [])
          Coverage.start(lines: true)
          tmp = Dir.pwd
          f = tmp + "/test.rb"
          require f
          p Coverage.result(stop: false, clear: true)[f]
          foo(1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result[f]
        end;
      }
    }
  end

  def test_clear_with_branches
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "def foo(x)"
          f.puts "  if x > 0"
          f.puts "    :pos"
          f.puts "  else"
          f.puts "    :non_pos"
          f.puts "  end"
          f.puts "end"
        end

        exp = [
          "{:branches=>{[:if, 0, 2, 2, 6, 5]=>{[:then, 1, 3, 4, 3, 8]=>0, [:else, 2, 5, 4, 5, 12]=>0}}}",
          "{:branches=>{[:if, 0, 2, 2, 6, 5]=>{[:then, 1, 3, 4, 3, 8]=>1, [:else, 2, 5, 4, 5, 12]=>0}}}",
          "{:branches=>{[:if, 0, 2, 2, 6, 5]=>{[:then, 1, 3, 4, 3, 8]=>0, [:else, 2, 5, 4, 5, 12]=>1}}}",
          "{:branches=>{[:if, 0, 2, 2, 6, 5]=>{[:then, 1, 3, 4, 3, 8]=>0, [:else, 2, 5, 4, 5, 12]=>1}}}",
        ]
        assert_in_out_err(%w[-rcoverage], <<-"end;", exp, [])
          Coverage.start(branches: true)
          tmp = Dir.pwd
          f = tmp + "/test.rb"
          require f
          p Coverage.result(stop: false, clear: true)[f]
          foo(1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
        end;
      }
    }
  end

  def test_clear_with_methods
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "def foo(x)"
          f.puts "  if x > 0"
          f.puts "    :pos"
          f.puts "  else"
          f.puts "    :non_pos"
          f.puts "  end"
          f.puts "end"
        end

        exp = [
          "{:methods=>{[Object, :foo, 1, 0, 7, 3]=>0}}",
          "{:methods=>{[Object, :foo, 1, 0, 7, 3]=>1}}",
          "{:methods=>{[Object, :foo, 1, 0, 7, 3]=>1}}",
          "{:methods=>{[Object, :foo, 1, 0, 7, 3]=>1}}"
        ]
        assert_in_out_err(%w[-rcoverage], <<-"end;", exp, [])
          Coverage.start(methods: true)
          tmp = Dir.pwd
          f = tmp + "/test.rb"
          require f
          p Coverage.result(stop: false, clear: true)[f]
          foo(1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
        end;
      }
    }
  end

  def test_clear_with_oneshot_lines
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "def foo(x)"
          f.puts "  if x > 0"
          f.puts "    :pos"
          f.puts "  else"
          f.puts "    :non_pos"
          f.puts "  end"
          f.puts "end"
        end

        exp = [
          "{:oneshot_lines=>[1]}",
          "{:oneshot_lines=>[2, 3]}",
          "{:oneshot_lines=>[5]}",
          "{:oneshot_lines=>[]}",
        ]
        assert_in_out_err(%w[-rcoverage], <<-"end;", exp, [])
          Coverage.start(oneshot_lines: true)
          tmp = Dir.pwd
          f = tmp + "/test.rb"
          require f
          p Coverage.result(stop: false, clear: true)[f]
          foo(1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
          foo(-1)
          p Coverage.result(stop: false, clear: true)[f]
        end;
      }
    }
  end

  def test_line_stub
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts "def foo(x)"
          f.puts "  if x > 0"
          f.puts "    :pos"
          f.puts "  else"
          f.puts "    :non_pos"
          f.puts "  end"
          f.puts "end"
        end

        assert_equal([0, 0, 0, nil, 0, nil, nil], Coverage.line_stub("test.rb"))
      }
    }
  end
end
