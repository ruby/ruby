#include "vm_core.h"

provider ruby {
  probe function__entry(const char *, const char *, const char *, int);
  probe function__return(const char *, const char *, const char *, int);

  probe require__entry(const char *, const char *, int);
  probe require__return(const char *);

  probe find__require__entry(const char *, const char *, int);
  probe find__require__return(const char *, const char *, int);

  probe load__entry(const char *, const char *, int);
  probe load__return(const char *);

  probe raise(const char *, const char *, int);

  probe object__create(const char *, const char *, int);
  probe array__create(long, const char *, int);
  probe hash__create(long, const char *, int);
  probe string__create(long, const char *, int);

  probe parse__begin(const char *, int);
  probe parse__end(const char *, int);

#if VM_COLLECT_USAGE_DETAILS
  probe insn(const char *);
  probe insn__operand(const char *, const char *);
#endif

  probe gc__mark__begin();
  probe gc__mark__end();
  probe gc__sweep__begin();
  probe gc__sweep__end();
};

#pragma D attributes Stable/Evolving/Common provider ruby provider
#pragma D attributes Stable/Evolving/Common provider ruby module
#pragma D attributes Stable/Evolving/Common provider ruby function
#pragma D attributes Evolving/Evolving/Common provider ruby name
#pragma D attributes Evolving/Evolving/Common provider ruby args
