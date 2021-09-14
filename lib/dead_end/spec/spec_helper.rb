# frozen_string_literal: true

require "bundler/setup"
require "dead_end/internals" # Don't auto load code to

require 'tempfile'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def spec_dir
  Pathname(__dir__)
end

def lib_dir
  root_dir.join("lib")
end

def root_dir
  spec_dir.join("..")
end

def fixtures_dir
  spec_dir.join("fixtures")
end

def code_line_array(string)
  code_lines = []
  string.lines.each_with_index do |line, index|
    code_lines << DeadEnd::CodeLine.new(line: line, index: index)
  end
  code_lines
end

def run!(cmd)
  out = `#{cmd} 2>&1`
  raise "Command: #{cmd} failed: #{out}" unless $?.success?
  out
end

# Allows us to write cleaner tests since <<~EOM block quotes
# strip off all leading indentation and we need it to be preserved
# sometimes.
class String
  def indent(number)
    self.lines.map do |line|
      if line.chomp.empty?
        line
      else
        " " * number + line
      end
    end.join
  end

  def strip_control_codes
    self.gsub(/\e\[[^\x40-\x7E]*[\x40-\x7E]/, "")
  end
end


