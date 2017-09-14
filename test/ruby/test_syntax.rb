# frozen_string_literal: false
require 'test/unit'

class TestSyntax < Test::Unit::TestCase
  using Module.new {
    refine(Object) do
      def `(s) #`
        s
      end
    end
  }

  def assert_syntax_files(test)
    srcdir = File.expand_path("../../..", __FILE__)
    srcdir = File.join(srcdir, test)
    assert_separately(%W[--disable-gem - #{srcdir}],
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
  ensure
    f.close! if f
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
  ensure
    f.close! if f
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

  class KW2
    def kw(k1: 1, k2: 2) [k1, k2] end
  end

  def test_keyword_splat
    assert_valid_syntax("foo(**h)", __FILE__)
    o = KW2.new
    h = {k1: 11, k2: 12}
    assert_equal([11, 12], o.kw(**h))
    assert_equal([11, 12], o.kw(k2: 22, **h))
    assert_equal([11, 22], o.kw(**h, **{k2: 22}))
    assert_equal([11, 12], o.kw(**{k2: 22}, **h))
  end

  def test_keyword_duplicated_splat
    bug10315 = '[ruby-core:65368] [Bug #10315]'

    o = KW2.new
    assert_equal([23, 2], o.kw(**{k1: 22}, **{k1: 23}), bug10315)

    h = {k3: 31}
    assert_raise(ArgumentError) {o.kw(**h)}
    h = {"k1"=>11, k2: 12}
    assert_raise(TypeError) {o.kw(**h)}
  end

  def test_keyword_duplicated
    bug10315 = '[ruby-core:65625] [Bug #10315]'
    a = []
    def a.add(x) push(x); x; end
    def a.f(k:) k; end
    a.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("a.f(k: a.add(1), k: a.add(2))")}
    assert_equal(2, r)
    assert_equal([1, 2], a, bug10315)
    a.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("a.f({k: a.add(1), k: a.add(2)})")}
    assert_equal(2, r)
    assert_equal([1, 2], a, bug10315)
  end

  def test_keyword_empty_splat
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      bug10719 = '[ruby-core:67446] [Bug #10719]'
      assert_valid_syntax("foo(a: 1, **{})", bug10719)
    end;
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      bug13756 = '[ruby-core:82113] [Bug #13756]'
      assert_valid_syntax("defined? foo(**{})", bug13756)
    end;
  end

  def test_keyword_self_reference
    bug9593 = '[ruby-core:61299] [Bug #9593]'
    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var: defined?(var)) var end")
    end
    assert_equal(42, o.foo(var: 42))
    assert_equal("local-variable", o.foo, bug9593)

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var: var) var end")
    end
    assert_nil(o.foo, bug9593)

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var: bar(var)) var end")
    end

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var: bar {var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var: bar {|var| var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var: def bar(var) var; end) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("proc {|var: 1| var}")
    end
  end

  def test_keyword_invalid_name
    bug11663 = '[ruby-core:71356] [Bug #11663]'

    o = Object.new
    assert_syntax_error('def o.foo(arg1?:) end', /arg1\?/, bug11663)
    assert_syntax_error('def o.foo(arg1?:, arg2:) end', /arg1\?/, bug11663)
    assert_syntax_error('proc {|arg1?:|}', /arg1\?/, bug11663)
    assert_syntax_error('proc {|arg1?:, arg2:|}', /arg1\?/, bug11663)
  end

  def test_optional_self_reference
    bug9593 = '[ruby-core:61299] [Bug #9593]'
    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = defined?(var)) var end")
    end
    assert_equal(42, o.foo(42))
    assert_equal("local-variable", o.foo, bug9593)

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = var) var end")
    end
    assert_nil(o.foo, bug9593)

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = bar(var)) var end")
    end

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = bar {var}) var end")
    end

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = (def bar;end; var)) var end")
    end

    o = Object.new
    assert_warn(/circular argument reference - var/) do
      o.instance_eval("def foo(var = (def self.bar;end; var)) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var = bar {|var| var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var = def bar(var) var; end) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("proc {|var = 1| var}")
    end
  end

  def test_warn_grouped_expression
    bug5214 = '[ruby-core:39050]'
    assert_warning("", bug5214) do
      assert_valid_syntax("foo \\\n(\n  true)", "test", verbose: true)
    end
  end

  def test_warn_unreachable
    assert_warning("test:3: warning: statement not reached\n") do
      code = "loop do\n" "break\n" "foo\n" "end"
      assert_valid_syntax(code, "test", verbose: true)
    end
  end

  def test_warn_balanced
    warning = <<WARN
test:1: warning: `%s' after local variable or literal is interpreted as binary operator
test:1: warning: even though it seems like %s
WARN
    [
     [:**, "argument prefix"],
     [:*, "argument prefix"],
     [:<<, "here document"],
     [:&, "argument prefix"],
     [:+, "unary operator"],
     [:-, "unary operator"],
     [:/, "regexp literal"],
     [:%, "string literal"],
    ].each do |op, syn|
      assert_warning(warning % [op, syn]) do
        assert_valid_syntax("puts 1 #{op}0", "test", verbose: true)
      end
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

  def test_no_label_with_percent
    assert_syntax_error('{%"a": 1}', /unexpected ':'/)
    assert_syntax_error("{%'a': 1}", /unexpected ':'/)
    assert_syntax_error('{%Q"a": 1}', /unexpected ':'/)
    assert_syntax_error("{%Q'a': 1}", /unexpected ':'/)
    assert_syntax_error('{%q"a": 1}', /unexpected ':'/)
    assert_syntax_error("{%q'a': 1}", /unexpected ':'/)
  end

  def test_block_after_cond
    bug10653 = '[ruby-dev:48790] [Bug #10653]'
    assert_valid_syntax("false ? raise {} : tap {}", bug10653)
    assert_valid_syntax("false ? raise do end : tap do end", bug10653)
  end

  def test_paren_after_label
    bug11456 = '[ruby-dev:49221] [Bug #11456]'
    assert_valid_syntax("{foo: (1 rescue 0)}", bug11456)
    assert_valid_syntax("{foo: /=/}", bug11456)
  end

  def test_percent_string_after_label
    bug11812 = '[ruby-core:72084]'
    assert_valid_syntax('{label:%w(*)}', bug11812)
    assert_valid_syntax('{label: %w(*)}', bug11812)
  end

  def test_heredoc_after_label
    bug11849 = '[ruby-core:72396] [Bug #11849]'
    assert_valid_syntax("{label:<<DOC\n""DOC\n""}", bug11849)
    assert_valid_syntax("{label:<<-DOC\n""DOC\n""}", bug11849)
    assert_valid_syntax("{label:<<~DOC\n""DOC\n""}", bug11849)
    assert_valid_syntax("{label: <<DOC\n""DOC\n""}", bug11849)
    assert_valid_syntax("{label: <<-DOC\n""DOC\n""}", bug11849)
    assert_valid_syntax("{label: <<~DOC\n""DOC\n""}", bug11849)
  end

  def test_cmdarg_kwarg_lvar_clashing_method
    bug12073 = '[ruby-core:73816] [Bug#12073]'
    a = 1
    assert_valid_syntax("a b: 1")
    assert_valid_syntax("a = 1; a b: 1", bug12073)
  end

  def test_duplicated_arg
    assert_syntax_error("def foo(a, a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_, _) end }
  end

  def test_duplicated_rest
    assert_syntax_error("def foo(a, *a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_, *_) end }
  end

  def test_duplicated_opt
    assert_syntax_error("def foo(a, a=1) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_, _=1) end }
  end

  def test_duplicated_opt_rest
    assert_syntax_error("def foo(a=1, *a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_=1, *_) end }
  end

  def test_duplicated_rest_opt
    assert_syntax_error("def foo(*a, a=1) end", /duplicated argument name/)
  end

  def test_duplicated_rest_post
    assert_syntax_error("def foo(*a, a) end", /duplicated argument name/)
  end

  def test_duplicated_opt_post
    assert_syntax_error("def foo(a=1, a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_=1, _) end }
  end

  def test_duplicated_kw
    assert_syntax_error("def foo(a, a: 1) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_, _: 1) end }
  end

  def test_duplicated_rest_kw
    assert_syntax_error("def foo(*a, a: 1) end", /duplicated argument name/)
    assert_nothing_raised {def foo(*_, _: 1) end}
  end

  def test_duplicated_opt_kw
    assert_syntax_error("def foo(a=1, a: 1) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_=1, _: 1) end }
  end

  def test_duplicated_kw_kwrest
    assert_syntax_error("def foo(a: 1, **a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_: 1, **_) end }
  end

  def test_duplicated_rest_kwrest
    assert_syntax_error("def foo(*a, **a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(*_, **_) end }
  end

  def test_duplicated_opt_kwrest
    assert_syntax_error("def foo(a=1, **a) end", /duplicated argument name/)
    assert_nothing_raised { def foo(_=1, **_) end }
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

  def test_invalid_break
    assert_syntax_error("def m; break; end", /Invalid break/)
    assert_in_out_err([], '/#{break}/', [],  /Invalid break \(SyntaxError\)$/)
    assert_in_out_err([], '/#{break}/o', [],  /Invalid break \(SyntaxError\)$/)
  end

  def test_invalid_next
    assert_syntax_error("def m; next; end", /Invalid next/)
    assert_in_out_err([], '/#{next}/', [],  /Invalid next \(SyntaxError\)$/)
    assert_in_out_err([], '/#{next}/o', [],  /Invalid next \(SyntaxError\)$/)
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

  def test_do_block_in_lambda
    bug11107 = '[ruby-core:69017] [Bug #11107]'
    assert_valid_syntax('p ->() do a() do end end', bug11107)
  end

  def test_do_block_after_lambda
    bug11380 = '[ruby-core:70067] [Bug #11380]'
    assert_valid_syntax('p -> { :hello }, a: 1 do end', bug11380)
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

  def assert_dedented_heredoc(expect, result, mesg = "")
    all_assertions(mesg) do |a|
      %w[eos "eos" 'eos' `eos`].each do |eos|
        a.for(eos) do
          assert_equal(eval("<<-#{eos}\n#{expect}eos\n"),
                       eval("<<~#{eos}\n#{result}eos\n"))
        end
      end
    end
  end

  def test_dedented_heredoc_without_indentation
    result = " y\n" \
             "z\n"
    expect = result
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_indentation
    result = "     a\n" \
             "    b\n"
    expect = " a\n" \
             "b\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_blank_less_indented_line
    # the blank line has two leading spaces
    result = "    a\n" \
             "  \n" \
             "    b\n"
    expect = "a\n" \
             "\n" \
             "b\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_blank_less_indented_line_escaped
    result = "    a\n" \
             "\\ \\ \n" \
             "    b\n"
    expect = result
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_blank_more_indented_line
    # the blank line has six leading spaces
    result = "    a\n" \
             "      \n" \
             "    b\n"
    expect = "a\n" \
             "  \n" \
             "b\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_blank_more_indented_line_escaped
    result = "    a\n" \
             "\\ \\ \\ \\ \\ \\ \n" \
             "    b\n"
    expect = result
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_empty_line
    result = "      This would contain specially formatted text.\n" \
             "\n" \
             "      That might span many lines\n"
    expect = 'This would contain specially formatted text.'"\n" \
             ''"\n" \
             'That might span many lines'"\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_interpolated_expression
    result = '  #{1}a'"\n" \
             " zy\n"
    expect = ' #{1}a'"\n" \
             "zy\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_interpolated_string
    w = ""
    result = " \#{mesg} a\n" \
             "  zy\n"
    expect = '#{mesg} a'"\n" \
             ' zy'"\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_concatenation
    bug11990 = '[ruby-core:72857] [Bug #11990] concatenated string should not be dedented'
    %w[eos "eos" 'eos'].each do |eos|
      assert_equal("x\n  y",
                   eval("<<~#{eos} '  y'\n  x\neos\n"),
                   "#{bug11990} with #{eos}")
    end
    %w[eos "eos" 'eos' `eos`].each do |eos|
      _, expect = eval("[<<~#{eos}, '  x']\n""  y\n""eos\n")
      assert_equal('  x', expect, bug11990)
    end
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

  def test_dedented_heredoc_invalid_identifer
    assert_syntax_error('<<~ "#{}"', /unexpected <</)
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

  def test_integer_suffix
    ["1if true", "begin 1end"].each do |src|
      assert_valid_syntax(src)
      assert_equal(1, eval(src), src)
    end
  end

  def test_value_of_def
    assert_separately [], <<-EOS
      assert_equal(:foo, (def foo; end))
      assert_equal(:foo, (def (Object.new).foo; end))
    EOS
  end

  def test_heredoc_cr
    assert_syntax_error("puts <<""EOS\n""ng\n""EOS\r""NO\n", /can't find string "EOS" anywhere before EOF/)
  end

  def test__END___cr
    assert_syntax_error("__END__\r<<<<<\n", /unexpected <</)
  end

  def test_warning_for_cr
    feature8699 = '[ruby-core:56240] [Feature #8699]'
    assert_warning(/encountered \\r/, feature8699) do
      eval("\r""__id__\r")
    end
  end

  def test_unexpected_fraction
    msg = /unexpected fraction/
    assert_syntax_error("0x0.0", msg)
    assert_syntax_error("0b0.0", msg)
    assert_syntax_error("0d0.0", msg)
    assert_syntax_error("0o0.0", msg)
    assert_syntax_error("0.0.0", msg)
  end

  def test_error_message_encoding
    bug10114 = '[ruby-core:64228] [Bug #10114]'
    code = "# -*- coding: utf-8 -*-\n" "def n \"\u{2208}\"; end"
    assert_syntax_error(code, /def n "\u{2208}"; end/, bug10114)
  end

  def test_bad_kwarg
    bug10545 = '[ruby-dev:48742] [Bug #10545]'
    src = 'def foo(A: a) end'
    assert_syntax_error(src, /formal argument/, bug10545)
  end

  def test_null_range_cmdarg
    bug10957 = '[ruby-core:68477] [Bug #10957]'
    assert_ruby_status(['-c', '-e', 'p ()..0'], "", bug10957)
    assert_ruby_status(['-c', '-e', 'p ()...0'], "", bug10957)
    assert_syntax_error('0..%w.', /unterminated string/, bug10957)
    assert_syntax_error('0...%w.', /unterminated string/, bug10957)
  end

  def test_too_big_nth_ref
    bug11192 = '[ruby-core:69393] [Bug #11192]'
    assert_warn(/too big/, bug11192) do
      eval('$99999999999999999')
    end
  end

  def test_invalid_symbol_space
    assert_syntax_error(": foo", /unexpected ':'/)
    assert_syntax_error(": #\n foo", /unexpected ':'/)
    assert_syntax_error(":#\n foo", /unexpected ':'/)
  end

  def test_fluent_dot
    assert_valid_syntax("a\n.foo")
    assert_valid_syntax("a\n&.foo")
  end

  def test_no_warning_logop_literal
    assert_warning("") do
      eval("true||raise;nil")
    end
    assert_warning("") do
      eval("false&&raise;nil")
    end
    assert_warning("") do
      eval("''||raise;nil")
    end
  end

  def test_alias_symbol
    bug8851 = '[ruby-dev:47681] [Bug #8851]'
    formats = ['%s', ":'%s'", ':"%s"', '%%s(%s)']
    all_assertions(bug8851) do |all|
      formats.product(formats) do |form1, form2|
        all.for(code = "alias #{form1 % 'a'} #{form2 % 'p'}") do
          assert_valid_syntax(code)
        end
      end
    end
  end

  def test_undef_symbol
    bug8851 = '[ruby-dev:47681] [Bug #8851]'
    formats = ['%s', ":'%s'", ':"%s"', '%%s(%s)']
    all_assertions(bug8851) do |all|
      formats.product(formats) do |form1, form2|
        all.for(code = "undef #{form1 % 'a'}, #{form2 % 'p'}") do
          assert_valid_syntax(code)
        end
      end
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

  def caller_lineno(*)
    caller_locations(1, 1)[0].lineno
  end
end
