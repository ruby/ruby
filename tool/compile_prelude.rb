
prelude, outfile = *ARGV
lines = []

File.readlines(prelude).each{|line|
  lines << "#{line.dump}"
}

open(outfile, 'w'){|f|
f.puts <<EOS__

#include "ruby/ruby.h"
static const char *prelude_code = 
#{lines.join("\n")}
;
void
Init_prelude(void)
{
  rb_iseq_eval(rb_iseq_compile(
    rb_str_new2(prelude_code),
    rb_str_new2("prelude.rb"), INT2FIX(1)));
}
EOS__
}

