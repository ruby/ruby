#!/usr/bin/env ruby

require 'erb'
require 'optparse'
require 'pathname'

options = {}

OptionParser.new do |parser|
  parser.accept(Pathname) do |value|
    Pathname.new(value)
  end
  parser.on('-r', '--ruby RUBY', Pathname, 'Path to the ruby executable')
  parser.on('-p', '--print-script', TrueClass, 'Print the content of the bpftrace script')
  parser.on('-d', '--dry-run', TrueClass, 'Dry run.  Print the bpftrace command to be executed, but do not actually execute it.')
end.parse!(into: options)

[:ruby].each do |k|
  if !options.include?(k)
    raise "Option --#{k} is required"
  end
end

ruby_bin = options[:ruby]
if !ruby_bin.file?
  raise "Ruby executable '#{ruby_bin}' does not exist"
end

script = IO.read(Pathname(__dir__) / 'capture.bt')
template = ERB.new(script)

content = template.result_with_hash({
  ruby: ruby_bin,
})

if options[:"print-script"]
  $stderr.puts content
end

IO.write('capture.out.bt', content)

command_line = ["sudo", "bpftrace", "-v", "--unsafe", "capture.out.bt"]
$stderr.puts "Command to execute:"
$stderr.puts command_line.map{|s| "'#{s}'"}.join(' ')

if options[:"dry-run"]
  $stderr.puts "Dry run.  Exit..."
  exit 0
end

exec(*command_line)
