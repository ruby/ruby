require 'optparse/uri'
parser = OptionParser.new
parser.on('--uri=URI', URI) do |value|
  p [value, value.class]
end
parser.parse!
