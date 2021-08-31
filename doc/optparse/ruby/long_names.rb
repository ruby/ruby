require 'optparse'
parser = OptionParser.new
parser.on('--xxx', 'Long name') do |value|
  p ['-xxx', value]
end
parser.on('--y1%', '--z2#', "Two long names") do |value|
  p ['--y1% or --z2#', value]
end
parser.parse!
