# Require the OptionParser code.
require 'optparse'
# Create an OptionParser object.
parser = OptionParser.new
# Define one or more options.
parser.on('-x', 'Whether to X') do |value|
  p ['x', value]
end
parser.on('-y', 'Whether to Y') do |value|
  p ['y', value]
end
parser.on('-z', 'Whether to Z') do |value|
  p ['z', value]
end
# Parse the command line and return pared-down ARGV.
p parser.parse!

