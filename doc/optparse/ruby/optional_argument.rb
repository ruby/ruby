require 'optparse'
parser = OptionParser.new
parser.on('-x [XXX]', '--xxx', 'Optional argument via short  name') do |value|
  p ['--xxx', value]
end
parser.on('-y', '--yyy [YYY]', 'Optional argument via long name') do |value|
  p ['--yyy', value]
end
parser.parse!
