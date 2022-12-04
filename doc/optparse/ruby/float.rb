require 'optparse'
parser = OptionParser.new
parser.on('--float=FLOAT', Float) do |value|
  p [value, value.class]
end
parser.parse!
