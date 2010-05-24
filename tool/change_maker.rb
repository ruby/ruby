#! ./miniruby

if File.directory?(".svn")
  cmd = "svn diff"
elsif File.directory?(".git")
  cmd = "git diff"
else
  abort "does not seem to be under a vcs"
end

def diff2index(cmd, *argv)
  path = nil
  `#{cmd} #{argv.join(" ")}`.split(/\n/).each do |line|
    case line
    when /^Index: (\S*)/, /^diff --git [a-z]\/(\S*) [a-z]\/\1/
      path = $1
    when /^@@.*@@ +([A-Za-z_][A-Za-z_0-9 ]*[A-Za-z_0-9])/
      puts "* #{path} (#{$1}):"
    end
  end
  !!path
end

if !diff2index(cmd, ARGV) and /^git/ =~ cmd
  diff2index(cmd, "--cached", ARGV)
end
