#!ruby
require "pathname"
require "open3"
require "tmpdir"

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

def run_lcov(*args)
  system("lcov", "--rc", "geninfo_unexecuted_blocks=1", "--rc", "lcov_branch_coverage=1", *args, exception: true)
end

$info_files = []
def run_lcov_capture(dir, info)
  $info_files << info
  run_lcov("--capture", "-d", dir, "-o", info)
end

def run_lcov_merge(files, info)
  run_lcov(*files.flat_map {|f| ["--add-tracefile", f] }, "-o", info)
end

def run_lcov_remove(info_src, info_out)
  dirs = %w(/usr/*)
  dirs << File.join(Dir.tmpdir, "*")
  %w(
    test/*
    ext/-test-/*
    ext/nkf/nkf-utf8/nkf.c
  ).each {|f| dirs << File.join(File.dirname(__dir__), f) }
  run_lcov("--ignore-errors", "unused", "--remove", info_src, *dirs, "-o", info_out)
end

def run_genhtml(info, out)
  base_dir = File.dirname(File.dirname(__dir__))
  ignore_errors = %w(source unmapped category).reject do |a|
    Open3.capture3("genhtml", "--ignore-errors", a)[1].include?("unknown argument for --ignore-errors")
  end
  system("genhtml",
    "--branch-coverage",
    "--prefix", base_dir,
    *ignore_errors.flat_map {|a| ["--ignore-errors", a] },
    info, "-o", out, exception: true)
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
      cov[:methods].each do |(klass, name, lineno), count|
        f.puts "FN:#{ lineno },#{ klass }##{ name }"
        total += 1
        covered += 1 if count > 0
      end
      f.puts "FNF:#{ total }"
      f.puts "FNF:#{ covered }"
      cov[:methods].each do |(klass, name, _), count|
        f.puts "FNDA:#{ count },#{ klass }##{ name }"
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
      cov[:branches].each do |(_base_type, _, base_lineno), targets|
        i = 0
        targets.each do |(_target_type, _target_lineno), count|
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
      run_lcov_capture(".", info)
    end
  end
  ext_gcda_files.group_by {|f| f.descend.to_a[1] }.each do |key, files|
    info = "lcov-#{ key.to_s.gsub(File::Separator, "-") }.info"
    run_lcov_capture(key.to_s, info)
  end
end
if $info_files != []
  run_lcov_merge($info_files, "lcov-c-all.info")
  run_lcov_remove("lcov-c-all.info", "lcov-c-all-filtered.info")
  run_genhtml("lcov-c-all-filtered.info", "lcov-c-out")
end

if File.readable?("test-coverage.dat")
  gen_rb_lcov("test-coverage.dat")
  run_lcov_remove("lcov-rb-all.info", "lcov-rb-all-filtered.info")
  run_genhtml("lcov-rb-all-filtered.info", "lcov-rb-out")
end

if File.readable?("lcov-c-all.info") && File.readable?("lcov-rb-all.info")
  run_lcov_merge(%w(lcov-c-all.info lcov-rb-all.info), "lcov-all.info")
  run_lcov_remove("lcov-all.info", "lcov-all-filtered.info")
  run_genhtml("lcov-all-filtered.info", "lcov-out")
end
