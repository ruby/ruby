require 'getoptlong'

options = GetoptLong.new(
  ['--xxx', GetoptLong::REQUIRED_ARGUMENT],
  ['--yyy', GetoptLong::OPTIONAL_ARGUMENT],
  ['--zzz', GetoptLong::NO_ARGUMENT]
)
options.each do |option, argument|
  p [option, argument]
end
