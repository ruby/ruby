require 'optparse'
parser = OptionParser.new
parser.on('--[no-]binary', 'Long name with negation') do |value|
  p [value, value.class]
end
parser.parse!
