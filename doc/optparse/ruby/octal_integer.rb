require 'optparse'
include OptionParser::Acceptables
parser = OptionParser.new
parser.on('--octal_integer=OCTAL_INTEGER', OctalInteger) do |value|
  p [value, value.class]
end
parser.parse!
