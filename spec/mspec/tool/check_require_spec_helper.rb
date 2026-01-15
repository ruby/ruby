#!/usr/bin/env ruby

# This script is used to check that each *_spec.rb file has
# a relative_require for spec_helper which should live higher
# up in the ruby/spec repo directory tree.
#
# Prints errors to $stderr and returns a non-zero exit code when
# errors are found.
#
# Related to https://github.com/ruby/spec/pull/992

def check_file(fn)
  File.foreach(fn) do |line|
    return $1 if line =~ /^\s*require_relative\s*['"](.*spec_helper)['"]/
  end
  nil
end

rootdir = ARGV[0] || "."
fglob = File.join(rootdir, "**", "*_spec.rb")
specfiles = Dir.glob(fglob)
raise "No spec files found in #{fglob.inspect}. Give an argument to specify the root-directory of ruby/spec" if specfiles.empty?

errors = 0
specfiles.sort.each do |fn|
  result = check_file(fn)
  if result.nil?
    warn "Missing require_relative for *spec_helper for file: #{fn}"
    errors += 1
  end
end

puts "# Found #{errors} files with require_relative spec_helper issues."
exit 1 if errors > 0
