#! /usr/local/bin/ruby
# convert ls-lR filename into fullpath.

if ARGV[0] =~ /-p/
  ARGV.shift
  path = ARGV.shift 
end

if path == nil
  path = ""
elsif path !~ /\/$/
  path += "/"
end

while gets()
  if /:$/
    path = $_.chop.chop + "/"
  elsif /^total/ || /^d/
  elsif /^(.*\d )(.+)$/
    print($1, path, $2, "\n")
  end
end
    
