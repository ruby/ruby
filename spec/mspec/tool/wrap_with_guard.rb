#!/usr/bin/env ruby
# Wrap the passed the files with a guard (e.g., `ruby_version_is ""..."3.0"`).
# Notably if some methods are removed, this is a convenient way to skip such file from a given version.
# Example usage:
# $ spec/mspec/tool/wrap_with_guard.rb 'ruby_version_is ""..."3.0"' spec/ruby/library/set/sortedset/**/*_spec.rb

guard, *files = ARGV
abort "Usage: #{$0} GUARD FILES..." if files.empty?

files.each do |file|
  contents = File.binread(file)
  lines = contents.lines.to_a

  lines = lines.map { |line| line.chomp.empty? ? line : "  #{line}" }

  version_line = "#{guard} do\n"
  if lines[0] =~ /^\s*require.+spec_helper/
    lines[0] = lines[0].sub(/^  /, '')
    lines.insert 1, "\n", version_line
  else
    warn "Could not find 'require spec_helper' line in #{file}"
    lines.insert 0, version_line
  end

  lines << "end\n"

  File.binwrite file, lines.join
end
