require 'optparse'
parser = OptionParser.new
parser.on('-n', '--dry-run',) do |value|
  p ['--dry-run', value]
end
parser.on('-d', '--draft',) do |value|
  p ['--draft', value]
end
parser.parse!
