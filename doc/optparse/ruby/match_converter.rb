require 'optparse/date'
parser = OptionParser.new
parser.accept(:capitalize, /\w*/) do |value|
  value.capitalize
end
parser.on('--capitalize XXX', :capitalize) do |value|
  p [value, value.class]
end
parser.parse!
