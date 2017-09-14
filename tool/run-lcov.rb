#!ruby
require "pathname"
require "open3"

def backup_gcda_files(gcda_files)
  gcda_files = gcda_files.map do |gcda|
    [gcda, gcda.sub_ext(".bak")]
  end
  begin
    gcda_files.each do |before, after|
      before.rename(after)
    end
    yield
  ensure
    gcda_files.each do |before, after|
      after.rename(before)
    end
  end
end

$info_files = []
def run_lcov(dir, info)
  $info_files << info
  system("lcov", "-c", "-d", dir, "--rc", "lcov_branch_coverage=1", "-o", info)
end

def gen_rb_lcov(file)
  res = Marshal.load(File.binread(file))

  open("lcov-rb-all.info", "w") do |f|
    f.puts "TN:" # no test name
    base_dir = File.dirname(__dir__)
    res.each do |path, cov|
      next unless path.start_with?(base_dir)
      next if path.start_with?(File.join(base_dir, "test"))
      f.puts "SF:#{ path }"

      total = covered = 0
      cov.each_with_index do |count, lineno|
        next unless count
        f.puts "DA:#{ lineno + 1 },#{ count }"
        total += 1
        covered += 1 if count > 0
      end
      f.puts "LF:#{ total }"
      f.puts "LH:#{ covered }"

      f.puts "end_of_record"
    end
  end
end

def gen_rb_lcov(file)
  res = Marshal.load(File.binread(file))

  open("lcov-rb-all.info", "w") do |f|
    f.puts "TN:" # no test name
    base_dir = File.dirname(File.dirname(__dir__))
    res.each do |path, cov|
      next unless path.start_with?(base_dir)
      next if path.start_with?(File.join(base_dir, "test"))
      f.puts "SF:#{ path }"

      # function coverage
      total = covered = 0
      cov[:methods].each do |(name, lineno), count|
        f.puts "FN:#{ lineno },#{ name }"
        total += 1
        covered += 1 if count > 0
      end
      f.puts "FNF:#{ total }"
      f.puts "FNF:#{ covered }"
      cov[:methods].each do |(name, _), count|
        f.puts "FNDA:#{ count },#{ name }"
      end

      # line coverage
      total = covered = 0
      cov[:lines].each_with_index do |count, lineno|
        next unless count
        f.puts "DA:#{ lineno + 1 },#{ count }"
        total += 1
        covered += 1 if count > 0
      end
      f.puts "LF:#{ total }"
      f.puts "LH:#{ covered }"

      # branch coverage
      total = covered = 0
      id = 0
      cov[:branches].each do |(base_type, base_lineno), targets|
        i = 0
        targets.each do |(target_type, target_lineno), count|
          f.puts "BRDA:#{ base_lineno },#{ id },#{ i },#{ count }"
          total += 1
          covered += 1 if count > 0
          i += 1
        end
        id += 1
      end
      f.puts "BRF:#{ total }"
      f.puts "BRH:#{ covered }"
      f.puts "end_of_record"
    end
  end
end

gcda_files = Pathname.glob("**/*.gcda")
ext_gcda_files = gcda_files.select {|f| f.fnmatch("ext/*") }
rubyspec_temp_gcda_files = gcda_files.select {|f| f.fnmatch("rubyspec_temp/*") }

backup_gcda_files(rubyspec_temp_gcda_files) do
  if ext_gcda_files != []
    backup_gcda_files(ext_gcda_files) do
      info = "lcov-root.info"
      run_lcov(".", info)
    end
  end
  ext_gcda_files.group_by {|f| f.descend.to_a[1] }.each do |key, files|
    info = "lcov-#{ key.to_s.gsub(File::Separator, "-") }.info"
    run_lcov(key.to_s, info)
  end
end
if $info_files != []
  system("lcov", *$info_files.flat_map {|f| ["-a", f] }, "--rc", "lcov_branch_coverage=1", "-o", "lcov-c-all.info")
  system("genhtml", "--branch-coverage", "--ignore-errors", "source", "lcov-c-all.info", "-o", "lcov-c-out")
end

if File.readable?("test-coverage.dat")
  gen_rb_lcov("test-coverage.dat")
  system("genhtml", "--branch-coverage", "--ignore-errors", "source", "lcov-rb-all.info", "-o", "lcov-rb-out")
end

if File.readable?("lcov-c-all.info") && File.readable?("lcov-rb-all.info")
  system("lcov", "-a", "lcov-c-all.info", "-a", "lcov-rb-all.info", "--rc", "lcov_branch_coverage=1", "-o", "lcov-all.info") || raise
  system("genhtml", "--branch-coverage", "--ignore-errors", "source", "lcov-all.info", "-o", "lcov-out")
end
