
prelude, outfile = *ARGV

lines = File.readlines(prelude).map{|line|
  line.dump
}

open(outfile, 'w'){|f|
  f.puts <<EOS__, <<'EOS__'

#include "ruby/ruby.h"
#include "vm_core.h"

static const char prelude_name[] = "#{File.basename(prelude)}";
static const char prelude_code[] =
#{lines.join("\n")}
;
EOS__

void
Init_prelude(void)
{
  rb_iseq_eval(rb_iseq_compile(
    rb_str_new(prelude_code, sizeof(prelude_code) - 1),
    rb_str_new(prelude_name, sizeof(prelude_name) - 1),
    INT2FIX(1)));

#if 0
    printf("%s\n", prelude_code);
#endif
}
EOS__
}

