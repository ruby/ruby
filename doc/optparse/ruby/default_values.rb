require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx', 'Short and long, no argument')
parser.on('-yYYY', '--yyy', 'Short and long, required argument')
parser.on('-z [ZZZ]', '--zzz', 'Short and long, optional argument')
options = {yyy: 'AAA', zzz: 'BBB'}
parser.parse!(into: options)
p options
