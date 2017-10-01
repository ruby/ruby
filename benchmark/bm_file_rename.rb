# rename file
require 'tempfile'

max = 100_000
tmp = [ Tempfile.new('rename-a'), Tempfile.new('rename-b') ]
a, b = tmp.map { |x| x.path }
max.times do
  File.rename(a, b)
  File.rename(b, a)
end
tmp.each { |t| t.close! }
