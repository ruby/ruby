#!/usr/bin/env ruby
Dir.chdir('../rubyspec') do
  regexp = Regexp.new(ARGV[0])
  Dir.glob('**/*.rb') do |file|
    contents = File.read(file)
    if regexp =~ contents
      puts file
    end
  end
end
