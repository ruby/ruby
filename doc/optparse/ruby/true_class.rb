require 'optparse'
parser = OptionParser.new
parser.on('--true_class=TRUE_CLASS', TrueClass) do |value|
  p [value, value.class]
end
parser.parse!
