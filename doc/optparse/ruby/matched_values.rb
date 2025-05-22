require 'optparse'
parser = OptionParser.new
parser.on('--xxx XXX', /foo/i, 'Matched values') do |value|
  p ['--xxx', value]
end
parser.on('--yyy YYY', Integer, 'Check by range', 1..3) do |value|
  p ['--yyy', value]
end
parser.on('--zzz ZZZ', Integer, 'Check by list', [1, 3, 4]) do |value|
  p ['--zzz', value]
end
parser.parse!
