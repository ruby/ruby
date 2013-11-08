define hook-run
  set $color_type = 0
  set $color_highlite = 0
  set $color_end = 0
end

define ruby_gdb_init
  if !$color_type
    set $color_type = "\033[31m"
  end
  if !$color_highlite
    set $color_highlite = "\033[36m"
  end
  if !$color_end
    set $color_end = "\033[m"
  end
end

# set prompt \033[36m(gdb)\033[m\040

define rp
  ruby_gdb_init
  if ruby_dummy_gdb_enums.special_consts
  end
  if (VALUE)($arg0) & RUBY_FIXNUM_FLAG
    printf "FIXNUM: %ld\n", (long)($arg0) >> 1
  else
  if ((VALUE)($arg0) & ~(~(VALUE)0<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG
    set $id = (($arg0) >> RUBY_SPECIAL_SHIFT)
    printf "%sSYMBOL%s: ", $color_type, $color_end
    rp_id $id
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
    if ((VALUE)($arg0) & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG
      printf "%sFLONUM%s: %g\n", $color_type, $color_end, (double)rb_float_value($arg0)
    else
      echo immediate\n
    end
  else
  set $flags = ((struct RBasic*)($arg0))->flags
  if ($flags & RUBY_FL_PROMOTED)
    printf "[PROMOTED] "
  end
  if ($flags & RUBY_T_MASK) == RUBY_T_NONE
    printf "%sT_NONE%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_NIL
    printf "%sT_NIL%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_OBJECT
    printf "%sT_OBJECT%s: ", $color_type, $color_end
    print (struct RObject *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_CLASS
    printf "%sT_CLASS%s%s: ", $color_type, ($flags & RUBY_FL_SINGLETON) ? "*" : "", $color_end
    rp_class $arg0
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_ICLASS
    printf "%sT_ICLASS%s: ", $color_type, $color_end
    rp_class $arg0
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_MODULE
    printf "%sT_MODULE%s: ", $color_type, $color_end
    rp_class $arg0
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FLOAT
    printf "%sT_FLOAT%s: %.16g ", $color_type, $color_end, (((struct RFloat*)($arg0))->float_value)
    print (struct RFloat *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_STRING
    printf "%sT_STRING%s: ", $color_type, $color_end
    rp_string $arg0 $flags
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_REGEXP
    set $regsrc = ((struct RRegexp*)($arg0))->src
    set $rsflags = ((struct RBasic*)$regsrc)->flags
    printf "%sT_REGEXP%s: ", $color_type, $color_end
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
      printf "%sT_ARRAY%s: len=%ld ", $color_type, $color_end, $len
      printf "(embed) "
      if ($len == 0)
	printf "{(empty)} "
      else
	output/x *((VALUE*)((struct RArray*)($arg0))->as.ary) @ $len
	printf " "
      end
    else
      set $len = ((struct RArray*)($arg0))->as.heap.len
      printf "%sT_ARRAY%s: len=%ld ", $color_type, $color_end, $len
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
    printf "%sT_FIXNUM%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_HASH
    printf "%sT_HASH%s: ", $color_type, $color_end,
    if ((struct RHash *)($arg0))->ntbl
      printf "len=%ld ", ((struct RHash *)($arg0))->ntbl->num_entries
    end
    print (struct RHash *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_STRUCT
    printf "%sT_STRUCT%s: len=%ld ", $color_type, $color_end, \
      (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
       ($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) >> (RUBY_FL_USHIFT+1) : \
       ((struct RStruct *)($arg0))->as.heap.len)
    print (struct RStruct *)($arg0)
    x/xw (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
          ((struct RStruct *)($arg0))->as.ary : \
          ((struct RStruct *)($arg0))->as.heap.ptr)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_BIGNUM
    printf "%sT_BIGNUM%s: sign=%d len=%ld ", $color_type, $color_end, \
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
    printf "%sT_RATIONAL%s: ", $color_type, $color_end
    print (struct RRational *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_COMPLEX
    printf "%sT_COMPLEX%s: ", $color_type, $color_end
    print (struct RComplex *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FILE
    printf "%sT_FILE%s: ", $color_type, $color_end
    print (struct RFile *)($arg0)
    output *((struct RFile *)($arg0))->fptr
    printf "\n"
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_TRUE
    printf "%sT_TRUE%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_FALSE
    printf "%sT_FALSE%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_DATA
    if ((struct RTypedData *)($arg0))->typed_flag == 1
      printf "%sT_DATA%s(%s): ", $color_type, $color_end, ((struct RTypedData *)($arg0))->type->wrap_struct_name
      print (struct RTypedData *)($arg0)
    else
      printf "%sT_DATA%s: ", $color_type, $color_end
      print (struct RData *)($arg0)
    end
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_MATCH
    printf "%sT_MATCH%s: ", $color_type, $color_end
    print (struct RMatch *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_SYMBOL
    printf "%sT_SYMBOL%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_UNDEF
    printf "%sT_UNDEF%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_NODE
    printf "%sT_NODE%s(", $color_type, $color_end
    output (enum node_type)(($flags&RUBY_NODE_TYPEMASK)>>RUBY_NODE_TYPESHIFT)
    printf "): "
    print *(NODE *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_ZOMBIE
    printf "%sT_ZOMBIE%s: ", $color_type, $color_end
    print (struct RData *)($arg0)
  else
    printf "%sunknown%s: ", $color_type, $color_end
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

define rp_id
  set $id = (ID)$arg0
  if $id == '!' || $id == '+' || $id == '-' || $id == '*' || $id == '/' || $id == '%' || $id == '<' || $id == '>' || $id == '`'
    printf "(:%c)\n", $id
  else
  if $id == idDot2
    printf "(:..)\n"
  else
  if $id == idDot3
    printf "(:...)\n"
  else
  if $id == idUPlus
    printf "(:+@)\n"
  else
  if $id == idUMinus
    printf "(:-@)\n"
  else
  if $id == idPow
    printf "(:**)\n"
  else
  if $id == idCmp
    printf "(:<=>)\n"
  else
  if $id == idLTLT
    printf "(:<<)\n"
  else
  if $id == idLE
    printf "(:<=)\n"
  else
  if $id == idGE
    printf "(:>=)\n"
  else
  if $id == idEq
    printf "(:==)\n"
  else
  if $id == idEqq
    printf "(:===)\n"
  else
  if $id == idNeq
    printf "(:!=)\n"
  else
  if $id == idEqTilde
    printf "(:=~)\n"
  else
  if $id == idNeqTilde
    printf "(:!~)\n"
  else
  if $id == idAREF
    printf "(:[])\n"
  else
  if $id == idASET
    printf "(:[]=)\n"
  else
    if $id <= tLAST_OP_ID
      printf "O"
    else
      set $id_type = $id & RUBY_ID_SCOPE_MASK
      if $id_type == RUBY_ID_LOCAL
        printf "l"
      else
      if $id_type == RUBY_ID_INSTANCE
        printf "i"
      else
      if $id_type == RUBY_ID_GLOBAL
        printf "G"
      else
      if $id_type == RUBY_ID_ATTRSET
        printf "a"
      else
      if $id_type == RUBY_ID_CONST
        printf "C"
      else
      if $id_type == RUBY_ID_CLASS
        printf "c"
      else
        printf "j"
      end
      end
      end
      end
      end
      end
    end
    printf "(%ld): ", $id
    rb_numtable_entry global_symbols.id_str $id
    if $rb_numtable_rec
      rp_string $rb_numtable_rec
    else
      echo undef\n
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
document rp_id
  Print an ID.
end

define rp_string
  set $flags = ((struct RBasic*)($arg0))->flags
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
end
document rp_string
  Print the content of a String.
end

define rp_class
  printf "(struct RClass *) %p", (void*)$arg0
  if ((struct RClass *)($arg0))->ptr.origin != $arg0
    printf " -> %p", ((struct RClass *)($arg0))->ptr.origin
  end
  printf "\n"
  rb_classname $arg0
  print *(struct RClass *)($arg0)
  print *((struct RClass *)($arg0))->ptr
end
document rp_class
  Print the content of a Class/Module.
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
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_alen
  printf "%su2.argc%s: ", $color_highlite, $color_end
  p ($arg0).u2.argc
end

define nd_next
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_cond
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_body
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end

define nd_else
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_orig
  printf "%su3.value%s: ", $color_highlite, $color_end
  rp ($arg0).u3.value
end


define nd_resq
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end

define nd_ensr
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_1st
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_2nd
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end


define nd_stts
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end


define nd_entry
  printf "%su3.entry%s: ", $color_highlite, $color_end
  p ($arg0).u3.entry
end

define nd_vid
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_cflag
  printf "%su2.id%s: ", $color_highlite, $color_end
  p ($arg0).u2.id
end

define nd_cval
  printf "%su3.value%s: ", $color_highlite, $color_end
  rp ($arg0).u3.value
end


define nd_cnt
  printf "%su3.cnt%s: ", $color_highlite, $color_end
  p ($arg0).u3.cnt
end

define nd_tbl
  printf "%su1.tbl%s: ", $color_highlite, $color_end
  p ($arg0).u1.tbl
end


define nd_var
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_ibdy
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end

define nd_iter
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_value
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end

define nd_aid
  printf "%su3.id%s: ", $color_highlite, $color_end
  p ($arg0).u3.id
end


define nd_lit
  printf "%su1.value%s: ", $color_highlite, $color_end
  rp ($arg0).u1.value
end


define nd_frml
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_rest
  printf "%su2.argc%s: ", $color_highlite, $color_end
  p ($arg0).u2.argc
end

define nd_opt
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end


define nd_recv
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_mid
  printf "%su2.id%s: ", $color_highlite, $color_end
  p ($arg0).u2.id
end

define nd_args
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_noex
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_defn
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_old
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_new
  printf "%su2.id%s: ", $color_highlite, $color_end
  p ($arg0).u2.id
end


define nd_cfnc
  printf "%su1.cfunc%s: ", $color_highlite, $color_end
  p ($arg0).u1.cfunc
end

define nd_argc
  printf "%su2.argc%s: ", $color_highlite, $color_end
  p ($arg0).u2.argc
end


define nd_cname
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_super
  printf "%su3.node%s: ", $color_highlite, $color_end
  rp ($arg0).u3.node
end


define nd_modl
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_clss
  printf "%su1.value%s: ", $color_highlite, $color_end
  rp ($arg0).u1.value
end


define nd_beg
  printf "%su1.node%s: ", $color_highlite, $color_end
  rp ($arg0).u1.node
end

define nd_end
  printf "%su2.node%s: ", $color_highlite, $color_end
  rp ($arg0).u2.node
end

define nd_state
  printf "%su3.state%s: ", $color_highlite, $color_end
  p ($arg0).u3.state
end

define nd_rval
  printf "%su2.value%s: ", $color_highlite, $color_end
  rp ($arg0).u2.value
end


define nd_nth
  printf "%su2.argc%s: ", $color_highlite, $color_end
  p ($arg0).u2.argc
end


define nd_tag
  printf "%su1.id%s: ", $color_highlite, $color_end
  p ($arg0).u1.id
end

define nd_tval
  printf "%su2.value%s: ", $color_highlite, $color_end
  rp ($arg0).u2.value
end

define rb_p
  call rb_p($arg0)
end

define rb_numtable_entry
  set $rb_numtable_tbl = $arg0
  set $rb_numtable_id = (st_data_t)$arg1
  set $rb_numtable_key = 0
  set $rb_numtable_rec = 0
  if $rb_numtable_tbl->entries_packed
    set $rb_numtable_p = $rb_numtable_tbl->as.packed.bins
    while $rb_numtable_p && $rb_numtable_p < $rb_numtable_tbl->as.packed.bins+$rb_numtable_tbl->num_entries
      if $rb_numtable_p.k == $rb_numtable_id
	set $rb_numtable_key = $rb_numtable_p.k
	set $rb_numtable_rec = $rb_numtable_p.v
	set $rb_numtable_p = 0
      else
	set $rb_numtable_p = $rb_numtable_p + 1
      end
    end
  else
    set $rb_numtable_p = $rb_numtable_tbl->as.big.bins[$rb_numtable_id % $rb_numtable_tbl->num_bins]
    while $rb_numtable_p
      if $rb_numtable_p->key == $rb_numtable_id
	set $rb_numtable_key = $rb_numtable_p->key
	set $rb_numtable_rec = $rb_numtable_p->record
	set $rb_numtable_p = 0
      else
	set $rb_numtable_p = $rb_numtable_p->next
      end
    end
  end
end

define rb_id2name
  printf "%sID%s: ", $color_type, $color_end
  rp_id $arg0
end
document rb_id2name
  Print the name of id
end

define rb_method_entry
  set $rb_method_entry_klass = (struct RClass *)$arg0
  set $rb_method_entry_id = (ID)$arg1
  set $rb_method_entry_me = (rb_method_entry_t *)0
  while !$rb_method_entry_me && $rb_method_entry_klass
    rb_numtable_entry $rb_method_entry_klass->m_tbl $rb_method_entry_id
    set $rb_method_entry_me = (rb_method_entry_t *)$rb_numtable_rec
    if !$rb_method_entry_me
      set $rb_method_entry_klass = (struct RClass *)$rb_method_entry_klass->ptr->super
    end
  end
  if $rb_method_entry_me
    print *$rb_method_entry_klass
    print *$rb_method_entry_me
  else
    echo method not found\n
  end
end
document rb_method_entry
  Search method entry by class and id
end

define rb_classname
  # up to 128bit int
  set $rb_classname_permanent = "0123456789ABCDEF"
  set $rb_classname = classname($arg0, $rb_classname_permanent)
  if $rb_classname != RUBY_Qnil
    rp $rb_classname
  else
    echo anonymous class/module\n
  end
end

define rb_ancestors
  set $rb_ancestors_module = $arg0
  while $rb_ancestors_module
    rp_class $rb_ancestors_module
    set $rb_ancestors_module = ((struct RClass *)($rb_ancestors_module))->ptr.super
  end
end
document rb_ancestors
  Print ancestors.
end

define rb_backtrace
  call rb_backtrace()
end

define iseq
  if ruby_dummy_gdb_enums.special_consts
  end
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

define rb_ps
  rb_ps_vm ruby_current_vm
end
document rb_ps
Dump all threads and their callstacks
end

define rb_ps_vm
  print $ps_vm = (rb_vm_t*)$arg0
  set $ps_threads = (st_table*)$ps_vm->living_threads
  if $ps_threads->entries_packed
    set $ps_threads_i = 0
    while $ps_threads_i < $ps_threads->num_entries
      set $ps_threads_key = (st_data_t)$ps_threads->as.packed.entries[$ps_threads_i].key
      set $ps_threads_val = (st_data_t)$ps_threads->as.packed.entries[$ps_threads_i].val
      rb_ps_thread $ps_threads_key $ps_threads_val
      set $ps_threads_i = $ps_threads_i + 1
    end
  else
    set $ps_threads_ptr = (st_table_entry*)$ps_threads->head
    while $ps_threads_ptr
      set $ps_threads_key = (st_data_t)$ps_threads_ptr->key
      set $ps_threads_val = (st_data_t)$ps_threads_ptr->record
      rb_ps_thread $ps_threads_key $ps_threads_val
      set $ps_threads_ptr = (st_table_entry*)$ps_threads_ptr->fore
    end
  end
end
document rb_ps_vm
Dump all threads in a (rb_vm_t*) and their callstacks
end

define rb_ps_thread
  set $ps_thread = (struct RTypedData*)$arg0
  set $ps_thread_id = $arg1
  print $ps_thread_th = (rb_thread_t*)$ps_thread->data
end

# Details: https://bugs.ruby-lang.org/projects/ruby-trunk/wiki/MachineInstructionsTraceWithGDB
define trace_machine_instructions
  set logging on
  set height 0
  set width 0
  display/i $pc
  while !$exit_code
    info line *$pc
    si
  end
end

define SDR
  call rb_vmdebug_stack_dump_raw_current()
end

