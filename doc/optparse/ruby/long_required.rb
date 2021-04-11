require 'optparse'
parser = OptionParser.new
parser.on('--xxx XXX', 'Long name with required argument') do |value|
  p ['--xxx', value]
end
parser.parse!
