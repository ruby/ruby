set $fl_ushift = 11
set $fl_user1 = 1 << ($fl_ushift + 0)
set $fl_user1 = 1 << ($fl_ushift + 1)
set $fl_user2 = 1 << ($fl_ushift + 2)
set $fl_user3 = 1 << ($fl_ushift + 3)
set $fl_user4 = 1 << ($fl_ushift + 4)
set $fl_user5 = 1 << ($fl_ushift + 5)
set $fl_user6 = 1 << ($fl_ushift + 6)
set $fl_user7 = 1 << ($fl_ushift + 7)

define rp
  if $arg0 & 1
    printf "FIXNUM: %d\n", ((long)$arg0) >> 1
  else
  if ($arg0 & 0xff) == 0x0e
    printf "SYMBOL(%d)\n", ((long)$arg0) >> 8
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
  if $arg0 & 0x03
    echo immediate\n
  else
  set $flags = ((struct RBasic*)$arg0)->flags
  if ($flags & 0x1f) == 0x00
    printf "T_NONE(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x01
    printf "T_NIL(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x02
    printf "T_OBJECT(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x03
    printf "T_CLASS(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x04
    printf "T_ICLASS(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x05
    printf "T_MODULE(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x06
    printf "T_FLOAT(0x%08x): %.16g\n", $arg0, (((struct RFloat*)$arg0)->value)
  else
  if ($flags & 0x1f) == 0x07
    printf "T_STRING(0x%08x): \"%s\"\n", $arg0, ($flags & $fl_user1) ? ((struct RString*)$arg0)->as.heap.ptr : ((struct RString*)$arg0)->as.ary 
  else
  if ($flags & 0x1f) == 0x08
    printf "T_REGEXP(0x%08x): \"%s\"\n", $arg0, (((struct RRegexp*)$arg0)->str)
  else
  if ($flags & 0x1f) == 0x09
    printf "T_ARRAY(0x%08x) len=%d\n", $arg0, ((struct RArray*)$arg0)->len
  else
  if ($flags & 0x1f) == 0x0a
    printf "T_FIXNUM(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x0b
    printf "T_HASH(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x0c
    printf "T_STRUCT(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x0d
    printf "T_BIGNUM(0x%08x): sign=%d len=%d\n", $arg0, ((struct RBignum*)$arg0)->sign, ((struct RBignum*)$arg0)->len
  else
  if ($flags & 0x1f) == 0x0e
    printf "T_FILE(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x10
    printf "T_TRUE(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x11
    printf "T_FALSE(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x12
    printf "T_DATA(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x13
    printf "T_MATCH(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x14
    printf "T_SYMBOL(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x1a
    printf "T_VALUES(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x1b
    printf "T_BLOCK(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x1c
    printf "T_UNDEF(0x%08x)\n", $arg0
  else
  if ($flags & 0x1f) == 0x1f
    printf "T_NODE(0x%08x)\n", $arg0
    print (enum node_type)(($flags >> 11) & 0xff)
  else
    printf "unknown(0x%08x)\n", $arg0
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
