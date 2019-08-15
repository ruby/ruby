#!ruby
require "pathname"
require "open3"

Pathname.glob("**/*.gcda").sort.each do |gcda|
  if gcda.fnmatch("ext/*")
    cwd, gcda = gcda.split.map {|s| s.to_s }
    objdir = "."
  elsif gcda.fnmatch("rubyspec_temp/*")
    next
  else
    cwd, objdir, gcda = ".", gcda.dirname.to_s, gcda.to_s
  end
  puts "$ gcov -lpbc -o #{ objdir } #{ gcda }"
  out, err, _status = Open3.capture3("gcov", "-lpbc", "-o", objdir, gcda, chdir: cwd)
  puts out
  puts err

  # a black list of source files that contains wrong #line directives
  if err !~ %r(
    \A(
      Cannot\ open\ source\ file\ (
         defs/keywords
        |zonetab\.list
        |enc/jis/props\.kwd
        |parser\.c
        |parser\.rl
      )\n
    )*\z
  )x
    raise "Unexpected gcov output"
  end

  if out !~ %r(
    \A(
      File\ .*\nLines\ executed:.*\n
      (
        Branches\ executed:.*\n
        Taken\ at\ least\ once:.*\n
      |
        No\ branches\n
      )?
      (
        Calls\ executed:.*\n
      |
        No\ calls\n
      )?
      Creating\ .*\n
      \n
    )+\z
  )x
    raise "Unexpected gcov output"
  end
end
