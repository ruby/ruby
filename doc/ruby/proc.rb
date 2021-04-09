require 'optparse'
parser = OptionParser.new
parser.on(
  '--xxx',
  'Option with no argument',
  ->(value) {p ['Handler proc for -xxx called with value:', value]}
)
parser.on(
  '--yyy YYY',
  'Option with required argument',
  ->(value) {p ['Handler proc for -yyy called with value:', value]}
)
parser.parse!
