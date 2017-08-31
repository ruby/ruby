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

gcda_files = Pathname.glob("**/*.gcda")
ext_gcda_files = gcda_files.select {|f| f.fnmatch("ext/*") }
rubyspec_temp_gcda_files = gcda_files.select {|f| f.fnmatch("rubyspec_temp/*") }

backup_gcda_files(rubyspec_temp_gcda_files) do
  backup_gcda_files(ext_gcda_files) do
    info = "lcov-root.info"
    run_lcov(".", info)
  end
  ext_gcda_files.group_by {|f| f.descend.to_a[1] }.each do |key, files|
    info = "lcov-#{ key.to_s.gsub(File::Separator, "-") }.info"
    run_lcov(key.to_s, info)
  end
end
system("lcov", *$info_files.flat_map {|f| ["-a", f] }, "-o", "lcov-c-all.info")
