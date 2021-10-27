require 'optparse'
parser = OptionParser.new
parser.on('--string=STRING', String) do |value|
  p [value, value.class]
end
parser.parse!
