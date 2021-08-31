require 'optparse'
parser = OptionParser.new
parser.on('--my_option XXX') do |value|
  p [value, value.class]
end
parser.parse!
