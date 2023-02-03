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
    f&.close!
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
    f&.close!
  end

  def test_script_lines_encoding
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "script_lines.rb"), "SCRIPT_LINES__ = {}\n")
      assert_in_out_err(%w"-r./script_lines -w -Ke", "puts __ENCODING__.name",
                        %w"EUC-JP", /-K is specified/, chdir: dir)
    end
  end

  def test_anonymous_block_forwarding
    assert_syntax_error("def b; c(&); end", /no anonymous block parameter/)
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
        def b(&); c(&) end
        def c(&); yield 1 end
        a = nil
        b{|c| a = c}
        assert_equal(1, a)

        def inner
          yield
        end

        def block_only(&)
          inner(&)
        end
        assert_equal(1, block_only{1})

        def pos(arg1, &)
          inner(&)
        end
        assert_equal(2, pos(nil){2})

        def pos_kwrest(arg1, **kw, &)
          inner(&)
        end
        assert_equal(3, pos_kwrest(nil){3})

        def no_kw(arg1, **nil, &)
          inner(&)
        end
        assert_equal(4, no_kw(nil){4})

        def rest_kw(*a, kwarg: 1, &)
          inner(&)
        end
        assert_equal(5, rest_kw{5})

        def kw(kwarg:1, &)
          inner(&)
        end
        assert_equal(6, kw{6})

        def pos_kw_kwrest(arg1, kwarg:1, **kw, &)
          inner(&)
        end
        assert_equal(7, pos_kw_kwrest(nil){7})

        def pos_rkw(arg1, kwarg1:, &)
          inner(&)
        end
        assert_equal(8, pos_rkw(nil, kwarg1: nil){8})

        def all(arg1, arg2, *rest, post1, post2, kw1: 1, kw2: 2, okw1:, okw2:, &)
          inner(&)
        end
        assert_equal(9, all(nil, nil, nil, nil, okw1: nil, okw2: nil){9})

        def all_kwrest(arg1, arg2, *rest, post1, post2, kw1: 1, kw2: 2, okw1:, okw2:, **kw, &)
          inner(&)
        end
        assert_equal(10, all_kwrest(nil, nil, nil, nil, okw1: nil, okw2: nil){10})
    end;
  end

  def test_anonymous_rest_forwarding
    assert_syntax_error("def b; c(*); end", /no anonymous rest parameter/)
    assert_syntax_error("def b; c(1, *); end", /no anonymous rest parameter/)
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
        def b(*); c(*) end
        def c(*a); a end
        def d(*); b(*, *) end
        assert_equal([1, 2], b(1, 2))
        assert_equal([1, 2, 1, 2], d(1, 2))
    end;
  end

  def test_anonymous_keyword_rest_forwarding
    assert_syntax_error("def b; c(**); end", /no anonymous keyword rest parameter/)
    assert_syntax_error("def b; c(k: 1, **); end", /no anonymous keyword rest parameter/)
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
        def b(**); c(**) end
        def c(**kw); kw end
        def d(**); b(k: 1, **) end
        def e(**); b(**, k: 1) end
        def f(a: nil, **); b(**) end
        assert_equal({a: 1, k: 3}, b(a: 1, k: 3))
        assert_equal({a: 1, k: 3}, d(a: 1, k: 3))
        assert_equal({a: 1, k: 1}, e(a: 1, k: 3))
        assert_equal({k: 3}, f(a: 1, k: 3))
    end;
  end

  def test_argument_forwarding_with_anon_rest_kwrest_and_block
    assert_syntax_error("def f(*, **, &); g(...); end", /unexpected \.\.\./)
    assert_syntax_error("def f(...); g(*); end", /no anonymous rest parameter/)
    assert_syntax_error("def f(...); g(0, *); end", /no anonymous rest parameter/)
    assert_syntax_error("def f(...); g(**); end", /no anonymous keyword rest parameter/)
    assert_syntax_error("def f(...); g(x: 1, **); end", /no anonymous keyword rest parameter/)
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

  def test_hash_kwsplat_hash
    kw = {}
    h = {a: 1}
    assert_equal({}, {**{}})
    assert_equal({}, {**kw})
    assert_equal(h, {**h})
    assert_equal(false, {**{}}.frozen?)
    assert_equal(false, {**kw}.equal?(kw))
    assert_equal(false, {**h}.equal?(h))
  end

  def test_array_kwsplat_hash
    kw = {}
    h = {a: 1}
    assert_equal([], [**{}])
    assert_equal([], [**kw])
    assert_equal([h], [**h])
    assert_equal([{}], [{}])
    assert_equal([kw], [kw])
    assert_equal([h], [h])

    assert_equal([1], [1, **{}])
    assert_equal([1], [1, **kw])
    assert_equal([1, h], [1, **h])
    assert_equal([1, {}], [1, {}])
    assert_equal([1, kw], [1, kw])
    assert_equal([1, h], [1, h])

    assert_equal([], [**kw, **kw])
    assert_equal([], [**kw, **{}, **kw])
    assert_equal([1], [1, **kw, **{}, **kw])

    assert_equal([{}], [{}, **kw, **kw])
    assert_equal([kw], [kw, **kw, **kw])
    assert_equal([h], [h, **kw, **kw])
    assert_equal([h, h], [h, **kw, **kw, **h])

    assert_equal([h, {:a=>2}], [h, **{}, **h, a: 2])
    assert_equal([h, h], [h, **{}, a: 2, **h])
    assert_equal([h, h], [h, a: 2, **{}, **h])
    assert_equal([h, h], [h, a: 2, **h, **{}])
    assert_equal([h, {:a=>2}], [h, **h, a: 2, **{}])
    assert_equal([h, {:a=>2}], [h, **h, **{}, a: 2])
  end

  def test_normal_argument
    assert_valid_syntax('def foo(x) end')
    assert_syntax_error('def foo(X) end', /constant/)
    assert_syntax_error('def foo(@x) end', /instance variable/)
    assert_syntax_error('def foo(@@x) end', /class variable/)
  end

  def test_optional_argument
    assert_valid_syntax('def foo(x=nil) end')
    assert_syntax_error('def foo(X=nil) end', /constant/)
    assert_syntax_error('def foo(@x=nil) end', /instance variable/)
    assert_syntax_error('def foo(@@x=nil) end', /class variable/)
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
    assert_raise(ArgumentError) {o.kw(**h)}
  end

  def test_keyword_duplicated
    bug10315 = '[ruby-core:65625] [Bug #10315]'
    a = []
    def a.add(x) push(x); x; end
    b = a.clone
    def a.f(k:, **) k; end
    def b.f(k:) k; end
    a.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("b.f(k: b.add(1), k: b.add(2))")}
    assert_equal(2, r)
    assert_equal([1, 2], b, bug10315)
    b.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("a.f(k: a.add(1), j: a.add(2), k: a.add(3), k: a.add(4))")}
    assert_equal(4, r)
    assert_equal([1, 2, 3, 4], a)
    a.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("b.f(**{k: b.add(1), k: b.add(2)})")}
    assert_equal(2, r)
    assert_equal([1, 2], b, bug10315)
    b.clear
    r = nil
    assert_warn(/duplicated/) {r = eval("a.f(**{k: a.add(1), j: a.add(2), k: a.add(3), k: a.add(4)})")}
    assert_equal(4, r)
    assert_equal([1, 2, 3, 4], a)
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
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      bug15271 = '[ruby-core:89648] [Bug #15271]'
      assert_valid_syntax("a **{}", bug15271)
    end;
  end

  def test_keyword_self_reference
    message = /circular argument reference - var/
    assert_syntax_error("def foo(var: defined?(var)) var end", message)
    assert_syntax_error("def foo(var: var) var end", message)
    assert_syntax_error("def foo(var: bar(var)) var end", message)
    assert_syntax_error("def foo(var: bar {var}) var end", message)

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var: bar {|var| var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var: bar {| | var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var: bar {|| var}) var end")
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

    assert_syntax_error('def foo(arg1?:) end', /arg1\?/, bug11663)
    assert_syntax_error('def foo(arg1?:, arg2:) end', /arg1\?/, bug11663)
    assert_syntax_error('proc {|arg1?:|}', /arg1\?/, bug11663)
    assert_syntax_error('proc {|arg1?:, arg2:|}', /arg1\?/, bug11663)

    bug10545 = '[ruby-dev:48742] [Bug #10545]'
    assert_syntax_error('def foo(FOO: a) end', /constant/, bug10545)
    assert_syntax_error('def foo(@foo: a) end', /instance variable/)
    assert_syntax_error('def foo(@@foo: a) end', /class variable/)
  end

  def test_keywords_specified_and_not_accepted
    assert_syntax_error('def foo(a:, **nil) end', /unexpected/)
    assert_syntax_error('def foo(a:, **nil, &b) end', /unexpected/)
    assert_syntax_error('def foo(**a, **nil) end', /unexpected/)
    assert_syntax_error('def foo(**a, **nil, &b) end', /unexpected/)
    assert_syntax_error('def foo(**nil, **a) end', /unexpected/)
    assert_syntax_error('def foo(**nil, **a, &b) end', /unexpected/)

    assert_syntax_error('proc do |a:, **nil| end', /unexpected/)
    assert_syntax_error('proc do |a:, **nil, &b| end', /unexpected/)
    assert_syntax_error('proc do |**a, **nil| end', /unexpected/)
    assert_syntax_error('proc do |**a, **nil, &b| end', /unexpected/)
    assert_syntax_error('proc do |**nil, **a| end', /unexpected/)
    assert_syntax_error('proc do |**nil, **a, &b| end', /unexpected/)
  end

  def test_optional_self_reference
    message = /circular argument reference - var/
    assert_syntax_error("def foo(var = defined?(var)) var end", message)
    assert_syntax_error("def foo(var = var) var end", message)
    assert_syntax_error("def foo(var = bar(var)) var end", message)
    assert_syntax_error("def foo(var = bar {var}) var end", message)
    assert_syntax_error("def foo(var = (def bar;end; var)) var end", message)
    assert_syntax_error("def foo(var = (def self.bar;end; var)) var end", message)

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var = bar {|var| var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var = bar {| | var}) var end")
    end

    o = Object.new
    assert_warn("") do
      o.instance_eval("def foo(var = bar {|| var}) var end")
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
      all_assertions do |a|
        ["puts 1 #{op}0", "puts :a #{op}0", "m = 1; puts m #{op}0"].each do |src|
          a.for(src) do
            assert_warning(warning % [op, syn], src) do
              assert_valid_syntax(src, "test", verbose: true)
            end
          end
        end
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
    a = a = 1
    assert_valid_syntax("a b: 1")
    assert_valid_syntax("a = 1; a b: 1", bug12073)
  end

  def test_duplicated_arg
    assert_syntax_error("def foo(a, a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_, _) end")
    (obj = Object.new).instance_eval("def foo(_, x, _) x end")
    assert_equal(2, obj.foo(1, 2, 3))
  end

  def test_duplicated_rest
    assert_syntax_error("def foo(a, *a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_, *_) end")
    (obj = Object.new).instance_eval("def foo(_, x, *_) x end")
    assert_equal(2, obj.foo(1, 2, 3))
  end

  def test_duplicated_opt
    assert_syntax_error("def foo(a, a=1) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_, _=1) end")
    (obj = Object.new).instance_eval("def foo(_, x, _=42) x end")
    assert_equal(2, obj.foo(1, 2))
  end

  def test_duplicated_opt_rest
    assert_syntax_error("def foo(a=1, *a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_=1, *_) end")
    (obj = Object.new).instance_eval("def foo(_, x=42, *_) x end")
    assert_equal(42, obj.foo(1))
    assert_equal(2, obj.foo(1, 2))
  end

  def test_duplicated_rest_opt
    assert_syntax_error("def foo(*a, a=1) end", /duplicated argument name/)
  end

  def test_duplicated_rest_post
    assert_syntax_error("def foo(*a, a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(*_, _) end")
    (obj = Object.new).instance_eval("def foo(*_, x, _) x end")
    assert_equal(2, obj.foo(1, 2, 3))
    assert_equal(2, obj.foo(2, 3))
    (obj = Object.new).instance_eval("def foo(*_, _, x) x end")
    assert_equal(3, obj.foo(1, 2, 3))
    assert_equal(3, obj.foo(2, 3))
  end

  def test_duplicated_opt_post
    assert_syntax_error("def foo(a=1, a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_=1, _) end")
    (obj = Object.new).instance_eval("def foo(_=1, x, _) x end")
    assert_equal(2, obj.foo(1, 2, 3))
    assert_equal(2, obj.foo(2, 3))
    (obj = Object.new).instance_eval("def foo(_=1, _, x) x end")
    assert_equal(3, obj.foo(1, 2, 3))
    assert_equal(3, obj.foo(2, 3))
  end

  def test_duplicated_kw
    assert_syntax_error("def foo(a, a: 1) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_, _: 1) end")
    (obj = Object.new).instance_eval("def foo(_, x, _: 1) x end")
    assert_equal(3, obj.foo(2, 3))
    assert_equal(3, obj.foo(2, 3, _: 42))
    (obj = Object.new).instance_eval("def foo(x, _, _: 1) x end")
    assert_equal(2, obj.foo(2, 3))
    assert_equal(2, obj.foo(2, 3, _: 42))
  end

  def test_duplicated_rest_kw
    assert_syntax_error("def foo(*a, a: 1) end", /duplicated argument name/)
    assert_nothing_raised {def foo(*_, _: 1) end}
    (obj = Object.new).instance_eval("def foo(*_, x: 42, _: 1) x end")
    assert_equal(42, obj.foo(42))
    assert_equal(42, obj.foo(2, _: 0))
    assert_equal(2, obj.foo(x: 2, _: 0))
  end

  def test_duplicated_opt_kw
    assert_syntax_error("def foo(a=1, a: 1) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_=1, _: 1) end")
    (obj = Object.new).instance_eval("def foo(_=42, x, _: 1) x end")
    assert_equal(0, obj.foo(0))
    assert_equal(0, obj.foo(0, _: 3))
  end

  def test_duplicated_kw_kwrest
    assert_syntax_error("def foo(a: 1, **a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_: 1, **_) end")
    (obj = Object.new).instance_eval("def foo(_: 1, x: 42, **_) x end")
    assert_equal(42, obj.foo())
    assert_equal(42, obj.foo(a: 0))
    assert_equal(42, obj.foo(_: 0, a: 0))
    assert_equal(1, obj.foo(_: 0, x: 1, a: 0))
  end

  def test_duplicated_rest_kwrest
    assert_syntax_error("def foo(*a, **a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(*_, **_) end")
    (obj = Object.new).instance_eval("def foo(*_, x, **_) x end")
    assert_equal(1, obj.foo(1))
    assert_equal(1, obj.foo(1, a: 0))
    assert_equal(2, obj.foo(1, 2, a: 0))
  end

  def test_duplicated_opt_kwrest
    assert_syntax_error("def foo(a=1, **a) end", /duplicated argument name/)
    assert_valid_syntax("def foo(_=1, **_) end")
    (obj = Object.new).instance_eval("def foo(_=42, x, **_) x end")
    assert_equal(1, obj.foo(1))
    assert_equal(1, obj.foo(1, a: 0))
    assert_equal(1, obj.foo(0, 1, a: 0))
  end

  def test_duplicated_when
    w = 'warning: duplicated `when\' clause with line 3 is ignored'
    assert_warning(/3: #{w}.+4: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m) {
      eval %q{
        case 1
        when 1, 1
        when 1, 1
        when 1, 1
        end
      }
    }
    assert_warning(/#{w}/) {#/3: #{w}.+4: #{w}.+5: #{w}.+5: #{w}/m){
      a = a = 1
      eval %q{
        case 1
        when 1, 1
        when 1, a
        when 1, 1
        end
      }
    }
  end

  def test_duplicated_when_check_option
    w = /duplicated `when\' clause with line 3 is ignored/
    assert_in_out_err(%[-wc], "#{<<~"begin;"}\n#{<<~'end;'}", ["Syntax OK"], w)
    begin;
      case 1
      when 1
      when 1
      end
    end;
  end

  def test_invalid_break
    assert_syntax_error("def m; break; end", /Invalid break/)
    assert_syntax_error('/#{break}/', /Invalid break/)
    assert_syntax_error('/#{break}/o', /Invalid break/)
  end

  def test_invalid_next
    assert_syntax_error("def m; next; end", /Invalid next/)
    assert_syntax_error('/#{next}/', /Invalid next/)
    assert_syntax_error('/#{next}/o', /Invalid next/)
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

    assert_valid_syntax('->(opt = (foo.[] bar)) {}')
    assert_valid_syntax('->(opt = (foo.[]= bar)) {}')
    assert_valid_syntax('->(opt = (foo.[] bar)) do end')
    assert_valid_syntax('->(opt = (foo.[]= bar)) do end')
  end

  def test_reserved_method_no_args
    bug6403 = '[ruby-dev:45626]'
    assert_valid_syntax("def self; :foo; end", __FILE__, bug6403)
  end

  def test_unassignable
    gvar = global_variables
    %w[self nil true false __FILE__ __LINE__ __ENCODING__].each do |kwd|
      assert_syntax_error("#{kwd} = nil", /Can't .* #{kwd}$/)
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
    w = w = ""
    result = " \#{mesg} a\n" \
             "  zy\n"
    expect = '#{mesg} a'"\n" \
             ' zy'"\n"
    assert_dedented_heredoc(expect, result)
  end

  def test_dedented_heredoc_with_newline
    bug11989 = '[ruby-core:72855] [Bug #11989] after escaped newline should not be dedented'
    result = '  x\n'"  y\n" \
             "  z\n"
    expect = 'x\n'"  y\n" \
             "z\n"
    assert_dedented_heredoc(expect, result, bug11989)
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

  def test_dedented_heredoc_expr_at_beginning
    result = "  a\n" \
             '#{1}'"\n"
    expected = "  a\n" \
             '#{1}'"\n"
    assert_dedented_heredoc(expected, result)
  end

  def test_dedented_heredoc_expr_string
    result = '  one#{"  two  "}'"\n"
    expected = 'one#{"  two  "}'"\n"
    assert_dedented_heredoc(expected, result)
  end

  def test_dedented_heredoc_continued_line
    result = "  1\\\n" "  2\n"
    expected = "1\\\n" "2\n"
    assert_dedented_heredoc(expected, result)
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /can't find string "TEXT"/)
    begin;
      <<-TEXT
      \
      TEXT
    end;
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /can't find string "TEXT"/)
    begin;
      <<~TEXT
      \
      TEXT
    end;

    assert_equal("  TEXT\n", eval("<<~eos\n" "  \\\n" "TEXT\n" "eos\n"))
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

  def test_dedented_heredoc_concatenation
    assert_equal("\n0\n1", eval("<<~0 '1'\n \n0\#{}\n0"))
  end

  def test_heredoc_mixed_encoding
    e = assert_syntax_error(<<-'HEREDOC', 'UTF-8 mixed within Windows-31J source')
      #encoding: cp932
      <<-TEXT
      \xe9\x9d\u1234
      TEXT
    HEREDOC
    assert_not_match(/end-of-input/, e.message)

    e = assert_syntax_error(<<-'HEREDOC', 'UTF-8 mixed within Windows-31J source')
      #encoding: cp932
      <<-TEXT
      \xe9\x9d
      \u1234
      TEXT
    HEREDOC
    assert_not_match(/end-of-input/, e.message)

    e = assert_syntax_error(<<-'HEREDOC', 'UTF-8 mixed within Windows-31J source')
      #encoding: cp932
      <<-TEXT
      \u1234\xe9\x9d
      TEXT
    HEREDOC
    assert_not_match(/end-of-input/, e.message)

    e = assert_syntax_error(<<-'HEREDOC', 'UTF-8 mixed within Windows-31J source')
      #encoding: cp932
      <<-TEXT
      \u1234
      \xe9\x9d
      TEXT
    HEREDOC
    assert_not_match(/end-of-input/, e.message)
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

  def test_heredoc_no_terminator
    assert_syntax_error("puts <<""A\n", /can't find string "A" anywhere before EOF/)
    assert_syntax_error("puts <<""A + <<""B\n", /can't find string "A" anywhere before EOF/)
    assert_syntax_error("puts <<""A + <<""B\n", /can't find string "B" anywhere before EOF/)
  end

  def test_unterminated_heredoc
    assert_syntax_error("<<\"EOS\n\nEOS\n", /unterminated/)
    assert_syntax_error("<<\"EOS\n\"\nEOS\n", /unterminated/)
  end

  def test_unterminated_heredoc_cr
    %W[\r\n \n].each do |nl|
      assert_syntax_error("<<\"\r\"#{nl}\r#{nl}", /unterminated/, nil, "CR with #{nl.inspect}")
    end
  end

  def test__END___cr
    assert_syntax_error("__END__\r<<<<<\n", /unexpected <</)
  end

  def test_warning_for_cr
    feature8699 = '[ruby-core:56240] [Feature #8699]'
    s = assert_warning(/encountered \\r/, feature8699) do
      eval("'\r'\r")
    end
    assert_equal("\r", s)
    s = assert_warning('') do
      eval("'\r'\r\n")
    end
    assert_equal("\r", s)
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

  def test_null_range_cmdarg
    bug10957 = '[ruby-core:68477] [Bug #10957]'
    assert_ruby_status(['-c', '-e', 'p ()..0'], "", bug10957)
    assert_ruby_status(['-c', '-e', 'p ()...0'], "", bug10957)
    assert_syntax_error('0..%q.', /unterminated string/, bug10957)
    assert_syntax_error('0...%q.', /unterminated string/, bug10957)
  end

  def test_range_at_eol
    assert_warn(/\.\.\. at EOL/) {eval("1...\n2")}
    assert_warn('') {eval("(1...)")}
    assert_warn('') {eval("(1...\n2)")}
    assert_warn('') {eval("{a: 1...\n2}")}

    assert_warn(/\.\.\. at EOL/) do
      assert_valid_syntax('foo.[]= ...', verbose: true)
    end
    assert_warn(/\.\.\. at EOL/) do
      assert_valid_syntax('foo.[] ...', verbose: true)
    end
    assert_warn(/\.\.\. at EOL/) do
      assert_syntax_error('foo.[]= bar, ...', /unexpected/, verbose: true)
    end
    assert_warn(/\.\.\. at EOL/) do
      assert_syntax_error('foo.[] bar, ...', /unexpected/, verbose: true)
    end
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

  def test_invalid_literal_message
    assert_syntax_error("def :foo", /unexpected symbol literal/)
    assert_syntax_error("def 'foo'", /unexpected string literal/)
  end

  def test_fluent_dot
    assert_valid_syntax("a\n.foo")
    assert_valid_syntax("a\n&.foo")
    assert_valid_syntax("a #\n#\n.foo\n")
    assert_valid_syntax("a #\n#\n&.foo\n")
  end

  def test_safe_call_in_massign_lhs
    assert_syntax_error("*a&.x=0", /multiple assignment destination/)
    assert_syntax_error("a&.x,=0", /multiple assignment destination/)
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

  def test_warning_literal_in_condition
    assert_warn(/string literal in condition/) do
      eval('1 if ""')
    end
    assert_warn(/regex literal in condition/) do
      eval('1 if //')
    end
    assert_warning(/literal in condition/) do
      eval('1 if 1')
    end
    assert_warning(/symbol literal in condition/) do
      eval('1 if :foo')
    end
    assert_warning(/symbol literal in condition/) do
      eval('1 if :"#{"foo".upcase}"')
    end

    assert_warn('') do
      eval('1 if !""')
    end
    assert_warn('') do
      eval('1 if !//')
    end
    assert_warn('') do
      eval('1 if !(true..false)')
    end
    assert_warning('') do
      eval('1 if !1')
    end
    assert_warning('') do
      eval('1 if !:foo')
    end
    assert_warning('') do
      eval('1 if !:"#{"foo".upcase}"')
    end
  end

  def test_warning_literal_in_flip_flop
    assert_warn(/literal in flip-flop/) do
      eval('1 if ""..false')
    end
    assert_warning(/literal in flip-flop/) do
      eval('1 if :foo..false')
    end
    assert_warning(/literal in flip-flop/) do
      eval('1 if :"#{"foo".upcase}"..false')
    end
    assert_warn(/literal in flip-flop/) do
      eval('1 if ""...false')
    end
    assert_warning(/literal in flip-flop/) do
      eval('1 if :foo...false')
    end
    assert_warning(/literal in flip-flop/) do
      eval('1 if :"#{"foo".upcase}"...false')
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

  def test_parenthesised_statement_argument
    assert_syntax_error("foo(bar rescue nil)", /unexpected `rescue' modifier/)
    assert_valid_syntax("foo (bar rescue nil)")
  end

  def test_cmdarg_in_paren
    bug11873 = '[ruby-core:72482] [Bug #11873]'
    assert_valid_syntax %q{a b{c d}, :e do end}, bug11873
    assert_valid_syntax %q{a b(c d), :e do end}, bug11873
    assert_valid_syntax %q{a b{c(d)}, :e do end}, bug11873
    assert_valid_syntax %q{a b(c(d)), :e do end}, bug11873
    assert_valid_syntax %q{a b{c d}, 1 do end}, bug11873
    assert_valid_syntax %q{a b(c d), 1 do end}, bug11873
    assert_valid_syntax %q{a b{c(d)}, 1 do end}, bug11873
    assert_valid_syntax %q{a b(c(d)), 1 do end}, bug11873
    assert_valid_syntax %q{a b{c d}, "x" do end}, bug11873
    assert_valid_syntax %q{a b(c d), "x" do end}, bug11873
    assert_valid_syntax %q{a b{c(d)}, "x" do end}, bug11873
    assert_valid_syntax %q{a b(c(d)), "x" do end}, bug11873
  end

  def test_block_after_cmdarg_in_paren
    bug11873 = '[ruby-core:72482] [Bug #11873]'
    def bug11873.p(*);end;

    assert_raise(LocalJumpError, bug11873) do
      bug11873.instance_eval do
        p p{p p;p(p)}, tap do
          raise SyntaxError, "should not be passed to tap"
        end
      end
    end

    assert_raise(LocalJumpError, bug11873) do
      bug11873.instance_eval do
        p p{p(p);p p}, tap do
          raise SyntaxError, "should not be passed to tap"
        end
      end
    end
  end

  def test_do_block_in_hash_brace
    bug13073 = '[ruby-core:78837] [Bug #13073]'
    assert_valid_syntax 'p :foo, {a: proc do end, b: proc do end}', bug13073
    assert_valid_syntax 'p :foo, {:a => proc do end, b: proc do end}', bug13073
    assert_valid_syntax 'p :foo, {"a": proc do end, b: proc do end}', bug13073
    assert_valid_syntax 'p :foo, {** proc do end, b: proc do end}', bug13073
    assert_valid_syntax 'p :foo, {proc do end => proc do end, b: proc do end}', bug13073
  end

  def test_do_after_local_variable
    obj = Object.new
    def obj.m; yield; end
    result = assert_nothing_raised(SyntaxError) do
      obj.instance_eval("m = 1; m do :ok end")
    end
    assert_equal(:ok, result)
  end

  def test_brace_after_local_variable
    obj = Object.new
    def obj.m; yield; end
    result = assert_nothing_raised(SyntaxError) do
      obj.instance_eval("m = 1; m {:ok}")
    end
    assert_equal(:ok, result)
  end

  def test_brace_after_literal_argument
    bug = '[ruby-core:81037] [Bug #13547]'
    error = /unexpected '{'/
    assert_syntax_error('m "x" {}', error)
    assert_syntax_error('m 1 {}', error, bug)
    assert_syntax_error('m 1.0 {}', error, bug)
    assert_syntax_error('m :m {}', error, bug)
    assert_syntax_error('m :"#{m}" {}', error, bug)
    assert_syntax_error('m ?x {}', error, bug)
    assert_syntax_error('m %[] {}', error, bug)
    assert_syntax_error('m 0..1 {}', error, bug)
    assert_syntax_error('m [] {}', error, bug)
  end

  def test_return_toplevel
    feature4840 = '[ruby-core:36785] [Feature #4840]'
    line = __LINE__+2
    code = "#{<<~"begin;"}#{<<~'end;'}"
    begin;
      return; raise
      begin return; rescue SystemExit; exit false; end
      begin return; ensure puts "ensured"; end #=> ensured
      begin ensure return; end
      begin raise; ensure; return; end
      begin raise; rescue; return; end
      return false; raise
      return 1; raise
      "#{return}"
      raise((return; "should not raise"))
      begin raise; ensure return; end; self
      begin raise; ensure return; end and self
      nil&defined?0--begin e=no_method_error(); return; 0;end
      return puts('ignored') #=> ignored
    end;
      .split(/\n/).map {|s|[(line+=1), *s.split(/#=> /, 2)]}
    failed = proc do |n, s|
      RubyVM::InstructionSequence.compile(s, __FILE__, nil, n).disasm
    end
    Tempfile.create(%w"test_return_ .rb") do |lib|
      lib.close
      args = %W[-W0 -r#{lib.path}]
      all_assertions_foreach(feature4840, *[:main, :lib].product([:class, :top], code)) do |main, klass, (n, s, *ex)|
        if klass == :class
          s = "class X; #{s}; end"
          if main == :main
            assert_in_out_err(%[-W0], s, [], /return/, proc {failed[n, s]}, success: false)
          else
            File.write(lib, s)
            assert_in_out_err(args, "", [], /return/, proc {failed[n, s]}, success: false)
          end
        else
          if main == :main
            assert_in_out_err(%[-W0], s, ex, [], proc {failed[n, s]}, success: true)
          else
            File.write(lib, s)
            assert_in_out_err(args, "", ex, [], proc {failed[n, s]}, success: true)
          end
        end
      end
    end
  end

  def test_return_toplevel_with_argument
    assert_warn(/argument of top-level return is ignored/) {eval("return 1")}
  end

  def test_return_in_proc_in_class
    assert_in_out_err(['-e', 'class TestSyntax; proc{ return }.call; end'], "", [], /^-e:1:.*unexpected return \(LocalJumpError\)/)
  end

  def test_syntax_error_in_rescue
    bug12613 = '[ruby-core:76531] [Bug #12613]'
    assert_syntax_error("#{<<-"begin;"}\n#{<<-"end;"}", /Invalid retry/, bug12613)
    begin;
      while true
        begin
          p
        rescue
          retry
        else
          retry
        end
        break
      end
    end;
  end

  def test_syntax_error_at_newline
    expected = "\n        ^"
    assert_syntax_error("%[abcdef", expected)
    assert_syntax_error("%[abcdef\n", expected)
  end

  def test_invalid_jump
    assert_in_out_err(%w[-e redo], "", [], /^-e:1: /)
  end

  def test_keyword_not_parens
    assert_valid_syntax("not()")
  end

  def test_rescue_do_end_raised
    result = []
    assert_raise(RuntimeError) do
      eval("#{<<-"begin;"}\n#{<<-"end;"}")
      begin;
        tap do
          result << :begin
          raise "An exception occurred!"
        ensure
          result << :ensure
        end
      end;
    end
    assert_equal([:begin, :ensure], result)
  end

  def test_rescue_do_end_rescued
    result = []
    assert_nothing_raised(RuntimeError) do
      eval("#{<<-"begin;"}\n#{<<-"end;"}")
      begin;
        tap do
          result << :begin
          raise "An exception occurred!"
        rescue
          result << :rescue
        else
          result << :else
        ensure
          result << :ensure
        end
      end;
    end
    assert_equal([:begin, :rescue, :ensure], result)
  end

  def test_rescue_do_end_no_raise
    result = []
    assert_nothing_raised(RuntimeError) do
      eval("#{<<-"begin;"}\n#{<<-"end;"}")
      begin;
        tap do
          result << :begin
        rescue
          result << :rescue
        else
          result << :else
        ensure
          result << :ensure
        end
      end;
    end
    assert_equal([:begin, :else, :ensure], result)
  end

  def test_rescue_do_end_ensure_result
    result = eval("#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      proc do
        :begin
      ensure
        :ensure
      end.call
    end;
    assert_equal(:begin, result)
  end

  def test_rescue_do_end_ensure_in_lambda
    result = []
    eval("#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      -> do
        result << :begin
        raise "An exception occurred!"
      rescue
        result << :rescue
      else
        result << :else
      ensure
        result << :ensure
      end.call
    end;
    assert_equal([:begin, :rescue, :ensure], result)
  end

  def test_return_in_loop
    obj = Object.new
    def obj.test
      x = nil
      return until x unless x
    end
    assert_nil obj.test
  end

  def test_assignment_return_in_loop
    obj = Object.new
    def obj.test
      x = nil
      _y = (return until x unless x)
    end
    assert_nil obj.test, "[Bug #16695]"
  end

  def test_method_call_location
    line = __LINE__+5
    e = assert_raise(NoMethodError) do
      1.upto(0) do
      end
        .
        foo(
          1,
          2,
        )
    end
    assert_equal(line, e.backtrace_locations[0].lineno)

    line = __LINE__+5
    e = assert_raise(NoMethodError) do
      1.upto 0 do
      end
        .
        foo(
          1,
          2,
        )
    end
    assert_equal(line, e.backtrace_locations[0].lineno)
  end

  def test_methoddef_endless
    assert_valid_syntax('private def foo = 42')
    assert_valid_syntax('private def foo() = 42')
    assert_valid_syntax('private def inc(x) = x + 1')
    assert_valid_syntax('private def obj.foo = 42')
    assert_valid_syntax('private def obj.foo() = 42')
    assert_valid_syntax('private def obj.inc(x) = x + 1')
    k = Class.new do
      class_eval('def rescued(x) = raise("to be caught") rescue "instance #{x}"')
      class_eval('def self.rescued(x) = raise("to be caught") rescue "class #{x}"')
    end
    assert_equal("class ok", k.rescued("ok"))
    assert_equal("instance ok", k.new.rescued("ok"))

    error = /setter method cannot be defined in an endless method definition/
    assert_syntax_error('def foo=() = 42', error)
    assert_syntax_error('def obj.foo=() = 42', error)
    assert_syntax_error('def foo=() = 42 rescue nil', error)
    assert_syntax_error('def obj.foo=() = 42 rescue nil', error)
  end

  def test_methoddef_endless_command
    assert_valid_syntax('def foo = puts "Hello"')
    assert_valid_syntax('def foo() = puts "Hello"')
    assert_valid_syntax('def foo(x) = puts x')
    assert_valid_syntax('def obj.foo = puts "Hello"')
    assert_valid_syntax('def obj.foo() = puts "Hello"')
    assert_valid_syntax('def obj.foo(x) = puts x')
    k = Class.new do
      class_eval('def rescued(x) = raise "to be caught" rescue "instance #{x}"')
      class_eval('def self.rescued(x) = raise "to be caught" rescue "class #{x}"')
    end
    assert_equal("class ok", k.rescued("ok"))
    assert_equal("instance ok", k.new.rescued("ok"))

    # Current technical limitation: cannot prepend "private" or something for command endless def
    error = /syntax error, unexpected string literal/
    error2 = /syntax error, unexpected local variable or method/
    assert_syntax_error('private def foo = puts "Hello"', error)
    assert_syntax_error('private def foo() = puts "Hello"', error)
    assert_syntax_error('private def foo(x) = puts x', error2)
    assert_syntax_error('private def obj.foo = puts "Hello"', error)
    assert_syntax_error('private def obj.foo() = puts "Hello"', error)
    assert_syntax_error('private def obj.foo(x) = puts x', error2)
  end

  def test_methoddef_in_cond
    assert_valid_syntax('while def foo; tap do end; end; break; end')
    assert_valid_syntax('while def foo a = tap do end; end; break; end')
  end

  def test_classdef_in_cond
    assert_valid_syntax('while class Foo; tap do end; end; break; end')
    assert_valid_syntax('while class Foo a = tap do end; end; break; end')
  end

  def test_command_with_cmd_brace_block
    assert_valid_syntax('obj.foo (1) {}')
    assert_valid_syntax('obj::foo (1) {}')
  end

  def test_numbered_parameter
    assert_valid_syntax('proc {_1}')
    assert_equal(3, eval('[1,2].then {_1+_2}'))
    assert_equal("12", eval('[1,2].then {"#{_1}#{_2}"}'))
    assert_equal([1, 2], eval('[1,2].then {_1}'))
    assert_equal(3, eval('->{_1+_2}.call(1,2)'))
    assert_equal(4, eval('->(a=->{_1}){a}.call.call(4)'))
    assert_equal(5, eval('-> a: ->{_1} {a}.call.call(5)'))
    assert_syntax_error('proc {|| _1}', /ordinary parameter is defined/)
    assert_syntax_error('proc {|;a| _1}', /ordinary parameter is defined/)
    assert_syntax_error("proc {|\n| _1}", /ordinary parameter is defined/)
    assert_syntax_error('proc {|x| _1}', /ordinary parameter is defined/)
    assert_syntax_error('proc {_1; proc {_2}}', /numbered parameter is already used/)
    assert_syntax_error('proc {proc {_1}; _2}', /numbered parameter is already used/)
    assert_syntax_error('->(){_1}', /ordinary parameter is defined/)
    assert_syntax_error('->(x){_1}', /ordinary parameter is defined/)
    assert_syntax_error('->x{_1}', /ordinary parameter is defined/)
    assert_syntax_error('->x:_2{}', /ordinary parameter is defined/)
    assert_syntax_error('->x=_1{}', /ordinary parameter is defined/)
    assert_syntax_error('-> {_1; -> {_2}}', /numbered parameter is already used/)
    assert_syntax_error('-> {-> {_1}; _2}', /numbered parameter is already used/)
    assert_syntax_error('proc {_1; _1 = nil}', /Can't assign to numbered parameter _1/)
    assert_syntax_error('proc {_1 = nil}', /_1 is reserved for numbered parameter/)
    assert_syntax_error('_2=1', /_2 is reserved for numbered parameter/)
    assert_syntax_error('proc {|_3|}', /_3 is reserved for numbered parameter/)
    assert_syntax_error('def x(_4) end', /_4 is reserved for numbered parameter/)
    assert_syntax_error('def _5; end', /_5 is reserved for numbered parameter/)
    assert_syntax_error('def self._6; end', /_6 is reserved for numbered parameter/)
    assert_raise_with_message(NameError, /undefined local variable or method `_1'/) {
      eval('_1')
    }
    ['class C', 'class << C', 'module M', 'def m', 'def o.m'].each do |c|
      assert_valid_syntax("->{#{c};->{_1};end;_1}\n")
      assert_valid_syntax("->{_1;#{c};->{_1};end}\n")
    end

    1.times {
      [
        _1,
        assert_equal([:a], eval("[:a].map{_1}")),
        assert_raise(NameError) {eval("_1")},
      ]
    }
  end

  def test_value_expr_in_condition
    mesg = /void value expression/
    assert_syntax_error("tap {a = (true ? next : break)}", mesg)
    assert_valid_syntax("tap {a = (true ? true : break)}")
    assert_valid_syntax("tap {a = (break if false)}")
    assert_valid_syntax("tap {a = (break unless true)}")
  end

  def test_tautological_condition
    assert_valid_syntax("def f() return if false and invalid; nil end")
    assert_valid_syntax("def f() return unless true or invalid; nil end")
  end

  def test_argument_forwarding
    assert_valid_syntax('def foo(...) bar(...) end')
    assert_valid_syntax('def foo(...) end')
    assert_valid_syntax('def foo(a, ...) bar(...) end')
    assert_valid_syntax("def foo ...\n  bar(...)\nend")
    assert_valid_syntax("def foo a, ...\n  bar(...)\nend")
    assert_valid_syntax("def foo b = 1, ...\n  bar(...)\nend")
    assert_valid_syntax("def foo ...; bar(...); end")
    assert_valid_syntax("def foo a, ...; bar(...); end")
    assert_valid_syntax("def foo b = 1, ...; bar(...); end")
    assert_valid_syntax("(def foo ...\n  bar(...)\nend)")
    assert_valid_syntax("(def foo ...; bar(...); end)")
    assert_valid_syntax('def ==(...) end')
    assert_valid_syntax('def [](...) end')
    assert_valid_syntax('def nil(...) end')
    assert_valid_syntax('def true(...) end')
    assert_valid_syntax('def false(...) end')
    unexpected = /unexpected \.{3}/
    assert_syntax_error('iter do |...| end', /unexpected/)
    assert_syntax_error('iter {|...|}', /unexpected/)
    assert_syntax_error('->... {}', unexpected)
    assert_syntax_error('->(...) {}', unexpected)
    assert_syntax_error('def foo(x, y, z) bar(...); end', /unexpected/)
    assert_syntax_error('def foo(x, y, z) super(...); end', /unexpected/)
    assert_syntax_error('def foo(...) yield(...); end', /unexpected/)
    assert_syntax_error('def foo(...) return(...); end', /unexpected/)
    assert_syntax_error('def foo(...) a = (...); end', /unexpected/)
    assert_syntax_error('def foo(...) [...]; end', /unexpected/)
    assert_syntax_error('def foo(...) foo[...]; end', /unexpected/)
    assert_syntax_error('def foo(...) foo[...] = x; end', /unexpected/)
    assert_syntax_error('def foo(...) foo(...) { }; end', /both block arg and actual block given/)
    assert_syntax_error('def foo(...) defined?(...); end', /unexpected/)
    assert_syntax_error('def foo(*rest, ...) end', '... after rest argument')
    assert_syntax_error('def foo(*, ...) end', '... after rest argument')

    obj1 = Object.new
    def obj1.bar(*args, **kws, &block)
      if block
        block.call(args, kws)
      else
        [args, kws]
      end
    end
    obj4 = obj1.clone
    obj5 = obj1.clone
    obj1.instance_eval('def foo(...) bar(...) end', __FILE__, __LINE__)
    obj4.instance_eval("def foo ...\n  bar(...)\n""end", __FILE__, __LINE__)
    obj5.instance_eval("def foo ...; bar(...); end", __FILE__, __LINE__)

    klass = Class.new {
      def foo(*args, **kws, &block)
        if block
          block.call(args, kws)
        else
          [args, kws]
        end
      end
    }
    obj2 = klass.new
    obj2.instance_eval('def foo(...) super(...) end', __FILE__, __LINE__)

    obj3 = Object.new
    def obj3.bar(*args, &block)
      if kws = Hash.try_convert(args.last)
        args.pop
      else
        kws = {}
      end
      if block
        block.call(args, kws)
      else
        [args, kws]
      end
    end
    obj3.instance_eval('def foo(...) bar(...) end', __FILE__, __LINE__)

    [obj1, obj2, obj3, obj4, obj5].each do |obj|
      assert_warning('') {
        assert_equal([[1, 2, 3], {k1: 4, k2: 5}], obj.foo(1, 2, 3, k1: 4, k2: 5) {|*x| x})
      }
      assert_warning('') {
        assert_equal([[1, 2, 3], {k1: 4, k2: 5}], obj.foo(1, 2, 3, k1: 4, k2: 5))
      }
      array = obj == obj3 ? [] : [{}]
      assert_warning('') {
        assert_equal([array, {}], obj.foo({}) {|*x| x})
      }
      assert_warning('') {
        assert_equal([array, {}], obj.foo({}))
      }
      assert_equal(-1, obj.method(:foo).arity)
      parameters = obj.method(:foo).parameters
      assert_equal(:rest, parameters.dig(0, 0))
      assert_equal(:keyrest, parameters.dig(1, 0))
      assert_equal(:block, parameters.dig(2, 0))
    end
  end

  def test_argument_forwarding_with_leading_arguments
    obj = Object.new
    def obj.bar(*args, **kws, &block)
      if block
        block.call(args, kws)
      else
        [args, kws]
      end
    end
    obj.instance_eval('def foo(_a, ...) bar(...) end', __FILE__, __LINE__)
    assert_equal [[], {}], obj.foo(1)
    assert_equal [[2], {}], obj.foo(1, 2)
    assert_equal [[2, 3], {}], obj.foo(1, 2, 3)
    assert_equal [[], {a: 1}], obj.foo(1, a: 1)
    assert_equal [[2], {a: 1}], obj.foo(1, 2, a: 1)
    assert_equal [[2, 3], {a: 1}], obj.foo(1, 2, 3, a: 1)
    assert_equal [[2, 3], {a: 1}], obj.foo(1, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(...) bar(1, ...) end', __FILE__, __LINE__)
    assert_equal [[1], {}], obj.foo
    assert_equal [[1, 1], {}], obj.foo(1)
    assert_equal [[1, 1, 2], {}], obj.foo(1, 2)
    assert_equal [[1, 1, 2, 3], {}], obj.foo(1, 2, 3)
    assert_equal [[1], {a: 1}], obj.foo(a: 1)
    assert_equal [[1, 1], {a: 1}], obj.foo(1, a: 1)
    assert_equal [[1, 1, 2], {a: 1}], obj.foo(1, 2, a: 1)
    assert_equal [[1, 1, 2, 3], {a: 1}], obj.foo(1, 2, 3, a: 1)
    assert_equal [[1, 1, 2, 3], {a: 1}], obj.foo(1, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(a, ...) bar(a, ...) end', __FILE__, __LINE__)
    assert_equal [[4], {}], obj.foo(4)
    assert_equal [[4, 2], {}], obj.foo(4, 2)
    assert_equal [[4, 2, 3], {}], obj.foo(4, 2, 3)
    assert_equal [[4], {a: 1}], obj.foo(4, a: 1)
    assert_equal [[4, 2], {a: 1}], obj.foo(4, 2, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(_a, ...) bar(1, ...) end', __FILE__, __LINE__)
    assert_equal [[1], {}], obj.foo(4)
    assert_equal [[1, 2], {}], obj.foo(4, 2)
    assert_equal [[1, 2, 3], {}], obj.foo(4, 2, 3)
    assert_equal [[1], {a: 1}], obj.foo(4, a: 1)
    assert_equal [[1, 2], {a: 1}], obj.foo(4, 2, a: 1)
    assert_equal [[1, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1)
    assert_equal [[1, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(_a, _b, ...) bar(...) end', __FILE__, __LINE__)
    assert_equal [[], {}], obj.foo(4, 5)
    assert_equal [[2], {}], obj.foo(4, 5, 2)
    assert_equal [[2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(_a, _b, ...) bar(1, ...) end', __FILE__, __LINE__)
    assert_equal [[1], {}], obj.foo(4, 5)
    assert_equal [[1, 2], {}], obj.foo(4, 5, 2)
    assert_equal [[1, 2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[1], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[1, 2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[1, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[1, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(_a, ...) bar(1, 2, ...) end', __FILE__, __LINE__)
    assert_equal [[1, 2], {}], obj.foo(5)
    assert_equal [[1, 2, 5], {}], obj.foo(4, 5)
    assert_equal [[1, 2, 5, 2], {}], obj.foo(4, 5, 2)
    assert_equal [[1, 2, 5, 2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[1, 2, 5], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[1, 2, 5, 2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[1, 2, 5, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[1, 2, 5, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(a, b, ...) bar(b, a, ...) end', __FILE__, __LINE__)
    assert_equal [[5, 4], {}], obj.foo(4, 5)
    assert_equal [[5, 4, 2], {}], obj.foo(4, 5, 2)
    assert_equal [[5, 4, 2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[5, 4], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[5, 4, 2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[5, 4, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[5, 4, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(a, _b, ...) bar(a, ...) end', __FILE__, __LINE__)
    assert_equal [[4], {}], obj.foo(4, 5)
    assert_equal [[4, 2], {}], obj.foo(4, 5, 2)
    assert_equal [[4, 2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[4], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[4, 2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval('def foo(a, ...) bar(a, 1, ...) end', __FILE__, __LINE__)
    assert_equal [[4, 1], {}], obj.foo(4)
    assert_equal [[4, 1, 5], {}], obj.foo(4, 5)
    assert_equal [[4, 1, 5, 2], {}], obj.foo(4, 5, 2)
    assert_equal [[4, 1, 5, 2, 3], {}], obj.foo(4, 5, 2, 3)
    assert_equal [[4, 1, 5], {a: 1}], obj.foo(4, 5, a: 1)
    assert_equal [[4, 1, 5, 2], {a: 1}], obj.foo(4, 5, 2, a: 1)
    assert_equal [[4, 1, 5, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1)
    assert_equal [[4, 1, 5, 2, 3], {a: 1}], obj.foo(4, 5, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval("def foo a, ...\n bar(a, ...)\n"" end", __FILE__, __LINE__)
    assert_equal [[4], {}], obj.foo(4)
    assert_equal [[4, 2], {}], obj.foo(4, 2)
    assert_equal [[4, 2, 3], {}], obj.foo(4, 2, 3)
    assert_equal [[4], {a: 1}], obj.foo(4, a: 1)
    assert_equal [[4, 2], {a: 1}], obj.foo(4, 2, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1){|args, kws| [args, kws]}

    obj.singleton_class.send(:remove_method, :foo)
    obj.instance_eval("def foo a, ...; bar(a, ...); end", __FILE__, __LINE__)
    assert_equal [[4], {}], obj.foo(4)
    assert_equal [[4, 2], {}], obj.foo(4, 2)
    assert_equal [[4, 2, 3], {}], obj.foo(4, 2, 3)
    assert_equal [[4], {a: 1}], obj.foo(4, a: 1)
    assert_equal [[4, 2], {a: 1}], obj.foo(4, 2, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1)
    assert_equal [[4, 2, 3], {a: 1}], obj.foo(4, 2, 3, a: 1){|args, kws| [args, kws]}

    exp = eval("-> (a: nil) {a...1}")
    assert_equal 0...1, exp.call(a: 0)
  end

  def test_class_module_Object_ancestors
    assert_separately([], <<-RUBY)
      m = Module.new
      m::Bug18832 = 1
      include m
      class Bug18832; end
    RUBY
    assert_separately([], <<-RUBY)
      m = Module.new
      m::Bug18832 = 1
      include m
      module Bug18832; end
    RUBY
  end

  def test_cdhash
    assert_separately([], <<-RUBY)
      n = case 1 when 2r then false else true end
      assert_equal(n, true, '[ruby-core:103759] [Bug #17854]')
    RUBY
    assert_separately([], <<-RUBY)
      n = case 3/2r when 1.5r then true else false end
      assert_equal(n, true, '[ruby-core:103759] [Bug #17854]')
    RUBY
    assert_separately([], <<-RUBY)
      n = case 1i when 1i then true else false end
      assert_equal(n, true, '[ruby-core:103759] [Bug #17854]')
    RUBY
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
