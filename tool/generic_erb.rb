require 'erb'

template = ARGV.shift
ERB.new(File.read(template), nil, '%').run
