require 'optparse/date'
parser = OptionParser.new
parser.on('--date=DATE', Date) do |value|
  p [value, value.class]
end
parser.parse!
