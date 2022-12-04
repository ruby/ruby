require 'optparse'
include OptionParser::Acceptables
parser = OptionParser.new
parser.on('--decimal_integer=DECIMAL_INTEGER', DecimalInteger) do |value|
  p [value, value.class]
end
parser.parse!
