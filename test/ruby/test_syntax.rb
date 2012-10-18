require 'test/unit'
require_relative 'envutil'

class TestSyntax < Test::Unit::TestCase
  def assert_valid_syntax(code, fname, mesg = fname)
    code = code.dup.force_encoding("ascii-8bit")
    code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
      "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
    }
    code.force_encoding("us-ascii")
    verbose, $VERBOSE = $VERBOSE, nil
    yield if defined?(yield)
    assert_nothing_raised(SyntaxError, mesg) do
      assert_equal(:ok, catch {|tag| eval(code, binding, fname, 0)}, mesg)
    end
  ensure
    $VERBOSE = verbose
  end

  def test_syntax
    assert_nothing_raised(Exception) do
      for script in Dir[File.expand_path("../../../{lib,sample,ext,test}/**/*.rb", __FILE__)].sort
        assert_valid_syntax(IO::read(script), script)
      end
    end
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
    assert_warn("", bug5214) do
      assert_valid_syntax("foo \\\n(\n  true)", "test") {$VERBOSE = true}
    end
  end

  def test_warn_unreachable
    assert_warn("test:3: warning: statement not reached\n") do
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

  def test_duplicated_when
    w = 'warning: duplicated when clause is ignored'
    assert_warn(/3: #{w}.+4: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m){
      eval %q{
        case 1
        when 1, 1
        when 1, 1
        when 1, 1
        end
      }
    }
    assert_warn(/#{w}/){#/3: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m){
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
end
