#!/usr/bin/env ruby

# Adds tags based on error and failures output (e.g., from a CI log),
# without running any spec code.

tag = ENV["TAG"] || "fails"

tags_dir = %w[
  spec/tags
  spec/tags/ruby
].find { |dir| Dir.exist?("#{dir}/language") }
abort 'Could not find tags directory' unless tags_dir

output = ARGF.readlines

# Automatically strip datetime of GitHub Actions
if output.first =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d+Z /
  output = output.map { |line| line.split(' ', 2).last }
end

NUMBER = /^\d+\)$/
ERROR_OR_FAILED = / (ERROR|FAILED)$/
SPEC_FILE = /^(\/.+_spec\.rb)\:\d+/

output.slice_before(NUMBER).select { |number, *rest|
  number =~ NUMBER and rest.any? { |line| line =~ ERROR_OR_FAILED }
}.each { |number, *rest|
  error_line = rest.find { |line| line =~ ERROR_OR_FAILED }
  description = error_line.match(ERROR_OR_FAILED).pre_match

  spec_file = rest.find { |line| line =~ SPEC_FILE }
  if spec_file
    spec_file = spec_file[SPEC_FILE, 1] or raise
  else
    if error_line =~ /^([\w:]+)[#\.](\w+) /
      mod, method = $1, $2
      file = "#{mod.downcase.gsub('::', '/')}/#{method}_spec.rb"
      spec_file = ['spec/ruby/core', 'spec/ruby/library', *Dir.glob('spec/ruby/library/*')].find { |dir|
        path = "#{dir}/#{file}"
        break path if File.exist?(path)
      }
    end

    unless spec_file
      warn "Could not find file for:\n#{error_line}"
      next
    end
  end

  prefix = spec_file.index('spec/ruby/') || spec_file.index('spec/truffle/')
  spec_file = spec_file[prefix..-1]

  tags_file = spec_file.sub('spec/ruby/', "#{tags_dir}/").sub('spec/truffle/', "#{tags_dir}/truffle/")
  tags_file = tags_file.sub(/_spec\.rb$/, '_tags.txt')

  dir = File.dirname(tags_file)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  tag_line = "#{tag}:#{description}"
  lines = File.exist?(tags_file) ? File.readlines(tags_file, chomp: true) : []
  unless lines.include?(tag_line)
    puts tags_file
    File.write(tags_file, (lines + [tag_line]).join("\n") + "\n")
  end
}
