#
# dummyparser.rb
#

class Node

  def initialize( name, *nodes )
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

  def push( item )
    @list.push item
    self
  end

  def prepend( items )
    @list[0,0] = items
  end

  def to_s
    '[' + @list.join(',') + ']'
  end

end


class DummyParser < Ripper

  def method_missing( mid, *args )
    raise NoMethodError, "wrong method: #{mid}" unless /\Aon__/ === mid.to_s
    args[0]
  end

  def on__program( stmts )
    $thru_program = true
    stmts
  end

  def on__stmts_new
    NodeList.new
  end

  def on__stmts_add( stmts, st )
    stmts.push st
    stmts
  end

  def on__void_stmt
    Node.new('void')
  end

  def on__BEGIN( stmts )
    Node.new('BEGIN', stmts)
  end

  def on__END( stmts )
    Node.new('END', stmts)
  end

  def on__var_ref( name )
    Node.new('ref', name)
  end

  def on__alias(a, b)
    Node.new('alias', a, b)
  end

  def on__var_alias(a, b)
    Node.new('valias', a, b)
  end

  def on__alias_error(a)
    Node.new('aliaserr', a)
  end

  def on__aref(a, b)
    Node.new('aref', a, b)
  end

  def on__aref_field(a, b)
    Node.new('aref_field', a, b)
  end

  def on__arg_ambiguous
    Node.new('arg_ambiguous')
  end

  def on__arg_paren( args )
    args
  end

  def on__arglist_new
    NodeList.new
  end

  def on__arglist_add( list, arg )
    list.push(arg)
  end

  def on__arglist_add_block( list, blk )
    list.push('&' + blk.to_s)
  end

  def on__arglist_add_star( list, arg )
    list.push('*' + arg.to_s)
  end

  def on__arglist_prepend( list, args )
    list.prepend args
    list
  end

  def on__method_add_arg( m, arg )
    m.children.push arg
    m
  end

  def on__assoc_new(a, b)
    Node.new('assoc', a, b)
  end

  def on__bare_assoc_hash( assoc_list )
    Node.new('assocs', *assoc_list)
  end

  def on__assoclist_from_args(a)
    Node.new('assocs', *a.list)
  end

  ######## untested

  def on__array(a)
    Node.new('array', a)
  end

  def on__assign(a, b)
    Node.new('assign', a, b)
  end

  def on__assign_error(a)
    Node.new('assign_error', a)
  end

  def on__begin(a)
    Node.new('begin', a)
  end

  def on__binary(a, b, c)
    Node.new('binary', a, b, c)
  end

  def on__block_var(a)
    Node.new('block_var', a)
  end

  def on__bodystmt(a, b, c, d)
    Node.new('bodystmt', a, b, c, d)
  end

  def on__brace_block(a, b)
    Node.new('brace_block', a, b)
  end

  def on__break(a)
    Node.new('break', a)
  end

  def on__call(a, b, c)
    Node.new('call', a, b, c)
  end

  def on__case(a, b)
    Node.new('case', a, b)
  end

  def on__class(a, b, c)
    Node.new('class', a, b, c)
  end

  def on__class_name_error(a)
    Node.new('class_name_error', a)
  end

  def on__command(a, b)
    Node.new('command', a, b)
  end

  def on__command_call(a, b, c, d)
    Node.new('command_call', a, b, c, d)
  end

  def on__const_ref(a)
    Node.new('const_ref', a)
  end

  def on__constpath_field(a, b)
    Node.new('constpath_field', a, b)
  end

  def on__constpath_ref(a, b)
    Node.new('constpath_ref', a, b)
  end

  def on__def(a, b, c)
    Node.new('def', a, b, c)
  end

  def on__defined(a)
    Node.new('defined', a)
  end

  def on__defs(a, b, c, d, e)
    Node.new('defs', a, b, c, d, e)
  end

  def on__do_block(a, b)
    Node.new('do_block', a, b)
  end

  def on__dot2(a, b)
    Node.new('dot2', a, b)
  end

  def on__dot3(a, b)
    Node.new('dot3', a, b)
  end

  def on__dyna_symbol(a)
    Node.new('dyna_symbol', a)
  end

  def on__else(a)
    Node.new('else', a)
  end

  def on__elsif(a, b, c)
    Node.new('elsif', a, b, c)
  end

  def on__ensure(a)
    Node.new('ensure', a)
  end

  def on__fcall(a)
    Node.new('fcall', a)
  end

  def on__field(a, b, c)
    Node.new('field', a, b, c)
  end

  def on__for(a, b, c)
    Node.new('for', a, b, c)
  end

  def on__hash(a)
    Node.new('hash', a)
  end

  def on__if(a, b, c)
    Node.new('if', a, b, c)
  end

  def on__if_mod(a, b)
    Node.new('if_mod', a, b)
  end

  def on__ifop(a, b, c)
    Node.new('ifop', a, b, c)
  end

  def on__iter_block(a, b)
    Node.new('iter_block', a, b)
  end

  def on__massign(a, b)
    Node.new('massign', a, b)
  end

  def on__mlhs_add(a, b)
    Node.new('mlhs_add', a, b)
  end

  def on__mlhs_add_star(a, b)
    Node.new('mlhs_add_star', a, b)
  end

  def on__mlhs_new
    Node.new('mlhs_new')
  end

  def on__mlhs_paren(a)
    Node.new('mlhs_paren', a)
  end

  def on__module(a, b)
    Node.new('module', a, b)
  end

  def on__mrhs_add(a, b)
    Node.new('mrhs_add', a, b)
  end

  def on__mrhs_add_star(a, b)
    Node.new('mrhs_add_star', a, b)
  end

  def on__mrhs_new
    Node.new('mrhs_new')
  end

  def on__mrhs_new_from_arglist(a)
    Node.new('mrhs_new_from_arglist', a)
  end

  def on__next(a)
    Node.new('next', a)
  end

  def on__opassign(a, b, c)
    Node.new('opassign', a, b, c)
  end

  def on__param_error(a)
    Node.new('param_error', a)
  end

  def on__params(a, b, c, d)
    Node.new('params', a, b, c, d)
  end

  def on__paren(a)
    Node.new('paren', a)
  end

  def on__parse_error(a)
    Node.new('parse_error', a)
  end

  def on__qwords_add(a, b)
    Node.new('qwords_add', a, b)
  end

  def on__qwords_new
    Node.new('qwords_new')
  end

  def on__redo
    Node.new('redo')
  end

  def on__regexp_literal(a)
    Node.new('regexp_literal', a)
  end

  def on__rescue(a, b, c, d)
    Node.new('rescue', a, b, c, d)
  end

  def on__rescue_mod(a, b)
    Node.new('rescue_mod', a, b)
  end

  def on__restparam(a)
    Node.new('restparam', a)
  end

  def on__retry
    Node.new('retry')
  end

  def on__return(a)
    Node.new('return', a)
  end

  def on__return0
    Node.new('return0')
  end

  def on__sclass(a, b)
    Node.new('sclass', a, b)
  end

  def on__space(a)
    Node.new('space', a)
  end

  def on__string_add(a, b)
    Node.new('string_add', a, b)
  end

  def on__string_concat(a, b)
    Node.new('string_concat', a, b)
  end

  def on__string_content
    Node.new('string_content')
  end

  def on__string_dvar(a)
    Node.new('string_dvar', a)
  end

  def on__string_embexpr(a)
    Node.new('string_embexpr', a)
  end

  def on__string_literal(a)
    Node.new('string_literal', a)
  end

  def on__super(a)
    Node.new('super', a)
  end

  def on__symbol(a)
    Node.new('symbol', a)
  end

  def on__symbol_literal(a)
    Node.new('symbol_literal', a)
  end

  def on__topconst_field(a)
    Node.new('topconst_field', a)
  end

  def on__topconst_ref(a)
    Node.new('topconst_ref', a)
  end

  def on__unary(a, b)
    Node.new('unary', a, b)
  end

  def on__undef(a)
    Node.new('undef', a)
  end

  def on__unless(a, b, c)
    Node.new('unless', a, b, c)
  end

  def on__unless_mod(a, b)
    Node.new('unless_mod', a, b)
  end

  def on__until_mod(a, b)
    Node.new('until_mod', a, b)
  end

  def on__var_field(a)
    Node.new('var_field', a)
  end

  def on__when(a, b, c)
    Node.new('when', a, b, c)
  end

  def on__while(a, b)
    Node.new('while', a, b)
  end

  def on__while_mod(a, b)
    Node.new('while_mod', a, b)
  end

  def on__word_add(a, b)
    Node.new('word_add', a, b)
  end

  def on__word_new
    Node.new('word_new')
  end

  def on__words_add(a, b)
    Node.new('words_add', a, b)
  end

  def on__words_new
    Node.new('words_new')
  end

  def on__xstring_add(a, b)
    Node.new('xstring_add', a, b)
  end

  def on__xstring_literal(a)
    Node.new('xstring_literal', a)
  end

  def on__xstring_new
    Node.new('xstring_new')
  end

  def on__yield(a)
    Node.new('yield', a)
  end

  def on__yield0
    Node.new('yield0')
  end

  def on__zsuper
    Node.new('zsuper')
  end

end
