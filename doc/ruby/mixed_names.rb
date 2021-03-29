require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx') do |option|
  p "--xxx #{option}"
end
parser.on('-y', '--y1%') do |option|
  p "--y1% #{option}"
end
parser.parse!
