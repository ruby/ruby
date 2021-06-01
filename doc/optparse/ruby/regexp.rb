require 'optparse'
parser = OptionParser.new
parser.on('--regexp=REGEXP', Regexp) do |value|
  p [value, value.class]
end
parser.parse!
