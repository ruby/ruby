require 'optparse'
parser = OptionParser.new
parser.on('--integer=INTEGER', Integer) do |value|
  p [value, value.class]
end
parser.parse!
