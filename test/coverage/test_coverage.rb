# frozen_string_literal: false
require "test/unit"
require "coverage"
require "tmpdir"
require "envutil"

class TestCoverage < Test::Unit::TestCase
  # The command-line arguments that we will pass to the ruby subprocess invoked
  # by assert_in_out_err. In general this is just requiring the coverage
  # library, but if prism is enabled we want to additionally pass that option
  # through.
  ARGV = ["-rcoverage"]

  if RUBY_ENGINE == "ruby" && RubyVM::InstructionSequence.compile('').to_a[4][:parser] == :prism
    ARGV << "-W:no-experimental"
    ARGV << "--parser=prism"
  end

  def test_result_without_start
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is not enabled/)
      Coverage.result
      p :NG
    end;
  end

  def test_peek_result_without_start
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is not enabled/)
      Coverage.peek_result
      p :NG
    end;
  end

  def test_result_with_nothing
    assert_in_out_err(ARGV, <<-"end;", ["{}"], [])
      Coverage.start
      p Coverage.result
    end;
  end

  def test_coverage_in_main_script
    autostart_path = File.expand_path("autostart.rb", __dir__)
    main_path = File.expand_path("main.rb", __dir__)

    assert_in_out_err(['-r', autostart_path, main_path], "", ["1"], [])
  end

  def test_coverage_running?
    assert_in_out_err(ARGV, <<-"end;", ["false", "true", "true", "false"], [])
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

        assert_in_out_err(ARGV, <<-"end;", ["[1, 0, nil]", "[1, 1, nil]", "[1, 1, nil]"], [])
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
        assert_in_out_err(ARGV, <<-"end;", [exp1, exp2, exp3], [])
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

        assert_in_out_err(ARGV, <<-"end;", ["10003"], [])
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
          f.puts '    target.class_eval(<<~RUBY)'
          f.puts '      def foo'
          f.puts '        #{"\n" * rand(REPEATS)}'
          f.puts '      end'
          f.puts '      1'
          f.puts '    RUBY'
          f.puts '  end'
          f.puts 'end'
        end

        assert_in_out_err(["-W0", *ARGV], <<-"end;", ["[1, 1, 1, 400, nil, nil, nil, nil, nil, nil, nil]"], [], bug13305)
          Coverage.start(:all)
          tmp = Dir.pwd
          require tmp + '/test.rb'
          add_method(Class.new)
          p Coverage.result[tmp + "/test.rb"][:lines]
        end;
      }
    }
  end

  def test_eval_coverage
    assert_in_out_err(ARGV, <<-"end;", ["[1, 1, 1, nil, 0, nil]"], [])
      Coverage.start(eval: true, lines: true)

      eval(<<-RUBY, TOPLEVEL_BINDING, "test.rb")
      _out = String.new
      if _out.empty?
        _out << 'Hello World'
      else
        _out << 'Goodbye World'
      end
      RUBY

      p Coverage.result["test.rb"][:lines]
    end;
  end

  def test_eval_negative_lineno
    assert_in_out_err(ARGV, <<-"end;", ["[1, 1, 1]"], [])
      Coverage.start(eval: true, lines: true)

      eval(<<-RUBY, TOPLEVEL_BINDING, "test.rb", -2)
      p # -2 # Not subject to measurement
      p # -1 # Not subject to measurement
      p #  0 # Not subject to measurement
      p #  1 # Subject to measurement
      p #  2 # Subject to measurement
      p #  3 # Subject to measurement
      RUBY

      p Coverage.result["test.rb"][:lines]
    end;
  end

  def test_coverage_supported
    assert Coverage.supported?(:lines)
    assert Coverage.supported?(:oneshot_lines)
    assert Coverage.supported?(:branches)
    assert Coverage.supported?(:methods)
    assert Coverage.supported?(:eval)
    refute Coverage.supported?(:all)
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

  def test_coverage_ensure_if_return
    result = {
      :branches => {
        [:if, 0, 3, 2, 6, 5] => {
          [:then, 1, 3, 7, 3, 7] => 0,
          [:else, 2, 5, 4, 5, 10] => 1,
        },
      },
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      def flush
      ensure
        if $!
        else
          return
        end
      end
      flush
    end;
  end

  def assert_coverage(code, opt, stdout)
    stdout = [stdout] unless stdout.is_a?(Array)
    stdout = stdout.map {|s| s.to_s }
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.write("test.rb", code)

        assert_in_out_err(["-W0", *ARGV], <<-"end;", stdout, [])
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

  def test_branch_coverage_for_pattern_matching
    result = {
      :branches=> {
        [:case, 0,  3, 4,  8, 7] => {[:in, 1,  5, 6,  5, 7]=>2, [:in, 2, 7, 6, 7, 7]=>0, [:else, 3,  3, 4,  8, 7]=>1},
        [:case, 4, 12, 2, 17, 5] => {[:in, 5, 14, 4, 14, 5]=>2,                          [:else, 6, 16, 4, 16, 5]=>1}},
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      def foo(x)
        begin
          case x
          in 0
            0
          in 1
            1
          end
        rescue NoMatchingPatternError
        end

        case x
        in 0
          0
        else
          1
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
        [:"&.", 12, 10, 0, 10, 6] => {[:then, 13, 10, 0, 10, 6] => 0, [:else, 14, 10, 0, 10, 6] => 1},
        [:"&.", 15, 11, 0, 11, 5] => {[:then, 16, 11, 0, 11, 5] => 0, [:else, 17, 11, 0, 11, 5] => 1},
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
      d&.(b)
      d&.()
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
          { lines: [1, 0, 0, nil, 0, nil, nil] }.inspect,
          { lines: [0, 1, 1, nil, 0, nil, nil] }.inspect,
          { lines: [0, 1, 0, nil, 1, nil, nil] }.inspect,
        ]
        assert_in_out_err(ARGV, <<-"end;", exp, [])
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
          { branches: { [:if, 0, 2, 2, 6, 5] => { [:then, 1, 3, 4, 3, 8] => 0, [:else, 2, 5, 4, 5, 12] => 0 } } }.inspect,
          { branches: { [:if, 0, 2, 2, 6, 5] => { [:then, 1, 3, 4, 3, 8] => 1, [:else, 2, 5, 4, 5, 12] => 0 } } }.inspect,
          { branches: { [:if, 0, 2, 2, 6, 5] => { [:then, 1, 3, 4, 3, 8] => 0, [:else, 2, 5, 4, 5, 12] => 1 } } }.inspect,
          { branches: { [:if, 0, 2, 2, 6, 5] => { [:then, 1, 3, 4, 3, 8] => 0, [:else, 2, 5, 4, 5, 12] => 1 } } }.inspect,
        ]
        assert_in_out_err(ARGV, <<-"end;", exp, [])
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
          { methods: { [Object, :foo, 1, 0, 7, 3] => 0 } }.inspect,
          { methods: { [Object, :foo, 1, 0, 7, 3] => 1 } }.inspect,
          { methods: { [Object, :foo, 1, 0, 7, 3] => 1 } }.inspect,
          { methods: { [Object, :foo, 1, 0, 7, 3] => 1 } }.inspect
        ]
        assert_in_out_err(ARGV, <<-"end;", exp, [])
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
          { oneshot_lines: [1] }.inspect,
          { oneshot_lines: [2, 3] }.inspect,
          { oneshot_lines: [5] }.inspect,
          { oneshot_lines: [] }.inspect,
        ]
        assert_in_out_err(ARGV, <<-"end;", exp, [])
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

  def test_stop_wrong_peephole_optimization
    result = {
      :lines => [1, 1, 1, nil]
    }
    assert_coverage(<<~"end;", { lines: true }, result)
      raise if 1 == 2
      while true
        break
      end
    end;
  end

  def test_branch_coverage_in_ensure_clause
    result = {
      :branches => {
        [:if, 0, 4, 2, 4, 11] => {
          [:then, 1, 4, 2, 4, 5] => 1,
          [:else, 2, 4, 2, 4, 11] => 1,
        }
      }
    }
    assert_coverage(<<~"end;", { branches: true }, result) # Bug #16967
      def foo
        yield
      ensure
        :ok if $!
      end
      foo {}
      foo { raise } rescue nil
    end;
  end

  def test_coverage_with_asan
    result = { :lines => [1, 1, 0, 0, nil, nil, nil] }

    assert_coverage(<<~"end;", { lines: true }, result) # Bug #18001
      class Foo
        def bar
          baz do |x|
            next unless Integer == x
          end
        end
      end
    end;
  end

  def test_coverage_suspendable
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        File.open("test.rb", "w") do |f|
          f.puts <<-EOS
            def foo
              :ok
            end

            def bar
              :ok
            end

            def baz
              :ok
            end
          EOS
        end

        assert_separately(%w[-rcoverage], "#{<<~"begin;"}\n#{<<~'end;'}")
        begin;
          cov1 = [0, 0, nil, nil, 0, 1, nil, nil, 0, 0, nil]
          cov2 = [0, 0, nil, nil, 0, 1, nil, nil, 0, 1, nil]
          Coverage.setup
          tmp = Dir.pwd
          require tmp + "/test.rb"
          foo
          Coverage.resume
          bar
          Coverage.suspend
          baz
          assert_equal cov1, Coverage.peek_result[tmp + "/test.rb"]
          Coverage.resume
          baz
          assert_equal cov2, Coverage.result[tmp + "/test.rb"]
        end;

        assert_separately(%w[-rcoverage], "#{<<~"begin;"}\n#{<<~'end;'}")
        begin;
          cov1 = {
            lines: [0, 0, nil, nil, 0, 1, nil, nil, 0, 0, nil],
            branches: {},
            methods: {
              [Object, :baz, 9, 12, 11, 15]=>0,
              [Object, :bar, 5, 12, 7, 15]=>1,
              [Object, :foo, 1, 12, 3, 15]=>0,
            }
          }

          cov2 = {
            lines: [0, 0, nil, nil, 0, 1, nil, nil, 0, 1, nil],
            branches: {},
            methods: {
              [Object, :baz, 9, 12, 11, 15]=>1,
              [Object, :bar, 5, 12, 7, 15]=>1,
              [Object, :foo, 1, 12, 3, 15]=>0,
            }
          }

          Coverage.setup(:all)
          tmp = Dir.pwd
          require tmp + "/test.rb"
          foo
          Coverage.resume
          bar
          Coverage.suspend
          baz
          assert_equal cov1, Coverage.peek_result[tmp + "/test.rb"]
          Coverage.resume
          baz
          assert_equal cov2, Coverage.result[tmp + "/test.rb"]
        end;

        assert_separately(%w[-rcoverage], "#{<<~"begin;"}\n#{<<~'end;'}")
        begin;
          cov1 = {:oneshot_lines=>[6]}
          cov2 = {:oneshot_lines=>[6, 10]}
          Coverage.setup(oneshot_lines: true)
          tmp = Dir.pwd
          require tmp + "/test.rb"
          foo
          Coverage.resume
          bar
          Coverage.suspend
          baz
          assert_equal cov1, Coverage.peek_result[tmp + "/test.rb"]
          Coverage.resume
          baz
          assert_equal cov2, Coverage.result[tmp + "/test.rb"]
        end;
      }
    }
  end

  def test_coverage_state
    assert_in_out_err(ARGV, <<-"end;", [":idle", ":running", ":running", ":idle"], [])
      p Coverage.state
      Coverage.start
      p Coverage.state
      Coverage.peek_result
      p Coverage.state
      Coverage.result
      p Coverage.state
    end;

    assert_in_out_err(ARGV, <<-"end;", [":idle", ":suspended", ":running", ":suspended", ":running", ":suspended", ":idle"], [])
      p Coverage.state
      Coverage.setup
      p Coverage.state
      Coverage.resume
      p Coverage.state
      Coverage.suspend
      p Coverage.state
      Coverage.resume
      p Coverage.state
      Coverage.suspend
      p Coverage.state
      Coverage.result
      p Coverage.state
    end;
  end

  def test_result_without_resume
    assert_in_out_err(ARGV, <<-"end;", ["{}"], [])
      Coverage.setup
      p Coverage.result
    end;
  end

  def test_result_after_suspend
    assert_in_out_err(ARGV, <<-"end;", ["{}"], [])
      Coverage.start
      Coverage.suspend
      p Coverage.result
    end;
  end

  def test_resume_without_setup
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is not set up yet/)
      Coverage.resume
      p :NG
    end;
  end

  def test_suspend_without_setup
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is not running/)
      Coverage.suspend
      p :NG
    end;
  end

  def test_double_resume
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is already running/)
      Coverage.start
      Coverage.resume
      p :NG
    end;
  end

  def test_double_suspend
    assert_in_out_err(ARGV, <<-"end;", [], /coverage measurement is not running/)
      Coverage.setup
      Coverage.suspend
      p :NG
    end;
  end

  def test_tag_break_with_branch_coverage
    result = {
      :branches => {
        [:"&.", 0, 1, 0, 1, 6] => {
          [:then, 1, 1, 0, 1, 6] => 1,
          [:else, 2, 1, 0, 1, 6] => 0,
        },
      },
    }
    assert_coverage(<<~"end;", { branches: true }, result)
      1&.tap do break end
    end;
  end
end
