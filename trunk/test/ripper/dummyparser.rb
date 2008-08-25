#
# dummyparser.rb
#

require 'ripper'

class Node
  def initialize(name, *nodes)
    @name = name
    @children = nodes
  end

  attr_reader :children

  def to_s
    "#{@name}(#{@children.map {|n| n.to_s }.join(',')})"
  end
end

class NodeList
  def initialize
    @list = []
  end

  attr_reader :list

  def push(item)
    @list.push item
    self
  end

  def prepend(items)
    @list.unshift items
  end

  def to_s
    '[' + @list.join(',') + ']'
  end
end

class DummyParser < Ripper

  def on_program(stmts)
    $thru_program = true
    stmts
  end

  def on_stmts_new
    NodeList.new
  end

  def on_stmts_add(stmts, st)
    stmts.push st
    stmts
  end

  def on_void_stmt
    Node.new('void')
  end

  def on_BEGIN(stmts)
    Node.new('BEGIN', stmts)
  end

  def on_END(stmts)
    Node.new('END', stmts)
  end

  def on_var_ref(name)
    Node.new('ref', name)
  end

  def on_alias(a, b)
    Node.new('alias', a, b)
  end

  def on_var_alias(a, b)
    Node.new('valias', a, b)
  end

  def on_alias_error(a)
    Node.new('aliaserr', a)
  end

  def on_aref(a, b)
    Node.new('aref', a, b)
  end

  def on_aref_field(a, b)
    Node.new('aref_field', a, b)
  end

  def on_arg_ambiguous
    Node.new('arg_ambiguous')
  end

  def on_arg_paren(args)
    args
  end

  def on_args_new
    NodeList.new
  end

  def on_args_add(list, arg)
    list.push(arg)
  end

  def on_args_add_block(list, blk)
    if blk
      list.push('&' + blk.to_s)
    else
      list
    end
  end

  def on_args_add_star(list, arg)
    list.push('*' + arg.to_s)
  end

  def on_args_prepend(list, args)
    list.prepend args
    list
  end

  def on_method_add_arg(m, arg)
    if arg == nil
      arg = on_args_new
    end
    m.children.push arg
    m
  end

  def on_method_add_block(m, b)
    on_args_add_block(m.children, b)
    m
  end

  def on_assoc_new(a, b)
    Node.new('assoc', a, b)
  end

  def on_bare_assoc_hash(assoc_list)
    Node.new('assocs', *assoc_list)
  end

  def on_assoclist_from_args(a)
    Node.new('assocs', *a.list)
  end

  ######## untested

  def on_array(a)
    Node.new('array', a)
  end

  def on_assign(a, b)
    Node.new('assign', a, b)
  end

  def on_assign_error(a)
    Node.new('assign_error', a)
  end

  def on_begin(a)
    Node.new('begin', a)
  end

  def on_binary(a, b, c)
    Node.new('binary', a, b, c)
  end

  def on_block_var(a)
    Node.new('block_var', a)
  end

  def on_bodystmt(a, b, c, d)
    Node.new('bodystmt', a, b, c, d)
  end

  def on_brace_block(a, b)
    Node.new('brace_block', a, b)
  end

  def on_break(a)
    Node.new('break', a)
  end

  def on_call(a, b, c)
    Node.new('call', a, b, c)
  end

  def on_case(a, b)
    Node.new('case', a, b)
  end

  def on_class(a, b, c)
    Node.new('class', a, b, c)
  end

  def on_class_name_error(a)
    Node.new('class_name_error', a)
  end

  def on_command(a, b)
    Node.new('command', a, b)
  end

  def on_command_call(a, b, c, d)
    Node.new('command_call', a, b, c, d)
  end

  def on_const_ref(a)
    Node.new('const_ref', a)
  end

  def on_constpath_field(a, b)
    Node.new('constpath_field', a, b)
  end

  def on_constpath_ref(a, b)
    Node.new('constpath_ref', a, b)
  end

  def on_def(a, b, c)
    Node.new('def', a, b, c)
  end

  def on_defined(a)
    Node.new('defined', a)
  end

  def on_defs(a, b, c, d, e)
    Node.new('defs', a, b, c, d, e)
  end

  def on_do_block(a, b)
    Node.new('do_block', a, b)
  end

  def on_dot2(a, b)
    Node.new('dot2', a, b)
  end

  def on_dot3(a, b)
    Node.new('dot3', a, b)
  end

  def on_dyna_symbol(a)
    Node.new('dyna_symbol', a)
  end

  def on_else(a)
    Node.new('else', a)
  end

  def on_elsif(a, b, c)
    Node.new('elsif', a, b, c)
  end

  def on_ensure(a)
    Node.new('ensure', a)
  end

  def on_fcall(a)
    Node.new('fcall', a)
  end

  def on_field(a, b, c)
    Node.new('field', a, b, c)
  end

  def on_for(a, b, c)
    Node.new('for', a, b, c)
  end

  def on_hash(a)
    Node.new('hash', a)
  end

  def on_if(a, b, c)
    Node.new('if', a, b, c)
  end

  def on_if_mod(a, b)
    Node.new('if_mod', a, b)
  end

  def on_ifop(a, b, c)
    Node.new('ifop', a, b, c)
  end

  def on_iter_block(a, b)
    Node.new('iter_block', a, b)
  end

  def on_massign(a, b)
    Node.new('massign', a, b)
  end

  def on_mlhs_add(a, b)
    Node.new('mlhs_add', a, b)
  end

  def on_mlhs_add_star(a, b)
    Node.new('mlhs_add_star', a, b)
  end

  def on_mlhs_new
    Node.new('mlhs_new')
  end

  def on_mlhs_paren(a)
    Node.new('mlhs_paren', a)
  end

  def on_module(a, b)
    Node.new('module', a, b)
  end

  def on_mrhs_add(a, b)
    Node.new('mrhs_add', a, b)
  end

  def on_mrhs_add_star(a, b)
    Node.new('mrhs_add_star', a, b)
  end

  def on_mrhs_new
    Node.new('mrhs_new')
  end

  def on_mrhs_new_from_arglist(a)
    Node.new('mrhs_new_from_arglist', a)
  end

  def on_next(a)
    Node.new('next', a)
  end

  def on_opassign(a, b, c)
    Node.new('opassign', a, b, c)
  end

  def on_param_error(a)
    Node.new('param_error', a)
  end

  def on_params(a, b, c, d)
    Node.new('params', a, b, c, d)
  end

  def on_paren(a)
    Node.new('paren', a)
  end

  def on_parse_error(a)
    Node.new('parse_error', a)
  end

  def on_qwords_add(a, b)
    Node.new('qwords_add', a, b)
  end

  def on_qwords_new
    Node.new('qwords_new')
  end

  def on_redo
    Node.new('redo')
  end

  def on_regexp_literal(a)
    Node.new('regexp_literal', a)
  end

  def on_rescue(a, b, c, d)
    Node.new('rescue', a, b, c, d)
  end

  def on_rescue_mod(a, b)
    Node.new('rescue_mod', a, b)
  end

  def on_restparam(a)
    Node.new('restparam', a)
  end

  def on_retry
    Node.new('retry')
  end

  def on_return(a)
    Node.new('return', a)
  end

  def on_return0
    Node.new('return0')
  end

  def on_sclass(a, b)
    Node.new('sclass', a, b)
  end

  def on_sp(a)
    Node.new('space', a)
  end

  def on_string_add(a, b)
    Node.new('string_add', a, b)
  end

  def on_string_concat(a, b)
    Node.new('string_concat', a, b)
  end

  def on_string_content
    Node.new('string_content')
  end

  def on_string_dvar(a)
    Node.new('string_dvar', a)
  end

  def on_string_embexpr(a)
    Node.new('string_embexpr', a)
  end

  def on_string_literal(a)
    Node.new('string_literal', a)
  end

  def on_super(a)
    Node.new('super', a)
  end

  def on_symbol(a)
    Node.new('symbol', a)
  end

  def on_symbol_literal(a)
    Node.new('symbol_literal', a)
  end

  def on_topconst_field(a)
    Node.new('topconst_field', a)
  end

  def on_topconst_ref(a)
    Node.new('topconst_ref', a)
  end

  def on_unary(a, b)
    Node.new('unary', a, b)
  end

  def on_undef(a)
    Node.new('undef', a)
  end

  def on_unless(a, b, c)
    Node.new('unless', a, b, c)
  end

  def on_unless_mod(a, b)
    Node.new('unless_mod', a, b)
  end

  def on_until_mod(a, b)
    Node.new('until_mod', a, b)
  end

  def on_var_field(a)
    Node.new('var_field', a)
  end

  def on_when(a, b, c)
    Node.new('when', a, b, c)
  end

  def on_while(a, b)
    Node.new('while', a, b)
  end

  def on_while_mod(a, b)
    Node.new('while_mod', a, b)
  end

  def on_word_add(a, b)
    Node.new('word_add', a, b)
  end

  def on_word_new
    Node.new('word_new')
  end

  def on_words_add(a, b)
    Node.new('words_add', a, b)
  end

  def on_words_new
    Node.new('words_new')
  end

  def on_xstring_add(a, b)
    Node.new('xstring_add', a, b)
  end

  def on_xstring_literal(a)
    Node.new('xstring_literal', a)
  end

  def on_xstring_new
    Node.new('xstring_new')
  end

  def on_yield(a)
    Node.new('yield', a)
  end

  def on_yield0
    Node.new('yield0')
  end

  def on_zsuper
    Node.new('zsuper')
  end

  def on_backref(a)
    a
  end
  def on_comma(a)
    a
  end
  def on_gvar(a)
    a
  end
  def on_ident(a)
    a
  end
  def on_int(a)
    a
  end
  def on_kw(a)
    a
  end
  def on_lbrace(a)
    a
  end
  def on_rbrace(a)
    a
  end
  def on_lbracket(a)
    a
  end
  def on_rbracket(a)
    a
  end
  def on_lparen(a)
    a
  end
  def on_rparen(a)
    a
  end
  def on_op(a)
    a
  end
  def on_semicolon(a)
    a
  end
end
