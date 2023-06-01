# frozen_string_literal: true

require "bundler/setup"
require "syntax_suggest/api"

require "benchmark"
require "tempfile"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  if config.color_mode == :automatic
    if config.color_enabled? && ((ENV["TERM"] == "dumb") || ENV["NO_COLOR"]&.slice(0))
      config.color_mode = :off
    end
  end
end

# Used for debugging modifications to
# display output
def debug_display(output)
  return unless ENV["DEBUG_DISPLAY"]
  puts
  puts output
  puts
end

def spec_dir
  Pathname(__dir__)
end

def lib_dir
  if ruby_core?
    root_dir.join("../lib")
  else
    root_dir.join("lib")
  end
end

def root_dir
  spec_dir.join("..")
end

def fixtures_dir
  spec_dir.join("fixtures")
end

def ruby_core?
  !root_dir.join("syntax_suggest.gemspec").exist?
end

def code_line_array(source)
  SyntaxSuggest::CleanDocument.new(source: source).call.lines
end

autoload :RubyProf, "ruby-prof"

def debug_perf
  raise "No block given" unless block_given?

  if ENV["DEBUG_PERF"]
    out = nil
    result = RubyProf.profile do
      out = yield
    end

    dir = SyntaxSuggest.record_dir("tmp")
    printer = RubyProf::MultiPrinter.new(result, [:flat, :graph, :graph_html, :tree, :call_tree, :stack, :dot])
    printer.print(path: dir, profile: "profile")

    out
  else
    yield
  end
end

def run!(cmd, raise_on_nonzero_exit: true)
  out = `#{cmd} 2>&1`
  raise "Command: #{cmd} failed: #{out}" if !$?.success? && raise_on_nonzero_exit
  out
end

# Allows us to write cleaner tests since <<~EOM block quotes
# strip off all leading indentation and we need it to be preserved
# sometimes.
class String
  def indent(number)
    lines.map do |line|
      if line.chomp.empty?
        line
      else
        " " * number + line
      end
    end.join
  end
end
