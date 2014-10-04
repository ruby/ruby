require 'mkmf'

dir_config("gdbm")
if have_library("gdbm", "gdbm_open") and
   have_header("gdbm.h")
  checking_for("sizeof(DBM) is available") {
    if try_compile(<<SRC)
#include <gdbm.h>

const int sizeof_DBM = (int)sizeof(DBM);
SRC
      $defs << '-DDBM_SIZEOF_DBM=sizeof(DBM)'
    else
      $defs << '-DDBM_SIZEOF_DBM=0'
    end
  }
  create_makefile("gdbm")
end
