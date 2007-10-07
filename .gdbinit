define rp
  if (VALUE)$arg0 & 1
    printf "FIXNUM: %d\n", $arg0 >> 1
  else
  if ((VALUE)$arg0 & ~(~(VALUE)0<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG
    printf "SYMBOL(%d)\n", $arg0 >> 8
  else
  if $arg0 == 0
    echo false\n
  else
  if $arg0 == 2
    echo true\n
  else
  if $arg0 == 4
    echo nil\n
  else
  if $arg0 == 6
    echo undef\n
  else
  if (VALUE)$arg0 & 0x03
    echo immediate\n
  else
  set $flags = ((struct RBasic*)$arg0)->flags
  if ($flags & 0x1f) == 0x00
    printf "T_NONE: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x01
    printf "T_NIL: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x02
    printf "T_OBJECT: "
    print (struct RObject *)$arg0
  else
  if ($flags & 0x1f) == 0x03
    printf "T_CLASS: "
    print (struct RClass *)$arg0
  else
  if ($flags & 0x1f) == 0x04
    printf "T_ICLASS: "
    print (struct RClass *)$arg0
  else
  if ($flags & 0x1f) == 0x05
    printf "T_MODULE: "
    print (struct RClass *)$arg0
  else
  if ($flags & 0x1f) == 0x06
    printf "T_FLOAT: %.16g ", (((struct RFloat*)$arg0)->value)
    print (struct RFloat *)$arg0
  else
  if ($flags & 0x1f) == 0x07
    printf "T_STRING: "
    set print address off
    output (char *)(($flags & RUBY_FL_USER1) ? \
	    ((struct RString*)$arg0)->as.heap.ptr : \
	    ((struct RString*)$arg0)->as.ary)
    set print address on
    printf " "
    print (struct RString *)$arg0
  else
  if ($flags & 0x1f) == 0x08
    printf "T_REGEXP: "
    set print address off
    output ((struct RRegexp*)$arg0)->str
    set print address on
    printf " "
    print (struct RRegexp *)$arg0
  else
  if ($flags & 0x1f) == 0x09
    printf "T_ARRAY: len=%d ", ((struct RArray*)$arg0)->len
    print (struct RArray *)$arg0
    x/xw ((struct RArray*)$arg0)->ptr
  else
  if ($flags & 0x1f) == 0x0a
    printf "T_FIXNUM: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x0b
    printf "T_HASH: ",
    if ((struct RHash *)$arg0)->ntbl
      printf "len=%d ", ((struct RHash *)$arg0)->ntbl->num_entries
    end
    print (struct RHash *)$arg0
  else
  if ($flags & 0x1f) == 0x0c
    printf "T_STRUCT: len=%d ", \
      (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
       ($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) >> (RUBY_FL_USHIFT+1) : \
       ((struct RStruct *)$arg0)->as.heap.len)
    print (struct RStruct *)$arg0
    x/xw (($flags & (RUBY_FL_USER1|RUBY_FL_USER2)) ? \
          ((struct RStruct *)$arg0)->as.ary : \
          ((struct RStruct *)$arg0)->as.heap.len)
  else
  if ($flags & 0x1f) == 0x0d
    printf "T_BIGNUM: sign=%d len=%d ", \
      (($flags & RUBY_FL_USER1) != 0), \
      (($flags & RUBY_FL_USER2) ? \
       ($flags & (RUBY_FL_USER5|RUBY_FL_USER4|RUBY_FL_USER3)) >> (RUBY_FL_USHIFT+3) : \
       ((struct RBignum*)$arg0)->as.heap.len)
    if $flags & RUBY_FL_USER2
      printf "(embed) "
    end
    print (struct RBignum *)$arg0
    x/xw (($flags & RUBY_FL_USER2) ? \
          ((struct RBignum*)$arg0)->as.ary : \
          ((struct RBignum*)$arg0)->as.heap.digits)
  else
  if ($flags & 0x1f) == 0x0e
    printf "T_FILE: "
    print (struct RFile *)$arg0
    output *((struct RFile *)$arg0)->fptr
    printf "\n"
  else
  if ($flags & 0x1f) == 0x10
    printf "T_TRUE: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x11
    printf "T_FALSE: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x12
    printf "T_DATA: "
    print (struct RData *)$arg0
  else
  if ($flags & 0x1f) == 0x13
    printf "T_MATCH: "
    print (struct RMatch *)$arg0
  else
  if ($flags & 0x1f) == 0x14
    printf "T_SYMBOL: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x1a
    printf "T_VALUES: "
    print (struct RValues *)$arg0
  else
  if ($flags & 0x1f) == 0x1b
    printf "T_BLOCK: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x1c
    printf "T_UNDEF: "
    print (struct RBasic *)$arg0
  else
  if ($flags & 0x1f) == 0x1f
    printf "T_NODE("
    output (enum node_type)(($flags&RUBY_NODE_TYPEMASK)>>RUBY_NODE_TYPESHIFT)
    printf "): "
    print *(NODE *)$arg0
  else
    printf "unknown: "
    print (struct RBasic *)$arg0
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
  print (enum node_type)((((NODE*)$arg0)->flags&RUBY_NODE_TYPEMASK)>>RUBY_NODE_TYPESHIFT)
end
document nd_type
  Print a Ruby' node type.
end

define nd_file
  print ((NODE*)$arg0)->nd_file
end
document nd_file
  Print the source file name of a node.
end

define nd_line
  print ((unsigned int)((((NODE*)$arg0)->flags>>RUBY_NODE_LSHIFT)&RUBY_NODE_LMASK))
end
document nd_line
  Print the source line number of a node.
end

# Print members of ruby node.

define nd_head
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_alen
  printf "u2.argc: "
  p $arg0.u2.argc
end

define nd_next
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_cond
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_body
  printf "u2.node: "
  rp $arg0.u2.node
end

define nd_else
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_orig
  printf "u3.value: "
  rp $arg0.u3.value
end


define nd_resq
  printf "u2.node: "
  rp $arg0.u2.node
end

define nd_ensr
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_1st
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_2nd
  printf "u2.node: "
  rp $arg0.u2.node
end


define nd_stts
  printf "u1.node: "
  rp $arg0.u1.node
end


define nd_entry
  printf "u3.entry: "
  p $arg0.u3.entry
end

define nd_vid
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_cflag
  printf "u2.id: "
  p $arg0.u2.id
end

define nd_cval
  printf "u3.value: "
  rp $arg0.u3.value
end


define nd_cnt
  printf "u3.cnt: "
  p $arg0.u3.cnt
end

define nd_tbl
  printf "u1.tbl: "
  p $arg0.u1.tbl
end


define nd_var
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_ibdy
  printf "u2.node: "
  rp $arg0.u2.node
end

define nd_iter
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_value
  printf "u2.node: "
  rp $arg0.u2.node
end

define nd_aid
  printf "u3.id: "
  p $arg0.u3.id
end


define nd_lit
  printf "u1.value: "
  rp $arg0.u1.value
end


define nd_frml
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_rest
  printf "u2.argc: "
  p $arg0.u2.argc
end

define nd_opt
  printf "u1.node: "
  rp $arg0.u1.node
end


define nd_recv
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_mid
  printf "u2.id: "
  p $arg0.u2.id
end

define nd_args
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_noex
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_defn
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_old
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_new
  printf "u2.id: "
  p $arg0.u2.id
end


define nd_cfnc
  printf "u1.cfunc: "
  p $arg0.u1.cfunc
end

define nd_argc
  printf "u2.argc: "
  p $arg0.u2.argc
end


define nd_cname
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_super
  printf "u3.node: "
  rp $arg0.u3.node
end


define nd_modl
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_clss
  printf "u1.value: "
  rp $arg0.u1.value
end


define nd_beg
  printf "u1.node: "
  rp $arg0.u1.node
end

define nd_end
  printf "u2.node: "
  rp $arg0.u2.node
end

define nd_state
  printf "u3.state: "
  p $arg0.u3.state
end

define nd_rval
  printf "u2.value: "
  rp $arg0.u2.value
end


define nd_nth
  printf "u2.argc: "
  p $arg0.u2.argc
end


define nd_tag
  printf "u1.id: "
  p $arg0.u1.id
end

define nd_tval
  printf "u2.value: "
  rp $arg0.u2.value
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
  print *(struct RClass*)$arg0
end

define rb_backtrace
  call rb_backtrace()
end
