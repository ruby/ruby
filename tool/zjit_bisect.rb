#!/usr/bin/env ruby
require 'logger'
require 'open3'
require 'shellwords'
require 'tempfile'
require 'timeout'

RUBY = ARGV[0] || raise("Usage: ruby jit_bisect.rb <path_to_ruby> <options>")
OPTIONS = ARGV[1..]
raise("Usage: ruby jit_bisect.rb <path_to_ruby> -- <options>") if OPTIONS.empty?
TIMEOUT_SEC = 5
LOGGER = Logger.new($stdout)

# From https://github.com/tekknolagi/omegastar
# MIT License
# Copyright (c) 2024 Maxwell Bernstein and Meta Platforms
# Attempt to reduce the `items` argument as much as possible, returning the
# shorter version. `fixed` will always be used as part of the items when
# running `command`.
# `command` should return True if the command succeeded (the failure did not
# reproduce) and False if the command failed (the failure reproduced).
def bisect_impl(command, fixed, items, indent="")
  LOGGER.info("#{indent}step fixed[#{fixed.length}] and items[#{items.length}]")
  while items.length > 1
    LOGGER.info("#{indent}#{fixed.length + items.length} candidates")
    # Return two halves of the given list. For odd-length lists, the second
    # half will be larger.
    half = items.length / 2
    left = items[0...half]
    right = items[half..]
    if !command.call(fixed + left)
      items = left
      next
    end
    if !command.call(fixed + right)
      items = right
      next
    end
    # We need something from both halves to trigger the failure. Try
    # holding each half fixed and bisecting the other half to reduce the
    # candidates.
    new_right = bisect_impl(command, fixed + left, right, indent + "< ")
    new_left = bisect_impl(command, fixed + new_right, left, indent + "> ")
    return new_left + new_right
  end
  items
end

# From https://github.com/tekknolagi/omegastar
# MIT License
# Copyright (c) 2024 Maxwell Bernstein and Meta Platforms
def run_bisect(command, items)
  LOGGER.info("Verifying items")
  if command.call(items)
    raise StandardError.new("Command succeeded with full items")
  end
  if !command.call([])
    raise StandardError.new("Command failed with empty items")
  end
  bisect_impl(command, [], items)
end

def run_with_jit_list(ruby, options, jit_list)
  # Make a new temporary file containing the JIT list
  Tempfile.create("jit_list") do |temp_file|
    temp_file.write(jit_list.join("\n"))
    temp_file.flush
    temp_file.close
    # Run the JIT with the temporary file
    command = Shellwords.join [ruby, "--zjit-allowed-iseqs=#{temp_file.path}", *options]
    Open3.capture3(command)
  end
end

# Try running with no JIT list to get a stable baseline
_, stderr, status = run_with_jit_list(RUBY, OPTIONS, [])
if !status.success?
  raise "Command failed with empty JIT list: #{stderr}"
end
# Collect the JIT list from the failing Ruby process
jit_list = nil
Tempfile.create "jit_list" do |temp_file|
  command = Shellwords.join [RUBY, "--zjit-log-compiled-iseqs=#{temp_file.path}", *OPTIONS]
  Open3.capture3(command)
  jit_list = File.readlines(temp_file.path).map(&:strip).reject(&:empty?)
end
LOGGER.info("Starting with JIT list of #{jit_list.length} items.")
# Now narrow it down
command = lambda do |items|
  status = Timeout.timeout(TIMEOUT_SEC) do
    _, _, status = run_with_jit_list(RUBY, OPTIONS, items)
    status
  end
  status.success?
end
result = run_bisect(command, jit_list)
File.open("jitlist.txt", "w") do |file|
  file.puts(result)
end
puts "Run:"
command = Shellwords.join [RUBY, "--zjit-allowed-iseqs=jitlist.txt", *OPTIONS]
puts command
puts "Reduced JIT list (available in jitlist.txt):"
puts result
