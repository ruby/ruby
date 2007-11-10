# This file is interpreted by $(BASERUBY) and miniruby.
# $(BASERUBY) is used for prelude.c.
# miniruby is used for ext_prelude.c.
# Since $(BASERUBY) may be older than Ruby 1.9,
# Ruby 1.9 feature should not be used.

preludes = ARGV.dup
outfile = preludes.pop

C_ESC = {
  "\\" => "\\\\",
  '"' => '\"',
  "\n" => '\n',
}

0x00.upto(0x1f) {|ch| C_ESC[[ch].pack("C")] ||= "\\x%02x" % ch }
0x7f.upto(0xff) {|ch| C_ESC[[ch].pack("C")] = "\\x%02x" % ch }
C_ESC_PAT = Regexp.union(*C_ESC.keys)

def c_esc(str)
  '"' + str.gsub(C_ESC_PAT) { C_ESC[$&] } + '"'
end

lines_list = preludes.map {|prelude|
  lines = []
  File.readlines(prelude).each {|line|
    line.gsub!(/RbConfig::CONFIG\["(\w+)"\]/) {
      require 'rbconfig'
      if RbConfig::CONFIG.has_key? $1
        c_esc(RbConfig::CONFIG[$1])
      else
        $&
      end
    }
    lines << c_esc(line)
  }
  lines
}

open(outfile, 'w'){|f|
  f.puts <<'EOS__'

#include "ruby/ruby.h"
#include "vm_core.h"

EOS__

  preludes.zip(lines_list).each_with_index {|(prelude, lines), i|
    f.puts <<EOS__
static const char prelude_name#{i}[] = "#{File.basename(prelude)}";
static const char prelude_code#{i}[] =
#{lines.join("\n")}
;
EOS__
  }
  f.puts <<'EOS__'

void
Init_prelude(void)
{
EOS__
  preludes.length.times {|i|
    f.puts <<EOS__
  rb_iseq_eval(rb_iseq_compile(
    rb_str_new(prelude_code#{i}, sizeof(prelude_code#{i}) - 1),
    rb_str_new(prelude_name#{i}, sizeof(prelude_name#{i}) - 1),
    INT2FIX(1)));

EOS__
  }
    f.puts <<EOS__
#if 0
EOS__
  preludes.length.times {|i|
    f.puts <<EOS__
    puts(prelude_code#{i});
EOS__
  }
    f.puts <<EOS__
#endif
EOS__

  f.puts <<'EOS__'
}
EOS__
}

