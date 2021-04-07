require 'optparse'
parser = OptionParser.new
parser.on('--object=OBJECT', Object) do |value|
  p [value, value.class]
end
parser.parse!
