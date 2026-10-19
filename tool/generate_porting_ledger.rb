#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "optparse"
require "open3"
require "rbconfig"

VALID_STATUSES = ["Not Started", "In Progress", "Ported", "Blocked", "N/A"].freeze

def number_with_delimiter(number)
  number.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, '\1,')
end

def find_preprocessor_context(file_path, error_line_num)
  return nil unless File.file?(file_path) && error_line_num.positive?

  lines = File.readlines(file_path)
  idx = [error_line_num - 1, lines.size - 1].min

  while idx >= 0
    line = lines[idx]
    if line =~ /^\s*#\s*(if|ifndef|ifdef)\b/
      return { line_num: idx + 1, content: line.strip }
    end
    idx -= 1
  end

  nil
end

def check_c_fallback(repo_root, basename)
  file_path = File.join(repo_root, basename)
  return { success: false, output: "File #{basename} not found" } unless File.file?(file_path)

  cmd = nil
  makefile_path = File.join(repo_root, "Makefile")

  if File.file?(makefile_path)
    obj_name = basename.sub(/\.c$/, ".o")
    make_cmd = ["make", "-n", obj_name]
    stdout, status = Open3.capture2e(*make_cmd, chdir: repo_root)
    if status.success?
      compile_line = stdout.lines.find { |l| l =~ /\b(?:cc|gcc|clang)\b.*-c\s+.*#{Regexp.escape(basename)}/i || l =~ /-c\s+.*#{Regexp.escape(basename)}/i }
      if compile_line
        dev_null = RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ ? "NUL" : "/dev/null"
        cmd = compile_line.strip.sub(/-o\s+\S+/, "-o #{dev_null}") + " -DUSE_RUST_PORTS=0"
      end
    end
  end

  unless cmd
    cc = RbConfig::CONFIG["CC"] || "gcc"
    dev_null = RbConfig::CONFIG["host_os"] =~ /mswin|mingw/ ? "NUL" : "/dev/null"
    arch = RbConfig::CONFIG["arch"]
    inc_flags = "-I. -I.ext/include/#{arch} -I.ext/include -I./include -I. -I./prism"
    cmd = "#{cc} #{inc_flags} -DUSE_RUST_PORTS=0 -c #{basename} -o #{dev_null}"
  end

  stdout_and_stderr, status = Open3.capture2e(cmd, chdir: repo_root)
  if status.success?
    { success: true, cmd: cmd, output: stdout_and_stderr }
  else
    error_line = nil
    stdout_and_stderr.scan(/#{Regexp.escape(basename)}:(\d+):/) do |m|
      error_line ||= m[0].to_i
    end

    preproc_ctx = error_line ? find_preprocessor_context(file_path, error_line) : nil

    {
      success: false,
      cmd: cmd,
      output: stdout_and_stderr,
      error_line: error_line,
      preproc_context: preproc_ctx
    }
  end
end

check_mode = false
check_fallbacks = false
OptionParser.new do |opts|
  opts.banner = "Usage: ruby tool/generate_porting_ledger.rb [options]"

  opts.on("--check", "Check if PORTING.md is up-to-date without modifying it") do
    check_mode = true
  end

  opts.on("--check-fallbacks", "Verify PORTING.md alignment and check C fallback compilation integrity") do
    check_mode = true
    check_fallbacks = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit 0
  end
end.parse!

repo_root = File.expand_path("..", __dir__)
status_file_path = File.join(repo_root, "tool", "porting_status.yml")
porting_md_path = File.join(repo_root, "PORTING.md")

unless File.file?(status_file_path)
  warn "Error: Status configuration file not found at #{status_file_path}"
  exit 1
end

status_data = YAML.load_file(status_file_path) || {}
subsystems_config = status_data["subsystems"] || {}
files_config = status_data["files"] || {}

c_files = Dir.glob(File.join(repo_root, "*.c")).sort

if !c_files.empty? && system("git", "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL, chdir: repo_root)
  IO.popen(["git", "-C", repo_root, "check-ignore", *c_files]) do |io|
    ignored_files = io.read.split("\n")
    c_files -= ignored_files
  end
end

file_entries = c_files.map do |file_path|
  basename = File.basename(file_path)
  loc = File.foreach(file_path).count
  config = files_config[basename] || {}

  status = config["status"] || "Not Started"
  unless VALID_STATUSES.include?(status)
    warn "Warning: Invalid status '#{status}' for #{basename}, defaulting to 'Not Started'"
    status = "Not Started"
  end

  {
    basename: basename,
    loc: loc,
    status: status,
    target: config["target"] || "-",
    subsystem: config["subsystem"] || "Utilities & Support",
    notes: config["notes"] || ""
  }
end

total_files = file_entries.size
total_loc = file_entries.sum { |e| e[:loc] }

stats = VALID_STATUSES.each_with_object({}) do |st, hash|
  entries = file_entries.select { |e| e[:status] == st }
  count = entries.size
  loc = entries.sum { |e| e[:loc] }
  pct = total_loc.positive? ? (loc.to_f / total_loc * 100.0).round(1) : 0.0
  hash[st] = { count: count, loc: loc, pct: pct }
end

# Build Markdown content
lines = []
lines << "# C-to-Rust Porting Ledger"
lines << ""
lines << "Automated migration ledger tracking C source files, line counts, and Rust porting status."
lines << "Generated automatically by `ruby tool/generate_porting_ledger.rb`. Do not edit manually."
lines << ""
lines << "## Summary Statistics"
lines << ""
lines << "| Metric | File Count | Lines of Code (LOC) | % of Total LOC |"
lines << "| :--- | :--- | :--- | :--- |"
lines << "| **Total C Source Files** | #{number_with_delimiter(total_files)} | #{number_with_delimiter(total_loc)} | 100.0% |"

VALID_STATUSES.each do |st|
  s = stats[st]
  lines << "| **#{st}** | #{number_with_delimiter(s[:count])} | #{number_with_delimiter(s[:loc])} | #{s[:pct]}% |"
end

lines << ""
lines << "## Migration Progress by Subsystem"
lines << ""

subsystem_names = subsystems_config.keys
# Add any subsystems present in file entries that were not explicitly in config
extra_subsystems = file_entries.map { |e| e[:subsystem] }.uniq - subsystem_names
all_subsystems = subsystem_names + extra_subsystems

all_subsystems.each do |subsystem_name|
  sub_entries = file_entries.select { |e| e[:subsystem] == subsystem_name }
  next if sub_entries.empty?

  sub_loc = sub_entries.sum { |e| e[:loc] }
  sub_desc = subsystems_config.dig(subsystem_name, "description")

  lines << "### #{subsystem_name}"
  lines << "_#{sub_desc}_" if sub_desc && !sub_desc.empty?
  lines << ""
  lines << "| C Source File | Lines (LOC) | Status | Target Rust Crate/Module | Notes |"
  lines << "| :--- | :--- | :--- | :--- | :--- |"

  sub_entries.sort_by { |e| e[:basename] }.each do |e|
    lines << "| `#{e[:basename]}` | #{number_with_delimiter(e[:loc])} | #{e[:status]} | `#{e[:target]}` | #{e[:notes]} |"
  end
  lines << ""
end

lines << "## Complete C Source File Ledger"
lines << ""
lines << "| C Source File | Subsystem | Lines (LOC) | Status | Target Rust Crate/Module | Notes |"
lines << "| :--- | :--- | :--- | :--- | :--- | :--- |"

file_entries.sort_by { |e| e[:basename] }.each do |e|
  lines << "| `#{e[:basename]}` | #{e[:subsystem]} | #{number_with_delimiter(e[:loc])} | #{e[:status]} | `#{e[:target]}` | #{e[:notes]} |"
end
lines << ""

generated_markdown = lines.join("\n")

if check_mode
  unless File.file?(porting_md_path)
    warn "Error: PORTING.md does not exist."
    exit 1
  end

  existing_markdown = File.read(porting_md_path)

  # Line counts change with every upstream sync, so --check ignores them:
  # it masks the "Lines (LOC)", "Lines of Code (LOC)" and "% of Total LOC"
  # cells (found by their column headers) and compares everything else --
  # the file list, statuses, file counts, targets, subsystems and notes.
  mask_loc = lambda do |markdown|
    masked_columns = []
    markdown.lines.map do |line|
      unless line.start_with?("|")
        masked_columns = []
        next line
      end
      cells = line.chomp.split("|", -1)
      if cells.any? { |c| c.include?("LOC") }
        masked_columns = cells.each_index.select { |i| cells[i].include?("LOC") }
        next line
      end
      masked_columns.each { |i| cells[i] = " # " if cells[i] }
      cells.join("|") + "\n"
    end.join
  end

  failed = false

  if existing_markdown == generated_markdown
    puts "PORTING.md is up to date."
  elsif mask_loc.(existing_markdown) == mask_loc.(generated_markdown)
    puts "PORTING.md is up to date (line counts have drifted; run 'ruby tool/generate_porting_ledger.rb' to refresh them)."
  else
    warn "Error: PORTING.md is out of date. Please run 'ruby tool/generate_porting_ledger.rb' to update."
    failed = true
  end

  if check_fallbacks
    puts "Verifying C fallback compilation for ported/in-progress C source files..."
    target_entries = file_entries.select { |e| ["In Progress", "Ported"].include?(e[:status]) }

    if target_entries.empty?
      puts "No C files marked as 'In Progress' or 'Ported'."
    else
      fallback_failures = 0
      target_entries.sort_by { |e| e[:basename] }.each do |entry|
        res = check_c_fallback(repo_root, entry[:basename])
        if res[:success]
          puts "  [PASS] #{entry[:basename]} C fallback compilation"
        else
          fallback_failures += 1
          warn "  [FAIL] #{entry[:basename]} C fallback compilation:"
          warn "    Command: #{res[:cmd]}"
          if res[:error_line] && res[:preproc_context]
            warn "    Error location: #{entry[:basename]}:#{res[:error_line]}"
            warn "    Preprocessor context: #{entry[:basename]}:#{res[:preproc_context][:line_num]}: #{res[:preproc_context][:content]}"
          end
          warn "    Compiler error output:"
          res[:output].to_s.each_line do |line|
            warn "      #{line.chomp}"
          end
        end
      end

      if fallback_failures > 0
        warn "Error: #{fallback_failures} C fallback compilation check(s) failed."
        failed = true
      else
        puts "All C fallback compilation checks passed successfully."
      end
    end
  end

  exit(failed ? 1 : 0)
else
  File.write(porting_md_path, generated_markdown)
  puts "Updated PORTING.md successfully (#{total_files} C source files, #{number_with_delimiter(total_loc)} LOC)."
  exit 0
end
