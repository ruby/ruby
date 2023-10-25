require 'optparse/date'
parser = OptionParser.new
parser.on('--datetime=DATETIME', DateTime) do |value|
  p [value, value.class]
end
parser.parse!
