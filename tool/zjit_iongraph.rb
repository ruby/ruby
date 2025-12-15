#!/usr/bin/env ruby
require 'json'
require 'logger'

LOGGER = Logger.new($stderr)

def run_ruby *cmd
  # Find the first --zjit* option and add --zjit-dump-hir-iongraph after it
  zjit_index = cmd.find_index { |arg| arg.start_with?("--zjit") }
  raise "No --zjit option found in command" unless zjit_index
  cmd.insert(zjit_index + 1, "--zjit-dump-hir-iongraph")
  pid = Process.spawn(*cmd)
  _, status = Process.wait2(pid)
  if status.exitstatus != 0
    LOGGER.warn("Command failed with exit status #{status.exitstatus}")
  end
  pid
end

usage = "Usage: zjit_iongraph.rb <path_to_ruby> <options>"
RUBY = ARGV[0] || raise(usage)
OPTIONS = ARGV[1..]
pid = run_ruby(RUBY, *OPTIONS)
functions = Dir["/tmp/zjit-iongraph-#{pid}/fun*.json"].map do |path|
  JSON.parse(File.read(path))
end

if functions.empty?
  LOGGER.warn("No iongraph functions found for PID #{pid}")
end

json = JSON.dump({version: 1, functions: functions})
# Get zjit_iongraph.html from the sibling file next to this script
html = File.read(File.join(File.dirname(__FILE__), "zjit_iongraph.html"))
html.sub!("{{ IONJSON }}", json)
output_path = "zjit_iongraph_#{pid}.html"
File.write(output_path, html)
puts "Wrote iongraph to #{output_path}"
