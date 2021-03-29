require 'optparse'
parser = OptionParser.new
parser.on('-x') do |option|
  p "-x #{option}"
end
parser.on('-1', '-%') do |option|
  p "-1 or -% #{option}"
end
parser.parse!
