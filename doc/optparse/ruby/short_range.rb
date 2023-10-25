require 'optparse'
parser = OptionParser.new
parser.on('-[!-~]', 'Short names in (very large) range') do |name, value|
  p ['!-~', name, value]
end
parser.parse!
