#!ruby
require "pathname"
require "open3"

BASE_DIR = Pathname(__dir__).dirname

# Hack to allow gcov to find parse.c
unless File.symlink?("ext/ripper/parse.c")
  File.symlink("../../parse.c", "ext/ripper/parse.c")
end

Pathname.glob(BASE_DIR + "**/*.gcda").sort.each do |gcda|
  gcda = gcda.relative_path_from(BASE_DIR)
  if gcda.fnmatch("ext/*")
    cwd, gcda = gcda.split.map {|s| s.to_s }
    objdir = "."
  else
    cwd, objdir, gcda = ".", gcda.dirname.to_s, gcda.to_s
  end
  puts "$ gcov -lpbc -o #{ objdir } #{ gcda }"
  out, _status = Open3.capture2e("gcov", "-lpbc", "-o", objdir, gcda, chdir: cwd)
  puts out

  if out !~ /\A(File .*\nLines executed:.*\n(Branches executed:.*\nTaken at least once:.*\n|No branches\n)?(Calls executed:.*\n|No calls\n)?Creating .*\n\n)+\z/
    raise "Unexpected gcov output"
  end
end
