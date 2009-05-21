define rp
  if (VALUE)($arg0) & RUBY_FIXNUM_FLAG
    printf "FIXNUM: %ld\n", (long)($arg0) >> 1
  else
  if ((VALUE)($arg0) & ~(~(VALUE)0<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG
    set $id = (($arg0) >> RUBY_SPECIAL_SHIFT)
    if $id == '!' || $id == '+' || $id == '-' || $id == '*' || $id == '/' || $id == '%' || $id == '<' || $id == '>' || $id == '`'
      printf "SYMBOL(:%c)\n", $id
    else
    if $id == idDot2
      echo SYMBOL(:..)\n
    else
    if $id == idDot3
      echo SYMBOL(:...)\n
    else
    if $id == idUPlus
      echo SYMBOL(:+@)\n
    else
    if $id == idUMinus
      echo SYMBOL(:-@)\n
    else
    if $id == idPow
      echo SYMBOL(:**)\n
    else
    if $id == idCmp
      echo SYMBOL(:<=>)\n
    else
    if $id == idLTLT
      echo SYMBOL(:<<)\n
    else
    if $id == idLE
      echo SYMBOL(:<=)\n
    else
    if $id == idGE
      echo SYMBOL(:>=)\n
    else
    if $id == idEq
      echo SYMBOL(:==)\n
    else
    if $id == idEqq
      echo SYMBOL(:===)\n
    else
    if $id == idNeq
      echo SYMBOL(:!=)\n
    else
    if $id == idEqTilde
      echo SYMBOL(:=~)\n
    else
    if $id == idNeqTilde
      echo SYMBOL(:!~)\n
    else
    if $id == idAREF
      echo SYMBOL(:[])\n
    else
    if $id == idASET
      echo SYMBOL(:[]=)\n
    else
      printf "SYMBOL(%ld)\n", $id
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
    end
  else
  if ($arg0) == RUBY_Qfalse
    echo false\n
  else
  if ($arg0) == RUBY_Qtrue
    echo true\n
  else
  if ($arg0) == RUBY_Qnil
    echo nil\n
  else
  if ($arg0) == RUBY_Qundef
    echo undef\n
  else
  if (VALUE)($arg0) & RUBY_IMMEDIATE_MASK
    echo immediate\n
  else
  set $flags = ((struct RBasic*)($arg0))->flags
  if ($flags & RUBY_T_MASK) == RUBY_T_NONE
    printf "T_NONE: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_NIL
    printf "T_NIL: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_OBJECT
    printf "T_OBJECT: "
    print (struct RObject *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_CLASS
    printf "T_CLASS: "
    print (struct RClass *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_ICLASS
    printf "T_ICLASS: "
    print (struct RClass *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_MODULE
    printf "T_MODULE: "
    print (struct RClass *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FLOAT
    printf "T_FLOAT: %.16g ", (((struct RFloat*)($arg0))->float_value)
    print (struct RFloat *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_STRING
    printf "T_STRING: "
    set print address off
    output (char *)(($flags & RUBY_FL_USER1) ? \
	    ((struct RString*)($arg0))->as.heap.ptr : \
	    ((struct RString*)($arg0))->as.ary)
    set print address on
    printf " bytesize:%ld ", ($flags & RUBY_FL_USER1) ? \
            ((struct RString*)($arg0))->as.heap.len : \
            (($flags & (RUBY_FL_USER2|RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5|RUBY_FL_USER6)) >> RUBY_FL_USHIFT+2)
    if !($flags & RUBY_FL_USER1)
      printf "(embed) "
    else
      if ($flags & RUBY_FL_USER2)
        printf "(shared) "
      end
      if ($flags & RUBY_FL_USER3)
        printf "(assoc) "
      end
    end
    printf "encoding:%d ", ($flags & RUBY_ENCODING_MASK) >> RUBY_ENCODING_SHIFT
    if ($flags & RUBY_ENC_CODERANGE_MASK) == 0
      printf "coderange:unknown "
    else
    if ($flags & RUBY_ENC_CODERANGE_MASK) == RUBY_ENC_CODERANGE_7BIT
      printf "coderange:7bit "
    else
    if ($flags & RUBY_ENC_CODERANGE_MASK) == RUBY_ENC_CODERANGE_VALID
      printf "coderange:valid "
    else
      printf "coderange:broken "
    end
    end
    end
    print (struct RString *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_REGEXP
    set $regsrc = ((struct RRegexp*)($arg0))->src
    set $rsflags = ((struct RBasic*)$regsrc)->flags
    printf "T_REGEXP: "
    set print address off
    output (char *)(($rsflags & RUBY_FL_USER1) ? \
	    ((struct RString*)$regsrc)->as.heap.ptr : \
	    ((struct RString*)$regsrc)->as.ary)
    set print address on
    printf " len:%ld ", ($rsflags & RUBY_FL_USER1) ? \
            ((struct RString*)$regsrc)->as.heap.len : \
            (($rsflags & (RUBY_FL_USER2|RUBY_FL_USER3|RUBY_FL_USER4|RUBY_FL_USER5|RUBY_FL_USER6)) >> RUBY_FL_USHIFT+2)
    if $flags & RUBY_FL_USER6
      printf "(none) "
    end
    if $flags & RUBY_FL_USER5
      printf "(literal) "
    end
    if $flags & RUBY_FL_USER4
      printf "(fixed) "
    end
    printf "encoding:%d ", ($flags & RUBY_ENCODING_MASK) >> RUBY_ENCODING_SHIFT
    print (struct RRegexp *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_ARRAY
    if ($flags & RUBY_FL_USER1)
      set $len = (($flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
      printf "T_ARRAY: len=%ld ", $len
      printf "(embed) "
      if ($len == 0)
	printf "{(empty)} "
      else
	output/x *((VALUE*)((struct RArray*)($arg0))->as.ary) @ $len
	printf " "
      end
    else
      set $len = ((struct RArray*)($arg0))->as.heap.len
      printf "T_ARRAY: len=%ld ", $len
      if ($flags & RUBY_FL_USER2)
	printf "(shared) shared="
	output/x ((struct RArray*)($arg0))->as.heap.aux.shared
	printf " "
      else
	printf "(ownership) capa=%ld ", ((struct RArray*)($arg0))->as.heap.aux.capa
      end
      if ($len == 0)
	printf "{(empty)} "
      else
	output/x *((VALUE*)((struct RArray*)($arg0))->as.heap.ptr) @ $len
	printf " "
      end
    end
    print (struct RArray *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FIXNUM
    printf "T_FIXNUM: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_HASH
    printf "T_HASH: ",
    if ((struct RHash *)($arg0))->ntbl
      printf "len=%ld ", ((struct RHash *)($arg0))->ntbl->num_entries
    end
    print (struct RHash *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_STRUCT
    printf "T_STRUCT: len=%ld ", \
      (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
       ($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) >> (RUBY_FL_USHIFT+1) : \
       ((struct RStruct *)($arg0))->as.heap.len)
    print (struct RStruct *)($arg0)
    x/xw (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
          ((struct RStruct *)($arg0))->as.ary : \
          ((struct RStruct *)($arg0))->as.heap.ptr)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_BIGNUM
    printf "T_BIGNUM: sign=%d len=%ld ", \
      (($flags & RUBY_FL_USER1) != 0), \
      (($flags & RUBY_FL_USER2) ? \
       ($flags & (RUBY_FL_USER5|RUBY_FL_USER4|RUBY_FL_USER3)) >> (RUBY_FL_USHIFT+3) : \
       ((struct RBignum*)($arg0))->as.heap.len)
    if $flags & RUBY_FL_USER2
      printf "(embed) "
    end
    print (struct RBignum *)($arg0)
    x/xw (($flags & RUBY_FL_USER2) ? \
          ((struct RBignum*)($arg0))->as.ary : \
          ((struct RBignum*)($arg0))->as.heap.digits)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_RATIONAL
    printf "T_RATIONAL: "
    print (struct RRational *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_COMPLEX
    printf "T_COMPLEX: "
    print (struct RComplex *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FILE
    printf "T_FILE: "
    print (struct RFile *)($arg0)
    output *((struct RFile *)($arg0))->fptr
    printf "\n"
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_TRUE
    printf "T_TRUE: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FALSE
    printf "T_FALSE: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_DATA
    printf "T_DATA: "
    print (struct RData *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_MATCH
    printf "T_MATCH: "
    print (struct RMatch *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_SYMBOL
    printf "T_SYMBOL: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_UNDEF
    printf "T_UNDEF: "
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_NODE
    printf "T_NODE("
    output (enum node_type)(($flags&RUBY_NODE_TYPEMASK)>>RUBY_NODE_TYPESHIFT)
    printf "): "
    print *(NODE *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_ZOMBIE
    printf "T_ZOMBIE: "
    print (struct RData *)($arg0)
  else
    printf "unknown: "
    print (struct RBasic *)($arg0)
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
  end
end
document rp
  Print a Ruby's VALUE.
end

define nd_type
  print (enum node_type)((((NODE*)($arg0))->flags&RUBY_NODE_TYPEMASK)>>RUBY_NODE_TYPESHIFT)
end
document nd_type
  Print a Ruby' node type.
end

define nd_file
  print ((NODE*)($arg0))->nd_file
end
document nd_file
  Print the source file name of a node.
end

define nd_line
  print ((unsigned int)((((NODE*)($arg0))->flags>>RUBY_NODE_LSHIFT)&RUBY_NODE_LMASK))
end
document nd_line
  Print the source line number of a node.
end

# Print members of ruby node.

define nd_head
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_alen
  printf "u2.argc: "
  p ($arg0).u2.argc
end

define nd_next
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_cond
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_body
  printf "u2.node: "
  rp ($arg0).u2.node
end

define nd_else
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_orig
  printf "u3.value: "
  rp ($arg0).u3.value
end


define nd_resq
  printf "u2.node: "
  rp ($arg0).u2.node
end

define nd_ensr
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_1st
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_2nd
  printf "u2.node: "
  rp ($arg0).u2.node
end


define nd_stts
  printf "u1.node: "
  rp ($arg0).u1.node
end


define nd_entry
  printf "u3.entry: "
  p ($arg0).u3.entry
end

define nd_vid
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_cflag
  printf "u2.id: "
  p ($arg0).u2.id
end

define nd_cval
  printf "u3.value: "
  rp ($arg0).u3.value
end


define nd_cnt
  printf "u3.cnt: "
  p ($arg0).u3.cnt
end

define nd_tbl
  printf "u1.tbl: "
  p ($arg0).u1.tbl
end


define nd_var
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_ibdy
  printf "u2.node: "
  rp ($arg0).u2.node
end

define nd_iter
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_value
  printf "u2.node: "
  rp ($arg0).u2.node
end

define nd_aid
  printf "u3.id: "
  p ($arg0).u3.id
end


define nd_lit
  printf "u1.value: "
  rp ($arg0).u1.value
end


define nd_frml
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_rest
  printf "u2.argc: "
  p ($arg0).u2.argc
end

define nd_opt
  printf "u1.node: "
  rp ($arg0).u1.node
end


define nd_recv
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_mid
  printf "u2.id: "
  p ($arg0).u2.id
end

define nd_args
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_noex
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_defn
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_old
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_new
  printf "u2.id: "
  p ($arg0).u2.id
end


define nd_cfnc
  printf "u1.cfunc: "
  p ($arg0).u1.cfunc
end

define nd_argc
  printf "u2.argc: "
  p ($arg0).u2.argc
end


define nd_cname
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_super
  printf "u3.node: "
  rp ($arg0).u3.node
end


define nd_modl
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_clss
  printf "u1.value: "
  rp ($arg0).u1.value
end


define nd_beg
  printf "u1.node: "
  rp ($arg0).u1.node
end

define nd_end
  printf "u2.node: "
  rp ($arg0).u2.node
end

define nd_state
  printf "u3.state: "
  p ($arg0).u3.state
end

define nd_rval
  printf "u2.value: "
  rp ($arg0).u2.value
end


define nd_nth
  printf "u2.argc: "
  p ($arg0).u2.argc
end


define nd_tag
  printf "u1.id: "
  p ($arg0).u1.id
end

define nd_tval
  printf "u2.value: "
  rp ($arg0).u2.value
end

define rb_p
  call rb_p($arg0)
end

define rb_id2name
  call rb_id2name($arg0)
end

define rb_classname
  call classname($arg0)
  rb_p $
  print *(struct RClass*)($arg0)
end

define rb_backtrace
  call rb_backtrace()
end

define iseq
  if ($arg0)->type == ISEQ_ELEMENT_NONE
    echo [none]\n
  end
  if ($arg0)->type == ISEQ_ELEMENT_LABEL
    print *(LABEL*)($arg0)
  end
  if ($arg0)->type == ISEQ_ELEMENT_INSN
    print *(INSN*)($arg0)
    if ((INSN*)($arg0))->insn_id != YARVINSN_jump
      set $i = 0
      set $operand_size = ((INSN*)($arg0))->operand_size
      set $operands = ((INSN*)($arg0))->operands
      while $i < $operand_size
	rp $operands[$i++]
      end
    end
  end
  if ($arg0)->type == ISEQ_ELEMENT_ADJUST
    print *(ADJUST*)($arg0)
  end
end

if dummy_gdb_enums.special_consts
end
