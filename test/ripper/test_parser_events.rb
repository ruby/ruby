begin

require 'dummyparser'
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

  def parse(str)
    DummyParser.new(str).parse.to_s
  end

  $thru_program = false

  def test_program
    assert_equal '[void()]', parse('')
    assert_equal true, $thru_program
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

=begin
  def test_arg_ambiguous
    assert_equal true, $thru__arg_ambiguous
  end
=end

  def test_array   # array literal
    assert_equal '[array([1,2,3])]', parse('[1,2,3]')
  end

  def test_assign   # generic assignment
    assert_equal '[assign(var_field(v),1)]', parse('v=1')
  end

=begin
  def test_assign_error
    assert_equal true, $thru__assign_error
  end

  def test_begin
    assert_equal true, $thru__begin
  end

  def test_binary
    assert_equal true, $thru__binary
  end

  def test_block_var
    assert_equal true, $thru__block_var
  end

  def test_bodystmt
    assert_equal true, $thru__bodystmt
  end

  def test_brace_block
    assert_equal true, $thru__brace_block
  end

  def test_break
    assert_equal true, $thru__break
  end

  def test_call
    assert_equal true, $thru__call
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

  def test_massign
    assert_equal true, $thru__massign
  end

  def test_method_add_arg
    assert_equal true, $thru__method_add_arg
  end

  def test_mlhs_add
    assert_equal true, $thru__mlhs_add
  end

  def test_mlhs_add_star
    assert_equal true, $thru__mlhs_add_star
  end

  def test_mlhs_new
    assert_equal true, $thru__mlhs_new
  end

  def test_mlhs_paren
    assert_equal true, $thru__mlhs_paren
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

end

rescue LoadError
end
