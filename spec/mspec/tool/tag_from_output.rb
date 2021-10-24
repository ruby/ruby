#!/usr/bin/env ruby

# Adds tags based on error and failures output (e.g., from a CI log),
# without running any spec code.

tags_dir = %w[
  spec/tags
  spec/tags/ruby
].find { |dir| Dir.exist?("#{dir}/language") }
abort 'Could not find tags directory' unless tags_dir

output = ARGF.readlines

NUMBER = /^\d+\)$/
ERROR_OR_FAILED = / (ERROR|FAILED)$/
SPEC_FILE = /^(\/.+_spec\.rb)\:\d+/

output.slice_before(NUMBER).select { |number, *rest|
  number =~ NUMBER and rest.any? { |line| line =~ ERROR_OR_FAILED }
}.each { |number, *rest|
  error_line = rest.find { |line| line =~ ERROR_OR_FAILED }
  description = error_line.match(ERROR_OR_FAILED).pre_match

  spec_file = rest.find { |line| line =~ SPEC_FILE }
  unless spec_file
    warn "Could not find file for:\n#{error_line}"
    next
  end
  spec_file = spec_file[SPEC_FILE, 1]
  prefix = spec_file.index('spec/ruby/') || spec_file.index('spec/truffle/')
  spec_file = spec_file[prefix..-1]

  tags_file = spec_file.sub('spec/ruby/', "#{tags_dir}/").sub('spec/truffle/', "#{tags_dir}/truffle/")
  tags_file = tags_file.sub(/_spec\.rb$/, '_tags.txt')

  dir = File.dirname(tags_file)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  tag_line = "fails:#{description}"
  lines = File.exist?(tags_file) ? File.readlines(tags_file, chomp: true) : []
  unless lines.include?(tag_line)
    puts tags_file
    File.write(tags_file, (lines + [tag_line]).join("\n") + "\n")
  end
}
