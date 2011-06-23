require 'rake'

# Load the test files from the command line.

ARGV.each do |f|
  next if f =~ /^-/

  if f =~ /\*/
    FileList[f].to_a.each { |fn| require File.expand_path(fn) }
  else
    require File.expand_path(f)
  end
end
