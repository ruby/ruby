require 'getoptlong'

options = GetoptLong.new(
  ['--xxx', '-x', '--aaa', '-a', '-p', GetoptLong::NO_ARGUMENT]
)
options.each do |option, argument|
  p [option, argument]
end
