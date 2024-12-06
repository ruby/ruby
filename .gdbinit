define ruby_gdb_init
  init-if-undefined $color_type = "\033[31m"
  init-if-undefined $color_highlite = "\033[36m"
  init-if-undefined $color_end = "\033[m"
end

# set prompt \033[36m(gdb)\033[m\040

define rp
  ruby_gdb_init
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
  if ($flags & RUBY_FL_PROMOTED) == RUBY_FL_PROMOTED
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
    print ((struct RObject *)($arg0))->basic
    if ($flags & ROBJECT_EMBED)
      print/x *((VALUE*)((struct RObject*)($arg0))->as.ary) @ (rb_shape_get_shape($arg0)->capacity)
    else
      print (((struct RObject *)($arg0))->as.heap)
      if (((struct RObject*)($arg0))->as.heap.numiv) > 0
        print/x *(((struct RObject*)($arg0))->as.heap.ivptr) @ (((struct RObject*)($arg0))->as.heap.numiv)
      end
    end
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
    set $len = ((struct RString*)($arg0))->len
    set print address off
    output *(char *)(($rsflags & RUBY_FL_USER1) ? \
            ((struct RString*)$regsrc)->as.heap.ptr : \
            ((struct RString*)$regsrc)->as.embed.ary) @ $len
    set print address on
    printf " len:%ld ", $len
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
        print/x *((VALUE*)((struct RArray*)($arg0))->as.ary) @ $len
        printf " "
      end
    else
      set $len = ((struct RArray*)($arg0))->as.heap.len
      printf "%sT_ARRAY%s: len=%ld ", $color_type, $color_end, $len
      if ($flags & RUBY_FL_USER2)
        printf "(shared) shared="
        output/x ((struct RArray*)($arg0))->as.heap.aux.shared_root
        printf " "
      else
        printf "(ownership) capa=%ld ", ((struct RArray*)($arg0))->as.heap.aux.capa
      end
      if ($len == 0)
        printf "{(empty)} "
      else
        print/x *((VALUE*)((struct RArray*)($arg0))->as.heap.ptr) @ $len
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
    if (((struct RHash *)($arg0))->basic.flags & RHASH_ST_TABLE_FLAG)
      printf "st len=%ld ", ((struct RHash *)($arg0))->as.st->num_entries
    else
      printf "li len=%ld bound=%ld ", \
        ((((struct RHash *)($arg0))->basic.flags & RHASH_AR_TABLE_SIZE_MASK) >> RHASH_AR_TABLE_SIZE_SHIFT), \
        ((((struct RHash *)($arg0))->basic.flags & RHASH_AR_TABLE_BOUND_MASK) >> RHASH_AR_TABLE_BOUND_SHIFT)
    end
    print (struct RHash *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_STRUCT
    set $len = (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
       ($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) >> (RUBY_FL_USHIFT+1) : \
       ((struct RStruct *)($arg0))->as.heap.len)
    printf "%sT_STRUCT%s: len=%ld ", $color_type, $color_end, $len
    print (struct RStruct *)($arg0)
    output/x *(($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
              ((struct RStruct *)($arg0))->as.ary : \
              ((struct RStruct *)($arg0))->as.heap.ptr) @ $len
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_BIGNUM
    rp_bignum $arg0
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
    print (struct RSymbol *)($arg0)
    set $id_type = ((struct RSymbol *)($arg0))->id & RUBY_ID_SCOPE_MASK
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
    set $id_fstr = ((struct RSymbol *)($arg0))->fstr
    rp_string $id_fstr
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_UNDEF
    printf "%sT_UNDEF%s: ", $color_type, $color_end
    print (struct RBasic *)($arg0)
  else
  if ($flags & RUBY_T_MASK) == RUBY_T_IMEMO
    printf "%sT_IMEMO%s(", $color_type, $color_end
    output (enum imemo_type)(($flags>>RUBY_FL_USHIFT)&RUBY_IMEMO_MASK)
    printf "): "
    rp_imemo $arg0
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
  if ($flags & RUBY_T_MASK) == RUBY_T_MOVED
    printf "%sT_MOVED%s: ", $color_type, $color_end
    print *(struct RMoved *)$arg0
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
  if $id == idGTGT
    printf "(:>>)\n"
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
  if $id == idCOLON2
    printf "(:'::')\n"
  else
  if $id == idANDOP
    printf "(:&&)\n"
  else
  if $id == idOROP
    printf "(:||)\n"
  else
  if $id == idANDDOT
    printf "(:&.)\n"
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
    print_id $id
    echo \n
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
document rp_id
  Print an ID.
end

define output_string
  set $flags = ((struct RBasic*)($arg0))->flags
  set $len = ((struct RString*)($arg0))->len
  if $len > 0
    output *(char *)(($flags & RUBY_FL_USER1) ? \
            ((struct RString*)($arg0))->as.heap.ptr : \
            ((struct RString*)($arg0))->as.embed.ary) @ $len
  else
    output ""
  end
end

define print_string
  set $flags = ((struct RBasic*)($arg0))->flags
  set $len = ((struct RString*)($arg0))->len
  if $len > 0
    printf "%s", *(char *)(($flags & RUBY_FL_USER1) ? \
            ((struct RString*)($arg0))->as.heap.ptr : \
            ((struct RString*)($arg0))->as.embed.ary) @ $len
  end
end

define rp_string
  output_string $arg0
  printf " bytesize:%ld ", $len
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

define rp_bignum
  set $flags = ((struct RBignum*)($arg0))->basic.flags
  set $len = (($flags & RUBY_FL_USER2) ? \
       ($flags & (RUBY_FL_USER5|RUBY_FL_USER4|RUBY_FL_USER3)) >> (RUBY_FL_USHIFT+3) : \
       ((struct RBignum*)($arg0))->as.heap.len)
  printf "%sT_BIGNUM%s: sign=%d len=%ld ", $color_type, $color_end, \
         (($flags & RUBY_FL_USER1) != 0), $len
  if $flags & RUBY_FL_USER2
    printf "(embed) "
  end
  print (struct RBignum *)($arg0)
  set $ptr = (($flags & RUBY_FL_USER2) ? \
              ((struct RBignum*)($arg0))->as.ary : \
              ((struct RBignum*)($arg0))->as.heap.digits)
  set $len = $len-1
  printf "0x%x", $ptr[$len]
  while $len > 0
    set $len = $len-1
    set $val = $ptr[$len]
    set $w = sizeof($ptr[0])
    printf "_"
    if $w > 8
      printf "%.32x", $val
    else
    if $w > 4
      printf "%.16x", $val
    else
    if $w > 2
      printf "%.8x", $val
    else
    if $w > 1
      printf "%.4x", $val
    else
      printf "%.2x", $val
    end
    end
    end
    end
  end
  printf "\n"
end
document rp_bignum
  Print the content of a Bignum.
end

define rp_class
  printf "(struct RClass *) %p", (void*)$arg0
  if RCLASS_ORIGIN((struct RClass *)($arg0)) != $arg0
    printf " -> %p", RCLASS_ORIGIN((struct RClass *)($arg0))
  end
  printf "\n"
  rb_classname $arg0
  print/x *(struct RClass *)($arg0)
  print *RCLASS_EXT((struct RClass *)($arg0))
end
document rp_class
  Print the content of a Class/Module.
end

define rp_imemo
  set $flags = (enum imemo_type)((((struct RBasic *)($arg0))->flags >> RUBY_FL_USHIFT) & RUBY_IMEMO_MASK)
  if $flags == imemo_cref
    printf "(rb_cref_t *) %p\n", (void*)$arg0
    print *(rb_cref_t *)$arg0
  else
  if $flags == imemo_svar
    printf "(struct vm_svar *) %p\n", (void*)$arg0
    print *(struct vm_svar *)$arg0
  else
  if $flags == imemo_throw_data
    printf "(struct vm_throw_data *) %p\n", (void*)$arg0
    print *(struct vm_throw_data *)$arg0
  else
  if $flags == imemo_ifunc
    printf "(struct vm_ifunc *) %p\n", (void*)$arg0
    print *(struct vm_ifunc *)$arg0
  else
  if $flags == imemo_memo
    printf "(struct MEMO *) %p\n", (void*)$arg0
    print *(struct MEMO *)$arg0
  else
  if $flags == imemo_ment
    printf "(rb_method_entry_t *) %p\n", (void*)$arg0
    print *(rb_method_entry_t *)$arg0
  else
  if $flags == imemo_iseq
    printf "(rb_iseq_t *) %p\n", (void*)$arg0
    print *(rb_iseq_t *)$arg0
  else
    printf "(struct RIMemo *) %p\n", (void*)$arg0
    print *(struct RIMemo *)$arg0
  end
  end
  end
  end
  end
  end
  end
end
document rp_imemo
  Print the content of a memo
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

define nd_tree
  set $buf = (struct RString *)rb_str_buf_new(0)
  call dump_node((VALUE)($buf), rb_str_tmp_new(0), 0, ($arg0))
  printf "%s\n", $buf->as.heap.ptr
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
    set $rb_numtable_p = $rb_numtable_tbl->as.big.bins[st_numhash($rb_numtable_id) % $rb_numtable_tbl->num_bins]
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
  ruby_gdb_init
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
    rb_numtable_entry $rb_method_entry_klass->m_tbl_wrapper->tbl $rb_method_entry_id
    set $rb_method_entry_me = (rb_method_entry_t *)$rb_numtable_rec
    if !$rb_method_entry_me
      set $rb_method_entry_klass = (struct RClass *)RCLASS_SUPER($rb_method_entry_klass)
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
  set $rb_classname = rb_mod_name($arg0)
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
    set $rb_ancestors_module = RCLASS_SUPER($rb_ancestors_module)
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
  rb_ps_vm ruby_current_vm_ptr
end
document rb_ps
Dump all threads and their callstacks
end

define rb_ps_vm
  print $ps_vm = (rb_vm_t*)$arg0
  set $ps_thread_ln      = $ps_vm->ractor.main_ractor.threads.set.n.next
  set $ps_thread_ln_last = $ps_vm->ractor.main_ractor.threads.set.n.prev
  while 1
    set $ps_thread_th = (rb_thread_t *)$ps_thread_ln
    set $ps_thread = (VALUE)($ps_thread_th->self)
    rb_ps_thread $ps_thread
    if $ps_thread_ln == $ps_thread_ln_last
      loop_break
    end
    set $ps_thread_ln = $ps_thread_ln->next
  end
end
document rb_ps_vm
Dump all threads in a (rb_vm_t*) and their callstacks
end

define print_lineno
  set $cfp = $arg0
  set $iseq = $cfp->iseq
  set $pos = $cfp->pc - $iseq->body->iseq_encoded
  if $pos != 0
    set $pos = $pos - 1
  end

  set $index = 0
  set $size = $iseq->body->insns_info.size
  set $table = $iseq->body->insns_info.body
  set $positions = $iseq->body->insns_info.positions
  #printf "size: %d\n", $size
  if $size == 0
  else
  if $size == 1
    printf "%d", $table[0].line_no
  else
    if $positions
      # get_insn_info_linear_search
      set $index = 1
      while $index < $size
        #printf "table[%d]: position: %d, line: %d, pos: %d\n", $i, $positions[$i], $table[$i].line_no, $pos
        if $positions[$index] > $pos
          loop_break
        end
        set $index = $index + 1
        if $positions[$index] == $pos
          loop_break
        end
      end
    else
      # get_insn_info_succinct_bitvector
      set $sd = $iseq->body->insns_info.succ_index_table
      set $immediate_table_size = sizeof($sd->imm_part) / sizeof(uint64_t) * 9
      if $pos < $immediate_table_size
        set $i = $pos / 9
        set $j = $pos % 9
        set $index = ((int)($sd->imm_part[$i] >> ($j * 7))) & 0x7f
      else
        set $block_index = ($pos - $immediate_table_size) / 512
        set $block = &$sd->succ_part[$block_index]
        set $block_bit_index = ($pos - $immediate_table_size) % 512
        set $small_block_index = $block_bit_index / 64
        set $small_block_popcount = $small_block_index == 0 ? 0 : (((int)($block->small_block_ranks >> (($small_block_index - 1) * 9))) & 0x1ff)
        set $x = $block->bits[$small_block_index] << (63 - $block_bit_index % 64)
        set $x = ($x & 0x5555555555555555) + ($x >> 1 & 0x5555555555555555)
        set $x = ($x & 0x3333333333333333) + ($x >> 2 & 0x3333333333333333)
        set $x = ($x & 0x0707070707070707) + ($x >> 4 & 0x0707070707070707)
        set $x = ($x & 0x001f001f001f001f) + ($x >> 8 & 0x001f001f001f001f)
        set $x = ($x & 0x0000003f0000003f) + ($x >>16 & 0x0000003f0000003f)
        set $popcnt = ($x & 0x7f) + ($x >>32 & 0x7f)
        set $index = $block->rank + $small_block_popcount + $popcnt
      end
    end
    printf "%d", $table[$index-1].line_no
  end
  end
end

define check_method_entry
  set $imemo = (struct RBasic *)$arg0
  if $imemo != RUBY_Qfalse
    set $type = ($imemo->flags >> 12) & 0x07
    if $type == imemo_ment
      set $me = (rb_callable_method_entry_t *)$imemo
    else
    if $type == imemo_svar
      set $imemo = ((struct vm_svar *)$imemo)->cref_or_me
      check_method_entry $imemo
    end
    end
  end
end

define print_id
  set $id = $arg0
  # rb_id_to_serial
  if $id > tLAST_OP_ID
    set $serial = (rb_id_serial_t)($id >> RUBY_ID_SCOPE_SHIFT)
  else
    set $serial = (rb_id_serial_t)$id
  end
  if $serial && $serial <= ruby_global_symbols.last_id
    set $idx = $serial / ID_ENTRY_UNIT
    set $ids = (struct RArray *)ruby_global_symbols.ids
    set $flags = $ids->basic.flags
    if ($flags & RUBY_FL_USER1)
      set $idsptr = $ids->as.ary
      set $idslen = (($flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
    else
      set $idsptr = $ids->as.heap.ptr
      set $idslen = $ids->as.heap.len
    end
    if $idx < $idslen
      set $t = 0
      set $ary = (struct RArray *)$idsptr[$idx]
      if $ary != RUBY_Qnil
        set $flags = $ary->basic.flags
        if ($flags & RUBY_FL_USER1)
          set $aryptr = $ary->as.ary
          set $arylen = (($flags & (RUBY_FL_USER3|RUBY_FL_USER4)) >> (RUBY_FL_USHIFT+3))
        else
          set $aryptr = $ary->as.heap.ptr
          set $arylen = $ary->as.heap.len
        end
        set $result = $aryptr[($serial % ID_ENTRY_UNIT) * ID_ENTRY_SIZE + $t]
        if $result != RUBY_Qnil
          print_string $result
        else
          echo undef
        end
      end
    end
  end
end

define print_pathobj
  set $flags = ((struct RBasic*)($arg0))->flags
  if ($flags & RUBY_T_MASK) == RUBY_T_STRING
    print_string $arg0
  end
  if ($flags & RUBY_T_MASK) == RUBY_T_ARRAY
    if $flags & RUBY_FL_USER1
      set $str = ((struct RArray*)($arg0))->as.ary[0]
    else
      set $str = ((struct RArray*)($arg0))->as.heap.ptr[0]
    end
    print_string $str
  end
end

define rb_ps_thread
  set $ps_thread = (struct RTypedData*)$arg0
  set $ps_thread_th = (rb_thread_t*)$ps_thread->data
  printf "* #<Thread:%p rb_thread_t:%p native_thread:%p>\n", \
    $ps_thread, $ps_thread_th, $ps_thread_th->nt
  set $cfp = $ps_thread_th->ec->cfp
  set $cfpend = (rb_control_frame_t *)($ps_thread_th->ec->vm_stack + $ps_thread_th->ec->vm_stack_size)-1
  while $cfp < $cfpend
    if $cfp->iseq
      if !((VALUE)$cfp->iseq & RUBY_IMMEDIATE_MASK) && (((imemo_ifunc << RUBY_FL_USHIFT) | RUBY_T_IMEMO)==$cfp->iseq->flags & ((RUBY_IMEMO_MASK << RUBY_FL_USHIFT) | RUBY_T_MASK))
        printf "%d:ifunc ", $cfpend-$cfp
        set print symbol-filename on
        output/a $cfp->iseq.body
        set print symbol-filename off
        printf "\n"
      else
      if $cfp->pc
        set $location = $cfp->iseq->body->location
        printf "%d:", $cfpend-$cfp
        print_pathobj $location.pathobj
        printf ":"
        print_lineno $cfp
        printf ":in `"
        print_string $location.label
        printf "'\n"
      else
        printf "%d: ???.rb:???:in `???'\n", $cfpend-$cfp
      end
      end
    else
      # if VM_FRAME_TYPE($cfp->flag) == VM_FRAME_MAGIC_CFUNC
      set $ep = $cfp->ep
      if ($ep[0] & 0xffff0001) == 0x55550001
        #define VM_ENV_FLAG_LOCAL 0x02
        #define VM_ENV_PREV_EP(ep)   GC_GUARDED_PTR_REF(ep[VM_ENV_DATA_INDEX_SPECVAL])
        set $me = 0
        set $env_specval = $ep[-1]
        set $env_me_cref = $ep[-2]
        while ($env_specval & 0x02) != 0
          check_method_entry $env_me_cref
          if $me != 0
            loop_break
          end
          set $ep = $ep[0]
          set $env_specval = $ep[-1]
          set $env_me_cref = $ep[-2]
        end
        if $me == 0
          check_method_entry $env_me_cref
        end
        printf "%d:", $cfpend-$cfp
        set print symbol-filename on
        output/a $me->def->body.cfunc.func
        set print symbol-filename off
        set $mid = $me->def->original_id
        printf ":in `"
        print_id $mid
        printf "'\n"
      else
        printf "%d:unknown_frame:???:in `???'\n", $cfpend-$cfp
      end
    end
    set $cfp = $cfp + 1
  end
end

define rb_count_objects
  set $objspace = ruby_current_vm_ptr->objspace
  set $counts_00 = 0
  set $counts_01 = 0
  set $counts_02 = 0
  set $counts_03 = 0
  set $counts_04 = 0
  set $counts_05 = 0
  set $counts_06 = 0
  set $counts_07 = 0
  set $counts_08 = 0
  set $counts_09 = 0
  set $counts_0a = 0
  set $counts_0b = 0
  set $counts_0c = 0
  set $counts_0d = 0
  set $counts_0e = 0
  set $counts_0f = 0
  set $counts_10 = 0
  set $counts_11 = 0
  set $counts_12 = 0
  set $counts_13 = 0
  set $counts_14 = 0
  set $counts_15 = 0
  set $counts_16 = 0
  set $counts_17 = 0
  set $counts_18 = 0
  set $counts_19 = 0
  set $counts_1a = 0
  set $counts_1b = 0
  set $counts_1c = 0
  set $counts_1d = 0
  set $counts_1e = 0
  set $counts_1f = 0
  set $total = 0
  set $i = 0
  while $i < $objspace->heap_pages.allocated_pages
    printf "\rcounting... %d/%d", $i, $objspace->heap_pages.allocated_pages
    set $page = $objspace->heap_pages.sorted[$i]
    set $p = $page->start
    set $pend = $p + $page->total_slots
    while $p < $pend
      set $flags = $p->as.basic.flags & 0x1f
      eval "set $counts_%02x = $counts_%02x + 1", $flags, $flags
      set $p = $p + 1
    end
    set $total = $total + $page->total_slots
    set $i = $i + 1
  end
  printf "\rTOTAL: %d, FREE: %d\n", $total, $counts_00
  printf "T_OBJECT: %d\n", $counts_01
  printf "T_CLASS: %d\n", $counts_02
  printf "T_MODULE: %d\n", $counts_03
  printf "T_FLOAT: %d\n", $counts_04
  printf "T_STRING: %d\n", $counts_05
  printf "T_REGEXP: %d\n", $counts_06
  printf "T_ARRAY: %d\n", $counts_07
  printf "T_HASH: %d\n", $counts_08
  printf "T_STRUCT: %d\n", $counts_09
  printf "T_BIGNUM: %d\n", $counts_0a
  printf "T_FILE: %d\n", $counts_0b
  printf "T_DATA: %d\n", $counts_0c
  printf "T_MATCH: %d\n", $counts_0d
  printf "T_COMPLEX: %d\n", $counts_0e
  printf "T_RATIONAL: %d\n", $counts_0f
  #printf "UNKNOWN_10: %d\n", $counts_10
  printf "T_NIL: %d\n", $counts_11
  printf "T_TRUE: %d\n", $counts_12
  printf "T_FALSE: %d\n", $counts_13
  printf "T_SYMBOL: %d\n", $counts_14
  printf "T_FIXNUM: %d\n", $counts_15
  printf "T_UNDEF: %d\n", $counts_16
  #printf "UNKNOWN_17: %d\n", $counts_17
  #printf "UNKNOWN_18: %d\n", $counts_18
  #printf "UNKNOWN_19: %d\n", $counts_19
  printf "T_IMEMO: %d\n", $counts_1a
  printf "T_NODE: %d\n", $counts_1b
  printf "T_ICLASS: %d\n", $counts_1c
  printf "T_ZOMBIE: %d\n", $counts_1d
  #printf "UNKNOWN_1E: %d\n", $counts_1e
  printf "T_MASK: %d\n", $counts_1f
end
document rb_count_objects
  Counts all objects grouped by type.
end

# Details: https://github.com/ruby/ruby/wiki/Machine-Instructions-Trace-with-GDB
define trace_machine_instructions
  set logging enabled
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

define rbi
  if ((LINK_ELEMENT*)$arg0)->type == ISEQ_ELEMENT_LABEL
    p *(LABEL*)$arg0
  else
  if ((LINK_ELEMENT*)$arg0)->type == ISEQ_ELEMENT_INSN
    p *(INSN*)$arg0
  else
  if ((LINK_ELEMENT*)$arg0)->type == ISEQ_ELEMENT_ADJUST
    p *(ADJUST*)$arg0
  else
    print *$arg0
  end
  end
  end
end

define dump_node
  set $str = rb_parser_dump_tree($arg0, 0)
  set $flags = ((struct RBasic*)($str))->flags
  printf "%s", (char *)(($flags & RUBY_FL_USER1) ? \
                        ((struct RString*)$str)->as.heap.ptr : \
                        ((struct RString*)$str)->as.embed.ary)
end

define print_flags
  printf "RUBY_FL_WB_PROTECTED: %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_WB_PROTECTED ? "1" : "0"
  printf "RUBY_FL_PROMOTED0   : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_PROMOTED0 ? "1" : "0"
  printf "RUBY_FL_PROMOTED1   : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_PROMOTED1 ? "1" : "0"
  printf "RUBY_FL_FINALIZE    : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_FINALIZE ? "1" : "0"
  printf "RUBY_FL_SHAREABLE   : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_SHAREABLE ? "1" : "0"
  printf "RUBY_FL_EXIVAR      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_EXIVAR ? "1" : "0"
  printf "RUBY_FL_FREEZE      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_FREEZE ? "1" : "0"

  printf "RUBY_FL_USER0       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER0 ? "1" : "0"
  printf "RUBY_FL_USER1       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER1 ? "1" : "0"
  printf "RUBY_FL_USER2       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER2 ? "1" : "0"
  printf "RUBY_FL_USER3       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER3 ? "1" : "0"
  printf "RUBY_FL_USER4       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER4 ? "1" : "0"
  printf "RUBY_FL_USER5       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER5 ? "1" : "0"
  printf "RUBY_FL_USER6       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER6 ? "1" : "0"
  printf "RUBY_FL_USER7       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER7 ? "1" : "0"
  printf "RUBY_FL_USER8       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER8 ? "1" : "0"
  printf "RUBY_FL_USER9       : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER9 ? "1" : "0"
  printf "RUBY_FL_USER10      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER10 ? "1" : "0"
  printf "RUBY_FL_USER11      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER11 ? "1" : "0"
  printf "RUBY_FL_USER12      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER12 ? "1" : "0"
  printf "RUBY_FL_USER13      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER13 ? "1" : "0"
  printf "RUBY_FL_USER14      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER14 ? "1" : "0"
  printf "RUBY_FL_USER15      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER15 ? "1" : "0"
  printf "RUBY_FL_USER16      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER16 ? "1" : "0"
  printf "RUBY_FL_USER17      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER17 ? "1" : "0"
  printf "RUBY_FL_USER18      : %s\n", ((struct RBasic*)($arg0))->flags & RUBY_FL_USER18 ? "1" : "0"
end

source -s misc/gdb.py

# Moved from beginning, since it fails on older gdbs
set startup-with-shell off
