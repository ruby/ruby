require 'optparse/time'
parser = OptionParser.new
parser.on('--time=TIME', Time) do |value|
  p [value, value.class]
end
parser.parse!
