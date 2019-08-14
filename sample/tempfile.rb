require 'tempfile'

f = Tempfile.new("foo")
f.print("foo\n")
f.close
f.open
p f.gets # => "foo\n"
f.close!
