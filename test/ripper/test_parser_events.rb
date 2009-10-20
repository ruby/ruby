begin

require_relative 'dummyparser'
require_relative '../ruby/envutil'
require 'test/unit'

class TestRipper_ParserEvents < Test::Unit::TestCase

  # should be enabled
=begin
  def test_event_coverage
    dispatched = Ripper::PARSER_EVENTS.map {|event,*| event }
    dispatched.each do |e|
      assert_equal true, respond_to?("test_#{e}", true),
                   "event not tested: #{e.inspect}"
    end
  end
=end

  def parse(str, nm = nil, &bl)
    dp = DummyParser.new(str)
    dp.hook(nm, &bl) if nm
    dp.parse.to_s
  end

  def test_program
    thru_program = false
    assert_equal '[void()]', parse('', :on_program) {thru_program = true}
    assert_equal true, thru_program
  end

  def test_stmts_new
    assert_equal '[void()]', parse('')
  end

  def test_stmts_add
    assert_equal '[ref(nil)]', parse('nil')
    assert_equal '[ref(nil),ref(nil)]', parse('nil;nil')
    assert_equal '[ref(nil),ref(nil),ref(nil)]', parse('nil;nil;nil')
  end

  def test_void_stmt
    assert_equal '[void()]', parse('')
    assert_equal '[void()]', parse('; ;')
  end

  def test_var_ref
    assert_equal '[ref(a)]', parse('a')
    assert_equal '[ref(nil)]', parse('nil')
    assert_equal '[ref(true)]', parse('true')
  end

  def test_BEGIN
    assert_equal '[BEGIN([void()])]', parse('BEGIN{}')
    assert_equal '[BEGIN([ref(nil)])]', parse('BEGIN{nil}')
  end

  def test_END
    assert_equal '[END([void()])]', parse('END{}')
    assert_equal '[END([ref(nil)])]', parse('END{nil}')
  end

  def test_alias
    assert_equal '[alias(symbol_literal(a),symbol_literal(b))]', parse('alias a b')
  end

  def test_var_alias
    assert_equal '[valias($a,$g)]', parse('alias $a $g')
  end

  def test_alias_error
    assert_equal '[aliaserr(valias($a,$1))]', parse('alias $a $1')
  end

  def test_arglist
    assert_equal '[fcall(m,[])]', parse('m()')
    assert_equal '[fcall(m,[1])]', parse('m(1)')
    assert_equal '[fcall(m,[1,2])]', parse('m(1,2)')
    assert_equal '[fcall(m,[*ref(r)])]', parse('m(*r)')
    assert_equal '[fcall(m,[1,*ref(r)])]', parse('m(1,*r)')
    assert_equal '[fcall(m,[1,2,*ref(r)])]', parse('m(1,2,*r)')
    assert_equal '[fcall(m,[&ref(r)])]', parse('m(&r)')
    assert_equal '[fcall(m,[1,&ref(r)])]', parse('m(1,&r)')
    assert_equal '[fcall(m,[1,2,&ref(r)])]', parse('m(1,2,&r)')
    assert_equal '[fcall(m,[*ref(a),&ref(b)])]', parse('m(*a,&b)')
    assert_equal '[fcall(m,[1,*ref(a),&ref(b)])]', parse('m(1,*a,&b)')
    assert_equal '[fcall(m,[1,2,*ref(a),&ref(b)])]', parse('m(1,2,*a,&b)')
  end

  def test_arg_paren
    # FIXME
  end

  def test_aref
    assert_equal '[aref(ref(v),[1])]', parse('v[1]')
    assert_equal '[aref(ref(v),[1,2])]', parse('v[1,2]')
  end

  def test_assocs
    assert_equal '[fcall(m,[assocs(assoc(1,2))])]', parse('m(1=>2)')
    assert_equal '[fcall(m,[assocs(assoc(1,2),assoc(3,4))])]', parse('m(1=>2,3=>4)')
    assert_equal '[fcall(m,[3,assocs(assoc(1,2))])]', parse('m(3,1=>2)')
  end

  def test_aref_field
    assert_equal '[assign(aref_field(ref(a),[1]),2)]', parse('a[1]=2')
  end

  def test_arg_ambiguous
    thru_arg_ambiguous = false
    parse('m //', :on_arg_ambiguous) {thru_arg_ambiguous = true}
    assert_equal true, thru_arg_ambiguous
  end

  def test_array   # array literal
    assert_equal '[array([1,2,3])]', parse('[1,2,3]')
  end

  def test_assign   # generic assignment
    assert_equal '[assign(var_field(v),1)]', parse('v=1')
  end

  def test_assign_error
    thru_assign_error = false
    parse('$` = 1', :on_assign_error) {thru_assign_error = true}
    assert_equal true, thru_assign_error
    thru_assign_error = false
    parse('$`, _ = 1', :on_assign_error) {thru_assign_error = true}
    assert_equal true, thru_assign_error

    thru_assign_error = false
    parse('self::X = 1', :on_assign_error) {thru_assign_error = true}
    assert_equal false, thru_assign_error
    parse('def m\n self::X = 1\nend', :on_assign_error) {thru_assign_error = true}
    assert_equal true, thru_assign_error

    thru_assign_error = false
    parse('X = 1', :on_assign_error) {thru_assign_error = true}
    assert_equal false, thru_assign_error
    parse('def m\n X = 1\nend', :on_assign_error) {thru_assign_error = true}
    assert_equal true, thru_assign_error

    thru_assign_error = false
    parse('::X = 1', :on_assign_error) {thru_assign_error = true}
    assert_equal false, thru_assign_error
    parse('def m\n ::X = 1\nend', :on_assign_error) {thru_assign_error = true}
    assert_equal true, thru_assign_error
  end

  def test_begin
    thru_begin = false
    parse('begin end', :on_begin) {thru_begin = true}
    assert_equal true, thru_begin
  end

  def test_binary
    thru_binary = nil
    %w"and or + - * / % ** | ^ & <=> > >= < <= == === != =~ !~ << >> && ||".each do |op|
      thru_binary = false
      parse("a #{op} b", :on_binary) {thru_binary = true}
      assert_equal true, thru_binary
    end
  end

  def test_block_var
    thru_block_var = false
    parse("proc{||}", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc{| |}", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc{|x|}", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc{|;y|}", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc{|x;y|}", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var

    thru_block_var = false
    parse("proc do || end", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc do | | end", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc do |x| end", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc do |;y| end", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
    thru_block_var = false
    parse("proc do |x;y| end", :on_block_var) {thru_block_var = true}
    assert_equal true, thru_block_var
  end

  def test_bodystmt
    thru_bodystmt = false
    parse("class X\nend", :on_bodystmt) {thru_bodystmt = true}
    assert_equal true, thru_bodystmt
  end

  def test_call
    bug2233 = '[ruby-core:26165]'
    tree = nil

    thru_call = false
    assert_nothing_raised {
      tree = parse("self.foo", :on_call) {thru_call = true}
    }
    assert_equal true, thru_call
    assert_equal "[call(ref(self),.,foo)]", tree
    thru_call = false
    assert_nothing_raised(bug2233) {
      tree = parse("foo.()", :on_call) {thru_call = true}
    }
    assert_equal true, thru_call
    assert_equal "[call(ref(foo),.,call,[])]", tree
  end

  def test_heredoc
    bug1921 = '[ruby-core:24855]'
    thru_heredoc_beg = false
    tree = parse("<<EOS\nheredoc\nEOS\n", :on_heredoc_beg) {thru_heredoc_beg = true}
    assert_equal true, thru_heredoc_beg
    assert_match(/string_content\(\),heredoc\n/, tree, bug1921)
    heredoc = nil
    parse("<<EOS\nheredoc1\nheredoc2\nEOS\n", :on_string_add) {|n, s| heredoc = s}
    assert_equal("heredoc1\nheredoc2\n", heredoc, bug1921)
    heredoc = nil
    parse("<<-EOS\nheredoc1\nheredoc2\n\tEOS\n", :on_string_add) {|n, s| heredoc = s}
    assert_equal("heredoc1\nheredoc2\n", heredoc, bug1921)
  end

  def test_massign
    thru_massign = false
    parse("a, b = 1, 2", :on_massign) {thru_massign = true}
    assert_equal true, thru_massign
  end

  def test_mlhs_add
    thru_mlhs_add = false
    parse("a, b = 1, 2", :on_mlhs_add) {thru_mlhs_add = true}
    assert_equal true, thru_mlhs_add
  end

  def test_mlhs_add_star
    bug2232 = '[ruby-core:26163]'

    thru_mlhs_add_star = false
    tree = parse("a, *b = 1, 2", :on_mlhs_add_star) {thru_mlhs_add_star = true}
    assert_equal true, thru_mlhs_add_star
    assert_match /mlhs_add_star\(mlhs_add\(mlhs_new\(\),a\),b\)/, tree
    thru_mlhs_add_star = false
    tree = parse("a, *b, c = 1, 2", :on_mlhs_add_star) {thru_mlhs_add_star = true}
    assert_equal true, thru_mlhs_add_star
    assert_match /mlhs_add\(mlhs_add_star\(mlhs_add\(mlhs_new\(\),a\),b\),mlhs_add\(mlhs_new\(\),c\)\)/, tree, bug2232
  end

  def test_mlhs_new
    thru_mlhs_new = false
    parse("a, b = 1, 2", :on_mlhs_new) {thru_mlhs_new = true}
    assert_equal true, thru_mlhs_new
  end

  def test_mlhs_paren
    thru_mlhs_paren = false
    parse("a, b = 1, 2", :on_mlhs_paren) {thru_mlhs_paren = true}
    assert_equal false, thru_mlhs_paren
    thru_mlhs_paren = false
    parse("(a, b) = 1, 2", :on_mlhs_paren) {thru_mlhs_paren = true}
    assert_equal true, thru_mlhs_paren
  end

=begin
  def test_brace_block
    assert_equal true, $thru__brace_block
  end

  def test_break
    assert_equal true, $thru__break
  end

  def test_case
    assert_equal true, $thru__case
  end

  def test_class
    assert_equal true, $thru__class
  end

  def test_class_name_error
    assert_equal true, $thru__class_name_error
  end

  def test_command
    assert_equal true, $thru__command
  end

  def test_command_call
    assert_equal true, $thru__command_call
  end

  def test_const_ref
    assert_equal true, $thru__const_ref
  end

  def test_constpath_field
    assert_equal true, $thru__constpath_field
  end

  def test_constpath_ref
    assert_equal true, $thru__constpath_ref
  end

  def test_def
    assert_equal true, $thru__def
  end

  def test_defined
    assert_equal true, $thru__defined
  end

  def test_defs
    assert_equal true, $thru__defs
  end

  def test_do_block
    assert_equal true, $thru__do_block
  end

  def test_dot2
    assert_equal true, $thru__dot2
  end

  def test_dot3
    assert_equal true, $thru__dot3
  end

  def test_dyna_symbol
    assert_equal true, $thru__dyna_symbol
  end

  def test_else
    assert_equal true, $thru__else
  end

  def test_elsif
    assert_equal true, $thru__elsif
  end

  def test_ensure
    assert_equal true, $thru__ensure
  end

  def test_fcall
    assert_equal true, $thru__fcall
  end

  def test_field
    assert_equal true, $thru__field
  end

  def test_for
    assert_equal true, $thru__for
  end

  def test_hash
    assert_equal true, $thru__hash
  end

  def test_if
    assert_equal true, $thru__if
  end

  def test_if_mod
    assert_equal true, $thru__if_mod
  end

  def test_ifop
    assert_equal true, $thru__ifop
  end

  def test_iter_block
    assert_equal true, $thru__iter_block
  end

  def test_method_add_arg
    assert_equal true, $thru__method_add_arg
  end

  def test_module
    assert_equal true, $thru__module
  end

  def test_mrhs_add
    assert_equal true, $thru__mrhs_add
  end

  def test_mrhs_add_star
    assert_equal true, $thru__mrhs_add_star
  end

  def test_mrhs_new
    assert_equal true, $thru__mrhs_new
  end

  def test_mrhs_new_from_arglist
    assert_equal true, $thru__mrhs_new_from_arglist
  end

  def test_next
    assert_equal true, $thru__next
  end

  def test_opassign
    assert_equal true, $thru__opassign
  end

  def test_param_error
    assert_equal true, $thru__param_error
  end

  def test_params
    assert_equal true, $thru__params
  end

  def test_paren
    assert_equal true, $thru__paren
  end

  def test_parse_error
    assert_equal true, $thru__parse_error
  end

  def test_qwords_add
    assert_equal true, $thru__qwords_add
  end

  def test_qwords_new
    assert_equal true, $thru__qwords_new
  end

  def test_redo
    assert_equal true, $thru__redo
  end

  def test_regexp_literal
    assert_equal true, $thru__regexp_literal
  end

  def test_rescue
    assert_equal true, $thru__rescue
  end

  def test_rescue_mod
    assert_equal true, $thru__rescue_mod
  end

  def test_restparam
    assert_equal true, $thru__restparam
  end

  def test_retry
    assert_equal true, $thru__retry
  end

  def test_return
    assert_equal true, $thru__return
  end

  def test_return0
    assert_equal true, $thru__return0
  end

  def test_sclass
    assert_equal true, $thru__sclass
  end

  def test_space
    assert_equal true, $thru__space
  end

  def test_string_add
    assert_equal true, $thru__string_add
  end

  def test_string_concat
    assert_equal true, $thru__string_concat
  end

  def test_string_content
    assert_equal true, $thru__string_content
  end

  def test_string_dvar
    assert_equal true, $thru__string_dvar
  end

  def test_string_embexpr
    assert_equal true, $thru__string_embexpr
  end

  def test_string_literal
    assert_equal true, $thru__string_literal
  end

  def test_super
    assert_equal true, $thru__super
  end

  def test_symbol
    assert_equal true, $thru__symbol
  end

  def test_symbol_literal
    assert_equal true, $thru__symbol_literal
  end

  def test_topconst_field
    assert_equal true, $thru__topconst_field
  end

  def test_topconst_ref
    assert_equal true, $thru__topconst_ref
  end

  def test_unary
    assert_equal true, $thru__unary
  end

  def test_undef
    assert_equal true, $thru__undef
  end

  def test_unless
    assert_equal true, $thru__unless
  end

  def test_unless_mod
    assert_equal true, $thru__unless_mod
  end

  def test_until_mod
    assert_equal true, $thru__until_mod
  end

  def test_var_field
    assert_equal true, $thru__var_field
  end

  def test_when
    assert_equal true, $thru__when
  end

  def test_while
    assert_equal true, $thru__while
  end

  def test_while_mod
    assert_equal true, $thru__while_mod
  end

  def test_word_add
    assert_equal true, $thru__word_add
  end

  def test_word_new
    assert_equal true, $thru__word_new
  end

  def test_words_add
    assert_equal true, $thru__words_add
  end

  def test_words_new
    assert_equal true, $thru__words_new
  end

  def test_xstring_add
    assert_equal true, $thru__xstring_add
  end

  def test_xstring_literal
    assert_equal true, $thru__xstring_literal
  end

  def test_xstring_new
    assert_equal true, $thru__xstring_new
  end

  def test_yield
    assert_equal true, $thru__yield
  end

  def test_yield0
    assert_equal true, $thru__yield0
  end

  def test_zsuper
    assert_equal true, $thru__zsuper
  end
=end

  def test_local_variables
    cmd = 'command(w,[regexp_literal(xstring_add(xstring_new(),25 # ),/)])'
    div = 'binary(ref(w),/,25)'
    var = '[w]'
    bug1939 = '[ruby-core:24923]'

    assert_equal("[#{cmd}]", parse('w /25 # /'), bug1939)
    assert_equal("[assign(var_field(w),1),#{div}]", parse("w = 1; w /25 # /"), bug1939)
    assert_equal("[fcall(p,[],&block([w],[#{div}]))]", parse("p{|w|w /25 # /\n}"), bug1939)
    assert_equal("[def(p,[w],bodystmt([#{div}]))]", parse("def p(w)\nw /25 # /\nend"), bug1939)
  end

  def test_block_variables
    assert_equal("[fcall(proc,[],&block([],[void()]))]", parse("proc{|;y|}"))
    if defined?(Process::RLIMIT_AS)
      assert_in_out_err(["-I#{File.dirname(__FILE__)}", "-rdummyparser"],
                        'Process.setrlimit(Process::RLIMIT_AS,102400); puts DummyParser.new("proc{|;y|}").parse',
                        ["[fcall(proc,[],&block([],[void()]))]"], [], '[ruby-dev:39423]')
    end
  end
end

rescue LoadError
end
