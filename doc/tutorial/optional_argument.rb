require 'optparse'
parser = OptionParser.new
parser.on('-x [XXX]', '--xxx') do |value|
  p ['--xxx', value]
end
parser.on('-y', '--yyy [YYY]') do |value|
  p ['--yyy', value]
end
parser.parse!
