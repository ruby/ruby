#! ./ruby
f = open("version.h", "r")
f.gets()
f.close

if $_ =~ /"(\d+)\.(\d+)"/;
  f = open("version.h", "w")
  i = $2.to_i + 1
  date = Time.now.strftime("%d %b %y")
  printf("ruby version %d.%0d (%s)\n", $1, i, date)
  printf(f, "#define RUBY_VERSION \"%d.%0d\"\n", $1, i)
  printf(f, "#define VERSION_DATE \"%s\"\n", date)
  f.close
end
