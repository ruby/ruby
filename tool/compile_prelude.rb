
prelude, outfile = *ARGV
lines = []

lines = File.readlines(prelude).map{|line|
  line.dump
}

open(outfile, 'w'){|f|
f.puts <<EOS__

#include "ruby/ruby.h"
#include "vm_core.h"

static const char *prelude_code = 
#{lines.join("\n")}
;
void
Init_prelude(void)
{
  rb_iseq_eval(rb_iseq_compile(
    rb_str_new2(prelude_code),
    rb_str_new2("#{File.basename(prelude)}"), INT2FIX(1)));

#if 0
    printf("%s\n", prelude_code);
#endif
}
EOS__
}

