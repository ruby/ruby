# rename file
require 'tempfile'

max = 100_000
tmp = [ Tempfile.new('rename-a'), Tempfile.new('rename-b') ]
a, b = tmp.map { |x| x.path }
tmp.each { |t| t.close } # Windows can't rename files without closing them
max.times do
  File.rename(a, b)
  File.rename(b, a)
end
