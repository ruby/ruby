require 'mkmf'
require 'rbconfig'

unless $CFLAGS.gsub!(/ -O[\dsz]?/, ' -O3')
  $CFLAGS << ' -O3'
end
if CONFIG['CC'] =~ /gcc/
  $CFLAGS << ' -Wall'
  #unless $CFLAGS.gsub!(/ -O[\dsz]?/, ' -O0 -ggdb')
  #  $CFLAGS << ' -O0 -ggdb'
  #end
end

if RUBY_VERSION < "1.9"
  have_header("re.h")
else
  have_header("ruby/re.h")
  have_header("ruby/encoding.h")
end
create_makefile 'json/ext/generator'
