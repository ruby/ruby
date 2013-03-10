#! ./miniruby

def diff2index(cmd, *argv)
  lines = []
  path = nil
  output = `#{cmd} #{argv.join(" ")}`
  if defined? Encoding::BINARY
    output.force_encoding Encoding::BINARY
  end
  output.each_line do |line|
    case line
    when /^Index: (\S*)/, /^diff --git [a-z]\/(\S*) [a-z]\/\1/
      path = $1
    when /^@@\s*-[,\d]+ +\+(\d+)[,\d]*\s*@@(?: +([A-Za-z_][A-Za-z_0-9 ]*[A-Za-z_0-9]))?/
      line = $1.to_i
      ent = "\t* #{path}"
      ent << " (#{$2})" if $2
      lines << "#{ent}:"
    end
  end
  lines.uniq!
  lines.empty? ? nil : lines
end

if `svnversion` =~ /^\d+/
  cmd = "svn diff --diff-cmd=diff -x-pU0"
  change = diff2index(cmd, ARGV)
elsif File.directory?(".git")
  cmd = "git diff -U0"
  change = diff2index(cmd, ARGV) || diff2index(cmd, "--cached", ARGV)
else
  abort "does not seem to be under a vcs"
end
puts change if change
