define rp
  if ($arg0 & 0x1)
    echo T_FIXNUM\n
    print (long)$arg0 >> 1
  else
  if ($arg0 == 0)
    echo T_FALSE\n
  else
  if ($arg0 == 2)
    echo T_TRUE\n
  else
  if ($arg0 == 4)
    echo T_NIL\n
  else
  if ($arg0 == 6)
    echo T_UNDEF\n
  else
  if (($arg0 & 0xff) == 0x0e)
    echo T_SYMBOL\n
    output $arg0 >> 8
    echo \n
    call rb_id2name($arg0 >> 8)
  else
    set $rbasic = (struct RBasic*)$arg0
  #  output  $rbasic
  #  echo \ =\ 
  #  output *$rbasic
  #  echo \n
    set $flags = (*$rbasic).flags & 0x3f
    if ($flags == 0x01)
      echo T_NIL\n
      echo impossible\n
    else
    if ($flags == 0x02)
      echo T_OBJECT\n
      print *(struct RObject*)$rbasic
    else
    if ($flags == 0x03)
      echo T_CLASS\n
      print *(struct RClass*)$rbasic
#      rb_classname($arg0)
    else
    if ($flags == 0x04)
      echo T_ICLASS\n
      print *(struct RClass*)$rbasic
    else
    if ($flags == 0x05)
      echo T_MODULE\n
      print *(struct RClass*)$rbasic
    else
    if ($flags == 0x06)
      echo T_FLOAT\n
      print *(struct RFloat*)$rbasic
    else
    if ($flags == 0x07)
      echo T_STRING\n
      print *(struct RString*)$rbasic
    else
    if ($flags == 0x08)
      echo T_REGEXP\n
      print *(struct RRegexp*)$rbasic
    else
    if ($flags == 0x09)
      echo T_ARRAY\n
      print *(struct RArray*)$rbasic
    else
    if ($flags == 0x0a)
      echo T_FIXNUM\n
      echo impossible\n
    else
    if ($flags == 0x0b)
      echo T_HASH\n
      print *(struct RHash*)$rbasic
    else
    if ($flags == 0x0c)
      echo T_STRUCT\n
      print *(struct RStruct*)$rbasic
    else
    if ($flags == 0x0d)
      echo T_BIGNUM\n
      print *(struct RBignum*)$rbasic
    else
    if ($flags == 0x0e)
      echo T_FILE\n
      print *(struct RFile*)$rbasic
    else
    if ($flags == 0x20 || $flags == 0x10)
      echo T_TRUE\n
      echo impossible\n
    else
    if ($flags == 0x21 || $flags == 0x11)
      echo T_FALSE\n
      echo impossible\n
    else
    if ($flags == 0x22 || $flags == 0x12)
      echo T_DATA\n
      print *(struct RData*)$rbasic
    else
    if ($flags == 0x23 || $flags == 0x13)
      echo T_MATCH\n
      print *(struct RMatch*)$rbasic
    else
    if ($flags == 0x24 || $flags == 0x14)
      echo T_SYMBOL\n
      echo impossible\n
    else
    if ($flags == 0x3c || $flags == 0x1c)
      echo T_UNDEF\n
      echo impossible\n
    else
    if ($flags == 0x3b)
      echo T_BLOCK\n
    else
    if ($flags == 0x3d || $flags == 0x1d)
      echo T_VARMAP\n
    else
    if ($flags == 0x3e || $flags == 0x1e)
      echo T_SCOPE\n
    else
    if ($flags == 0x3f || $flags == 0x1f)
      echo T_NODE\n
      print (NODE*)$arg0
    else
      echo Unknown\n
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
rubyの組み込みオブジェクトを表示する
end

define nd_type
  print (enum node_type)((((NODE*)$arg0)->flags>>node_typemask)&node_typeshift)
end
document nd_type
ruby node の型を表示
end

define nd_file
  print ((NODE*)$arg0)->nd_file
end
document nd_file
node のソースファイル名を表示
end

define nd_line
  print ((unsigned int)((((NODE*)$arg0)->flags>>node_lshift)&node_lmask))
end
document nd_line
node の行番号を表示
end

# ruby node のメンバを表示

define nd_head
  print "u1.node"
  what $arg0.u1.node
  p $arg0.u1.node
end

define nd_alen
  print "u2.argc"
  what $arg0.u2.argc
  p $arg0.u2.argc
end

define nd_next
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_cond
  print "u1.node"
  what $arg0.u1.node
  p $arg0.u1.node
end

define nd_body
  print "u2.node"
  what $arg0.u2.node
  p $arg0.u2.node
end

define nd_else
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_orig
  print "u3.value"
  what $arg0.u3.value
  p $arg0.u3.value
end


define nd_resq
  print "u2.node"
  what $arg0.u2.node
  p $arg0.u2.node
end

define nd_ensr
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_1st
   print "u1.node"
   what $arg0.u1.node
   p $arg0.u1.node
end

define nd_2nd
   print "u2.node"
   what $arg0.u2.node
   p $arg0.u2.node
end


define nd_stts
  print "u1.node"
  what $arg0.u1.node
  p $arg0.u1.node
end


define nd_entry
 print "u3.entry"
 what $arg0.u3.entry
 p $arg0.u3.entry
end

define nd_vid
   print "u1.id"
   what $arg0.u1.id
   p $arg0.u1.id
end

define nd_cflag
 print "u2.id"
 what $arg0.u2.id
 p $arg0.u2.id
end

define nd_cval
  print "u3.value"
  what $arg0.u3.value
  p $arg0.u3.value
end


define nd_cnt
   print "u3.cnt"
   what $arg0.u3.cnt
   p $arg0.u3.cnt
end

define nd_tbl
   print "u1.tbl"
   what $arg0.u1.tbl
   p $arg0.u1.tbl
end


define nd_var
   print "u1.node"
   what $arg0.u1.node
   p $arg0.u1.node
end

define nd_ibdy
  print "u2.node"
  what $arg0.u2.node
  p $arg0.u2.node
end

define nd_iter
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_value
 print "u2.node"
 what $arg0.u2.node
 p $arg0.u2.node
end

define nd_aid
   print "u3.id"
   what $arg0.u3.id
   p $arg0.u3.id
end


define nd_lit
   print "u1.value"
   what $arg0.u1.value
   p $arg0.u1.value
end


define nd_frml
  print "u1.node"
  what $arg0.u1.node
  p $arg0.u1.node
end

define nd_rest
  print "u2.argc"
  what $arg0.u2.argc
  p $arg0.u2.argc
end

define nd_opt
   print "u1.node"
   what $arg0.u1.node
   p $arg0.u1.node
end


define nd_recv
  print "u1.node"
  what $arg0.u1.node
  p $arg0.u1.node
end

define nd_mid
   print "u2.id"
   what $arg0.u2.id
   p $arg0.u2.id
end

define nd_args
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_noex
  print "u1.id"
  what $arg0.u1.id
  p $arg0.u1.id
end

define nd_defn
  print "u3.node"
  what $arg0.u3.node
  p $arg0.u3.node
end


define nd_old
   print "u1.id"
   what $arg0.u1.id
   p $arg0.u1.id
end

define nd_new
   print "u2.id"
   what $arg0.u2.id
   p $arg0.u2.id
end


define nd_cfnc
  print "u1.cfunc"
  what $arg0.u1.cfunc
  p $arg0.u1.cfunc
end

define nd_argc
  print "u2.argc"
  what $arg0.u2.argc
  p $arg0.u2.argc
end


define nd_cname
 print "u1.id"
 what $arg0.u1.id
 p $arg0.u1.id
end

define nd_super
 print "u3.node"
 what $arg0.u3.node
 p $arg0.u3.node
end


define nd_modl
  print "u1.id"
  what $arg0.u1.id
  p $arg0.u1.id
end

define nd_clss
  print "u1.value"
  what $arg0.u1.value
  p $arg0.u1.value
end


define nd_beg
   print "u1.node"
   what $arg0.u1.node
   p $arg0.u1.node
end

define nd_end
   print "u2.node"
   what $arg0.u2.node
   p $arg0.u2.node
end

define nd_state
 print "u3.state"
 what $arg0.u3.state
 p $arg0.u3.state
end

define nd_rval
  print "u2.value"
  what $arg0.u2.value
  p $arg0.u2.value
end


define nd_nth
   print "u2.argc"
   what $arg0.u2.argc
   p $arg0.u2.argc
end


define nd_tag
   print "u1.id"
   what $arg0.u1.id
   p $arg0.u1.id
end

define nd_tval
  print "u2.value"
  what $arg0.u2.value
  p $arg0.u2.value
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
  p *(struct RClass*)$arg0
end

define rb_backtrace
  call rb_backtrace()
end
