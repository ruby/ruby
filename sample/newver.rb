#! /usr/local/bin/ruby

f = open("version.h", "r")
f.gets()
f.close

if $_ =~ /"(\d)\.(\d+)"/;
  f = open("version.h", "w")
  i = $2.to_i + 1
  printf("ruby version %d.%0d\n", $1, i)
  printf(f, "#define RUBY_VERSION \"%d.%0d\"\n", $1, i)
  f.close
end
