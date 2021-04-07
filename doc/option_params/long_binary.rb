require 'optparse'
parser = OptionParser.new
parser.on('--[no-]binary') do |value|
  p [value, value.class]
end
parser.parse!
