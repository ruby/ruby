# This file is interpreted by $(BASERUBY) and miniruby.
# $(BASERUBY) is used for miniprelude.c.
# miniruby is used for prelude.c.
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

mkconf = nil
setup_ruby_prefix = nil
lines_list = preludes.map {|filename|
  lines = []
  need_ruby_prefix = false
  File.readlines(filename).each {|line|
    line.gsub!(/RbConfig::CONFIG\["(\w+)"\]/) {
      unless mkconf
        require 'rbconfig'
        mkconf = RbConfig::MAKEFILE_CONFIG.merge('prefix'=>'#{ruby_prefix}')
        exlen = $:.grep(%r{\A/}).last.length - RbConfig::CONFIG["prefix"].length
        setup_ruby_prefix = "ruby_prefix = $:.grep(%r{\\A/}).last[0..#{-exlen-1}]\n"
      end
      if RbConfig::MAKEFILE_CONFIG.has_key? $1
        val = RbConfig.expand("$(#$1)", mkconf)
        need_ruby_prefix = true if /\A\#{ruby_prefix\}/ =~ val
        c_esc(val)
      else
        $&
      end
    }
    lines << c_esc(line)
  }
  setup_lines = []
  if need_ruby_prefix
    setup_lines << c_esc(setup_ruby_prefix)
  end
  [setup_lines, lines]
}

open(outfile, 'w'){|f|
  f.puts <<'EOS__'

#include "ruby/ruby.h"
#include "vm_core.h"

EOS__

  preludes.zip(lines_list).each_with_index {|(prelude, (setup_lines, lines)), i|
    f.puts <<EOS__
static const char prelude_name#{i}[] = "#{File.basename(prelude)}";
static const char prelude_code#{i}[] =
#{(setup_lines+lines).join("\n")}
;
EOS__
  }
  f.puts <<'EOS__'

void
Init_prelude(void)
{
EOS__
  lines_list.each_with_index {|(setup_lines, lines), i|
    f.puts <<EOS__
  rb_iseq_eval(rb_iseq_compile(
    rb_str_new(prelude_code#{i}, sizeof(prelude_code#{i}) - 1),
    rb_str_new(prelude_name#{i}, sizeof(prelude_name#{i}) - 1),
    INT2FIX(#{1-setup_lines.length})));

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

