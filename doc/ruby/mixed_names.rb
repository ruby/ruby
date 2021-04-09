require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx') do |value|
  p ['--xxx', value]
end
parser.on('-y', '--y1%') do |value|
  p ['--y1%', value]
end
parser.parse!
