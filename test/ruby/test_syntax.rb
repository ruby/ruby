require 'test/unit'
require_relative 'envutil'

class TestSyntax < Test::Unit::TestCase
  def assert_syntax_files(test)
    srcdir = File.expand_path("../../..", __FILE__)
    srcdir = File.join(srcdir, test)
    assert_separately(%W[--disable-gem -r#{__dir__}/envutil - #{srcdir}],
                      __FILE__, __LINE__, <<-'eom', timeout: Float::INFINITY)
      dir = ARGV.shift
      for script in Dir["#{dir}/**/*.rb"].sort
        assert_valid_syntax(IO::read(script), script)
      end
    eom
  end

  def test_syntax_lib; assert_syntax_files("lib"); end
  def test_syntax_sample; assert_syntax_files("sample"); end
  def test_syntax_ext; assert_syntax_files("ext"); end
  def test_syntax_test; assert_syntax_files("test"); end

  def test_defined_empty_argument
    bug8220 = '[ruby-core:53999] [Bug #8220]'
    assert_ruby_status(%w[--disable-gem], 'puts defined? ()', bug8220)
  end

  def test_must_ascii_compatible
    require 'tempfile'
    f = Tempfile.new("must_ac_")
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      make_tmpsrc(f, "# -*- coding: #{enc.name} -*-")
      assert_nothing_raised(ArgumentError, enc.name) {load(f.path)}
    end
    Encoding.list.each do |enc|
      next if enc.ascii_compatible?
      make_tmpsrc(f, "# -*- coding: #{enc.name} -*-")
      assert_raise(ArgumentError, enc.name) {load(f.path)}
    end
    f.close!
  end

  def test_script_lines
    require 'tempfile'
    f = Tempfile.new("bug4361_")
    bug4361 = '[ruby-dev:43168]'
    with_script_lines do |debug_lines|
      Encoding.list.each do |enc|
        next unless enc.ascii_compatible?
        make_tmpsrc(f, "# -*- coding: #{enc.name} -*-\n#----------------")
        load(f.path)
        assert_equal([f.path], debug_lines.keys)
        assert_equal([enc, enc], debug_lines[f.path].map(&:encoding), bug4361)
      end
    end
    f.close!
  end

  def test_newline_in_block_parameters
    bug = '[ruby-dev:45292]'
    ["", "a", "a, b"].product(["", ";x", [";", "x"]]) do |params|
      params = ["|", *params, "|"].join("\n")
      assert_valid_syntax("1.times{#{params}}", __FILE__, "#{bug} #{params.inspect}")
    end
  end

  tap do |_,
    bug6115 = '[ruby-dev:45308]',
    blockcall = '["elem"].each_with_object [] do end',
    methods = [['map', 'no'], ['inject([])', 'with']],
    blocks = [['do end', 'do'], ['{}', 'brace']],
    *|
    [%w'. dot', %w':: colon'].product(methods, blocks) do |(c, n1), (m, n2), (b, n3)|
      m = m.tr_s('()', ' ').strip if n2 == 'do'
      name = "test_#{n3}_block_after_blockcall_#{n1}_#{n2}_arg"
      code = "#{blockcall}#{c}#{m} #{b}"
      define_method(name) {assert_valid_syntax(code, bug6115)}
    end
  end

  def test_do_block_in_cmdarg
    bug9726 = '[ruby-core:61950] [Bug #9726]'
    assert_valid_syntax("tap (proc do end)", __FILE__, bug9726)
  end

  def test_keyword_rest
    bug5989 = '[ruby-core:42455]'
    assert_valid_syntax("def kwrest_test(**a) a; end", __FILE__, bug5989)
    assert_valid_syntax("def kwrest_test2(**a, &b) end", __FILE__, bug5989)
    o = Object.new
    def o.kw(**a) a end
    assert_equal({}, o.kw, bug5989)
    assert_equal({foo: 1}, o.kw(foo: 1), bug5989)
    assert_equal({foo: 1, bar: 2}, o.kw(foo: 1, bar: 2), bug5989)
    EnvUtil.under_gc_stress do
      eval("def o.m(k: 0) k end")
    end
    assert_equal(42, o.m(k: 42), '[ruby-core:45744]')
    bug7922 = '[ruby-core:52744] [Bug #7922]'
    def o.bug7922(**) end
    assert_nothing_raised(ArgumentError, bug7922) {o.bug7922(foo: 42)}
  end

  def test_keyword_splat
    assert_valid_syntax("foo(**h)", __FILE__)
    o = Object.new
    def o.kw(k1: 1, k2: 2) [k1, k2] end
    h = {k1: 11, k2: 12}
    assert_equal([11, 12], o.kw(**h))
    assert_equal([11, 22], o.kw(k2: 22, **h))
    assert_equal([11, 12], o.kw(**h, **{k2: 22}))
    assert_equal([11, 22], o.kw(**{k2: 22}, **h))
    h = {k3: 31}
    assert_raise(ArgumentError) {o.kw(**h)}
    h = {"k1"=>11, k2: 12}
    assert_raise(TypeError) {o.kw(**h)}
  end

  def test_warn_grouped_expression
    bug5214 = '[ruby-core:39050]'
    assert_warning("", bug5214) do
      assert_valid_syntax("foo \\\n(\n  true)", "test") {$VERBOSE = true}
    end
  end

  def test_warn_unreachable
    assert_warning("test:3: warning: statement not reached\n") do
      code = "loop do\n" "break\n" "foo\n" "end"
      assert_valid_syntax(code, "test") {$VERBOSE = true}
    end
  end

  def test_cmd_symbol_after_keyword
    bug6347 = '[ruby-dev:45563]'
    assert_not_label(:foo, 'if true then not_label:foo end', bug6347)
    assert_not_label(:foo, 'if false; else not_label:foo end', bug6347)
    assert_not_label(:foo, 'begin not_label:foo end', bug6347)
    assert_not_label(:foo, 'begin ensure not_label:foo end', bug6347)
  end

  def test_cmd_symbol_in_string
    bug6347 = '[ruby-dev:45563]'
    assert_not_label(:foo, '"#{not_label:foo}"', bug6347)
  end

  def test_cmd_symbol_singleton_class
    bug6347 = '[ruby-dev:45563]'
    @not_label = self
    assert_not_label(:foo, 'class << not_label:foo; end', bug6347)
  end

  def test_cmd_symbol_superclass
    bug6347 = '[ruby-dev:45563]'
    @not_label = Object
    assert_not_label(:foo, 'class Foo < not_label:foo; end', bug6347)
  end

  def test_duplicated_arg
    assert_syntax_error("def foo(a, a) end", /duplicated argument name/)
  end

  def test_duplicated_rest
    assert_syntax_error("def foo(a, *a) end", /duplicated argument name/)
  end

  def test_duplicated_opt
    assert_syntax_error("def foo(a, a=1) end", /duplicated argument name/)
  end

  def test_duplicated_opt_rest
    assert_syntax_error("def foo(a=1, *a) end", /duplicated argument name/)
  end

  def test_duplicated_rest_opt
    assert_syntax_error("def foo(*a, a=1) end", /duplicated argument name/)
  end

  def test_duplicated_rest_post
    assert_syntax_error("def foo(*a, a) end", /duplicated argument name/)
  end

  def test_duplicated_opt_post
    assert_syntax_error("def foo(a=1, a) end", /duplicated argument name/)
  end

  def test_duplicated_kw
    assert_syntax_error("def foo(a, a: 1) end", /duplicated argument name/)
  end

  def test_duplicated_rest_kw
    assert_syntax_error("def foo(*a, a: 1) end", /duplicated argument name/)
  end

  def test_duplicated_opt_kw
    assert_syntax_error("def foo(a=1, a: 1) end", /duplicated argument name/)
  end

  def test_duplicated_kw_kwrest
    assert_syntax_error("def foo(a: 1, **a) end", /duplicated argument name/)
  end

  def test_duplicated_rest_kwrest
    assert_syntax_error("def foo(*a, **a) end", /duplicated argument name/)
  end

  def test_duplicated_opt_kwrest
    assert_syntax_error("def foo(a=1, **a) end", /duplicated argument name/)
  end

  def test_duplicated_when
    w = 'warning: duplicated when clause is ignored'
    assert_warning(/3: #{w}.+4: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m){
      eval %q{
        case 1
        when 1, 1
        when 1, 1
        when 1, 1
        end
      }
    }
    assert_warning(/#{w}/){#/3: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m){
      a = 1
      eval %q{
        case 1
        when 1, 1
        when 1, a
        when 1, 1
        end
      }
    }
  end

  def test_lambda_with_space
    feature6390 = '[ruby-dev:45605]'
    assert_valid_syntax("-> (x, y) {}", __FILE__, feature6390)
  end

  def test_do_block_in_cmdarg_begin
    bug6419 = '[ruby-dev:45631]'
    assert_valid_syntax("p begin 1.times do 1 end end", __FILE__, bug6419)
  end

  def test_do_block_in_call_args
    bug9308 = '[ruby-core:59342] [Bug #9308]'
    assert_valid_syntax("bar def foo; self.each do end end", bug9308)
  end

  def test_reserved_method_no_args
    bug6403 = '[ruby-dev:45626]'
    assert_valid_syntax("def self; :foo; end", __FILE__, bug6403)
  end

  def test_unassignable
    gvar = global_variables
    %w[self nil true false __FILE__ __LINE__ __ENCODING__].each do |kwd|
      assert_raise(SyntaxError) {eval("#{kwd} = nil")}
      assert_equal(gvar, global_variables)
    end
  end

  Bug7559 = '[ruby-dev:46737]'

  def test_lineno_command_call_quote
    expected = __LINE__ + 1
    actual = caller_lineno "a
b
c
d
e"
    assert_equal(expected, actual, "#{Bug7559}: ")
  end

  def test_lineno_after_heredoc
    bug7559 = '[ruby-dev:46737]'
    expected, _, actual = __LINE__, <<eom, __LINE__
    a
    b
    c
    d
eom
    assert_equal(expected, actual, bug7559)
  end

  def test_lineno_operation_brace_block
    expected = __LINE__ + 1
    actual = caller_lineno\
    {}
    assert_equal(expected, actual)
  end

  def assert_constant_reassignment_nested(preset, op, expected, err = [], bug = '[Bug #5449]')
    [
     ["p ", ""],                # no-pop
     ["", "p Foo::Bar"],        # pop
    ].each do |p1, p2|
      src = <<-EOM.gsub(/^\s*\n/, '')
      class Foo
        #{"Bar = " + preset if preset}
      end
      #{p1}Foo::Bar #{op}= 42
      #{p2}
      EOM
      msg = "\# #{bug}\n#{src}"
      assert_valid_syntax(src, caller_locations(1, 1)[0].path, msg)
      assert_in_out_err([], src, expected, err, msg)
    end
  end

  def test_constant_reassignment_nested
    already = /already initialized constant Foo::Bar/
    uninitialized = /uninitialized constant Foo::Bar/
    assert_constant_reassignment_nested(nil,     "||", %w[42])
    assert_constant_reassignment_nested("false", "||", %w[42], already)
    assert_constant_reassignment_nested("true",  "||", %w[true])
    assert_constant_reassignment_nested(nil,     "&&", [], uninitialized)
    assert_constant_reassignment_nested("false", "&&", %w[false])
    assert_constant_reassignment_nested("true",  "&&", %w[42], already)
    assert_constant_reassignment_nested(nil,     "+",  [], uninitialized)
    assert_constant_reassignment_nested("false", "+",  [], /undefined method/)
    assert_constant_reassignment_nested("11",    "+",  %w[53], already)
  end

  def assert_constant_reassignment_toplevel(preset, op, expected, err = [], bug = '[Bug #5449]')
    [
     ["p ", ""],                # no-pop
     ["", "p ::Bar"],           # pop
    ].each do |p1, p2|
      src = <<-EOM.gsub(/^\s*\n/, '')
      #{"Bar = " + preset if preset}
      class Foo
        #{p1}::Bar #{op}= 42
        #{p2}
      end
      EOM
      msg = "\# #{bug}\n#{src}"
      assert_valid_syntax(src, caller_locations(1, 1)[0].path, msg)
      assert_in_out_err([], src, expected, err, msg)
    end
  end

  def test_constant_reassignment_toplevel
    already = /already initialized constant Bar/
    uninitialized = /uninitialized constant Bar/
    assert_constant_reassignment_toplevel(nil,     "||", %w[42])
    assert_constant_reassignment_toplevel("false", "||", %w[42], already)
    assert_constant_reassignment_toplevel("true",  "||", %w[true])
    assert_constant_reassignment_toplevel(nil,     "&&", [], uninitialized)
    assert_constant_reassignment_toplevel("false", "&&", %w[false])
    assert_constant_reassignment_toplevel("true",  "&&", %w[42], already)
    assert_constant_reassignment_toplevel(nil,     "+",  [], uninitialized)
    assert_constant_reassignment_toplevel("false", "+",  [], /undefined method/)
    assert_constant_reassignment_toplevel("11",    "+",  %w[53], already)
  end

  def test_error_message_encoding
    bug10114 = '[ruby-core:64228] [Bug #10114]'
    code = "# -*- coding: utf-8 -*-\n" "def n \"\u{2208}\"; end"
    assert_syntax_error(code, /def n "\u{2208}"; end/, bug10114)
  end

  private

  def not_label(x) @result = x; @not_label ||= nil end
  def assert_not_label(expected, src, message = nil)
    @result = nil
    assert_nothing_raised(SyntaxError, message) {eval(src)}
    assert_equal(expected, @result, message)
  end

  def make_tmpsrc(f, src)
    f.open
    f.truncate(0)
    f.puts(src)
    f.close
  end

  def with_script_lines
    script_lines = nil
    debug_lines = {}
    Object.class_eval do
      if defined?(SCRIPT_LINES__)
        script_lines = SCRIPT_LINES__
        remove_const :SCRIPT_LINES__
      end
      const_set(:SCRIPT_LINES__, debug_lines)
    end
    yield debug_lines
  ensure
    Object.class_eval do
      remove_const :SCRIPT_LINES__
      const_set(:SCRIPT_LINES__, script_lines) if script_lines
    end
  end

  def caller_lineno(*)
    caller_locations(1, 1)[0].lineno
  end
end
