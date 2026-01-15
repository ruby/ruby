require 'optparse'
parser = OptionParser.new
parser.on('--numeric=NUMERIC', Numeric) do |value|
  p [value, value.class]
end
parser.parse!
