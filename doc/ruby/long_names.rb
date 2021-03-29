require 'optparse'
parser = OptionParser.new
parser.on('--xxx') do |option|
  p "--xxx #{option}"
end
parser.on('--y1%', '--z2#') do |option|
  p "--y1% or --z2# #{option}"
end
parser.parse!
