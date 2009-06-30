# This file is interpreted by $(BASERUBY) and miniruby.
# $(BASERUBY) is used for miniprelude.c.
# miniruby is used for prelude.c.
# Since $(BASERUBY) may be older than Ruby 1.9,
# Ruby 1.9 feature should not be used.

$:.unshift(File.expand_path("../..", __FILE__))

preludes = ARGV.dup
outfile = preludes.pop
init_name = outfile[/\w+(?=_prelude.c\b)/] || 'prelude'

C_ESC = {
  "\\" => "\\\\",
  '"' => '\"',
  "\n" => '\n',
}

0x00.upto(0x1f) {|ch| C_ESC[[ch].pack("C")] ||= "\\%03o" % ch }
0x7f.upto(0xff) {|ch| C_ESC[[ch].pack("C")] = "\\%03o" % ch }
C_ESC_PAT = Regexp.union(*C_ESC.keys)

def c_esc(str)
  '"' + str.gsub(C_ESC_PAT) { C_ESC[$&] } + '"'
end

mkconf = nil
setup_ruby_prefix = nil
teardown_ruby_prefix = nil
lines_list = preludes.map {|filename|
  lines = []
  need_ruby_prefix = false
  File.readlines(filename).each {|line|
    line.gsub!(/RbConfig::CONFIG\["(\w+)"\]/) {
      key = $1
      unless mkconf
        require 'rbconfig'
        mkconf = RbConfig::MAKEFILE_CONFIG.merge('prefix'=>'#{TMP_RUBY_PREFIX}')
        setup_ruby_prefix = "TMP_RUBY_PREFIX = $:.reverse.find{|e|e!=\".\"}.sub(%r{(.*)/lib/.*}m, \"\\\\1\")\n"
        teardown_ruby_prefix = 'Object.class_eval { remove_const "TMP_RUBY_PREFIX" }'
      end
      if RbConfig::MAKEFILE_CONFIG.has_key? key
        val = RbConfig.expand("$(#{key})", mkconf)
        need_ruby_prefix = true if /\A\#\{TMP_RUBY_PREFIX\}/ =~ val
        c_esc(val)
      else
        "nil"
      end
    }
    lines << c_esc(line)
  }
  setup_lines = []
  if need_ruby_prefix
    setup_lines << c_esc(setup_ruby_prefix)
    lines << c_esc(teardown_ruby_prefix)
  end
  [setup_lines, lines]
}

require 'erb'

tmp = ERB.new(<<'EOS', nil, '%').result(binding)
#include "ruby/ruby.h"
#include "vm_core.h"

% preludes.zip(lines_list).each_with_index {|(prelude, (setup_lines, lines)), i|
static const char prelude_name<%=i%>[] = <%=c_esc("<internal:" + File.basename(prelude, ".rb") + ">")%>;
static const char prelude_code<%=i%>[] =
%   (setup_lines+lines).each {|line|
<%=line%>
%   }
;
% }

void
Init_<%=init_name%>(void)
{
% lines_list.each_with_index {|(setup_lines, lines), i|
  rb_iseq_eval(rb_iseq_compile(
    rb_usascii_str_new(prelude_code<%=i%>, sizeof(prelude_code<%=i%>) - 1),
    rb_usascii_str_new(prelude_name<%=i%>, sizeof(prelude_name<%=i%>) - 1),
    INT2FIX(<%=1-setup_lines.length%>)));

% }
#if 0
% preludes.length.times {|i|
    puts(prelude_code<%=i%>);
% }
#endif
}
EOS

open(outfile, 'w'){|f|
  f << tmp
}

