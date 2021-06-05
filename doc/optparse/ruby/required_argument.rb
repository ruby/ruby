require 'optparse'
parser = OptionParser.new
parser.on('-x XXX', '--xxx', 'Required argument via short name') do |value|
  p ['--xxx', value]
end
parser.on('-y', '--y YYY', 'Required argument via long name') do |value|
  p ['--yyy', value]
end
parser.parse!
