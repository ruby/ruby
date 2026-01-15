require 'optparse'
parser = OptionParser.new
parser.on('--false_class=FALSE_CLASS', FalseClass) do |value|
  p [value, value.class]
end
parser.parse!
