require 'getoptlong'

options = GetoptLong.new(
  ['--xxx', GetoptLong::NO_ARGUMENT],
  ['--xyz', GetoptLong::NO_ARGUMENT]
)
options.each do |option, argument|
  p [option, argument]
end
