require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx', 'Short and long, no argument')
parser.on('-yYYY', '--yyy', 'Short and long, required argument')
parser.on('-z [ZZZ]', '--zzz', 'Short and long, optional argument')
options = {}
parser.parse!(into: options)
required_options = [:xxx, :zzz]
missing_options = required_options - options.keys
unless missing_options.empty?
  fail "Missing required options: #{missing_options}"
end
