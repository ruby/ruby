require 'getoptlong'

options = GetoptLong.new(
  ['--number', '-n', GetoptLong::REQUIRED_ARGUMENT],
  ['--verbose', '-v', GetoptLong::OPTIONAL_ARGUMENT],
  ['--help', '-h', GetoptLong::NO_ARGUMENT]
)
