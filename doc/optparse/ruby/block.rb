require 'optparse'
parser = OptionParser.new
parser.on('--xxx', 'Option with no argument') do |value|
  p ['Handler block for -xxx called with value:', value]
end
parser.on('--yyy YYY', 'Option with required argument') do |value|
  p ['Handler block for -yyy called with value:', value]
end
parser.parse!
