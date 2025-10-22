#!/usr/bin/env ruby
require 'logger'
require 'optparse'
require 'shellwords'
require 'tempfile'
require 'timeout'

ARGS = {timeout: 5}
OptionParser.new do |opts|
  opts.banner += " <path_to_ruby> -- <options>"
  opts.on("--timeout=TIMEOUT_SEC", "Seconds until child process is killed") do |timeout|
    ARGS[:timeout] = Integer(timeout)
  end
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

usage = "Usage: zjit_bisect.rb <path_to_ruby> -- <options>"
RUBY = ARGV[0] || raise(usage)
OPTIONS = ARGV[1..]
raise(usage) if OPTIONS.empty?
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

def add_zjit_options cmd
  if RUBY == "make"
    # Automatically detect that we're running a make command instead of a Ruby
    # one. Pass the bisection options via RUN_OPTS/SPECOPTS instead.
    zjit_opts = cmd.select { |arg| arg.start_with?("--zjit") }
    run_opts_index = cmd.find_index { |arg| arg.start_with?("RUN_OPTS=") }
    specopts_index = cmd.find_index { |arg| arg.start_with?("SPECOPTS=") }
    if run_opts_index
      run_opts = Shellwords.split(cmd[run_opts_index].delete_prefix("RUN_OPTS="))
      run_opts.concat(zjit_opts)
      cmd[run_opts_index] = "RUN_OPTS=#{run_opts.shelljoin}"
    elsif specopts_index
      specopts = Shellwords.split(cmd[specopts_index].delete_prefix("SPECOPTS="))
      specopts.concat(zjit_opts)
      cmd[specopts_index] = "SPECOPTS=#{specopts.shelljoin}"
    else
      raise "Expected RUN_OPTS or SPECOPTS to be present in make command"
    end
    cmd = cmd - zjit_opts
  end
  cmd
end

def run_ruby *cmd
  cmd = add_zjit_options(cmd)
  pid = Process.spawn(*cmd, {
    in: :close,
    out: [File::NULL, File::RDWR],
    err: [File::NULL, File::RDWR],
  })
  begin
    status = Timeout.timeout(ARGS[:timeout]) do
      Process::Status.wait(pid)
    end
  rescue Timeout::Error
    Process.kill("KILL", pid)
    LOGGER.warn("Timed out after #{ARGS[:timeout]} seconds")
    status = Process::Status.wait(pid)
  end

  status
end

def run_with_jit_list(ruby, options, jit_list)
  # Make a new temporary file containing the JIT list
  Tempfile.create("jit_list") do |temp_file|
    temp_file.write(jit_list.join("\n"))
    temp_file.flush
    temp_file.close
    # Run the JIT with the temporary file
    run_ruby ruby, "--zjit-allowed-iseqs=#{temp_file.path}", *options
  end
end

# Try running with no JIT list to get a stable baseline
unless run_with_jit_list(RUBY, OPTIONS, []).success?
  cmd = [RUBY, "--zjit-allowed-iseqs=/dev/null", *OPTIONS].shelljoin
  raise "The command failed unexpectedly with an empty JIT list. To reproduce, try running the following: `#{cmd}`"
end
# Collect the JIT list from the failing Ruby process
jit_list = nil
Tempfile.create "jit_list" do |temp_file|
  run_ruby RUBY, "--zjit-log-compiled-iseqs=#{temp_file.path}", *OPTIONS
  jit_list = File.readlines(temp_file.path).map(&:strip).reject(&:empty?)
end
LOGGER.info("Starting with JIT list of #{jit_list.length} items.")
# Try running without the optimizer
status = run_with_jit_list(RUBY, ["--zjit-disable-hir-opt", *OPTIONS], jit_list)
if status.success?
  LOGGER.warn "*** Command suceeded with HIR optimizer disabled. HIR optimizer is probably at fault. ***"
end
# Now narrow it down
command = lambda do |items|
  run_with_jit_list(RUBY, OPTIONS, items).success?
end
result = run_bisect(command, jit_list)
File.open("jitlist.txt", "w") do |file|
  file.puts(result)
end
puts "Run:"
jitlist_path = File.expand_path("jitlist.txt")
puts add_zjit_options([RUBY, "--zjit-allowed-iseqs=#{jitlist_path}", *OPTIONS]).shelljoin
puts "Reduced JIT list (available in jitlist.txt):"
puts result
