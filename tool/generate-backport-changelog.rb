#!ruby
require "time"

def usage!
  STDERR.puts <<-EOS
Usage: #$0 [--trunk=<dir>] [--target=<dir>] <revision(s)>

Generate ChangeLog entries for backporting.
The entries are output to STDOUT, and the messages of this tool are output to
STDERR. So you can simply redirect STDOUT to get the entries.

You should specify the path of trunk by `--trunk`. If not, assumed cwd.
You also should specify the path of the target branch by `--target`. If not,
assumed cwd.
This means that you have to specify at least one of `--trunk` or `--target`.

revision(s) can be below or their combinations:
  12345        # means r12345
  12345,54321  # means r12345 and r54321
  12345-12347  # means r12345, r12346 and r12347 (of course, if available)

Note that the revisions is backported branch's ones, not trunk's.

The target of this tool is *not* to generate ChangeLog automatically, but to
generate the draft of ChangeLog.
You have to check and modify the output.
  EOS
  exit
end

Majors = {
  "eregon" => "Benoit Daloze  <eregontp@gmail.com>",
  "kazu" => "Kazuhiro NISHIYAMA  <zn@mbf.nifty.com>",
  "ko1" => "Koichi Sasada  <ko1@atdot.net>",
  "marcandre" => "Marc-Andre Lafortune  <ruby-core@marc-andre.ca>",
  "naruse" => "NARUSE, Yui  <naruse@ruby-lang.org>",
  "nobu" => "Nobuyoshi Nakada  <nobu@ruby-lang.org>",
  "normal" => "Eric Wong  <normalperson@yhbt.net>",
  "rhe" => "Kazuki Yamaguchi  <k@rhe.jp>",
  "shugo" => "Shugo Maeda  <shugo@ruby-lang.org>",
  "stomar" => "Marcus Stollsteimer <sto.mar@web.de>",
  "usa" => "NAKAMURA Usaku  <usa@ruby-lang.org>",
  "zzak" => "Zachary Scott  <e@zzak.io>",
}

trunk = "."
target = "."
ARGV.delete_if{|e| /^--trunk=(.*)/ =~ e && trunk = $1}
ARGV.delete_if{|e| /^--target=(.*)/ =~ e && target = $1}
usage! if ARGV.size == 0 || trunk == target

revisions = []
ARGV.each do |a|
  a.split(/,/).each do |b|
    if /-/ =~ b
      revisions += Range.new(*b.split(/-/, 2).map{|e| Integer(e)}).to_a
    else
      revisions << Integer(b)
    end
  end
end
revisions.sort!
revisions.reverse!

revisions.each do |rev|
  if /^Index: ChangeLog$/ =~ `svn diff -c #{rev} #{target}`
    STDERR.puts "#{rev} already has ChangeLog. Skip."
  else
    lines = `svn log -r #{rev} #{target}`.lines[1..-2]
    if lines.empty?
      STDERR.puts "#{rev} does not exist. Skip."
      next
    end
    unless /^merge revision\(s\) (\d+)/ =~ lines[2]
      STDERR.puts "#{rev} is not seems to be a merge commit. Skip."
      next
    end
    original = $1
    committer = `svn log -r #{original} #{trunk}`.lines[1].split(/\|/)[1].strip
    if Majors[committer]
      committer = Majors[committer]
    else
      committer = "#{committer}  <#{committer}@ruby-lang.org>"
    end
    time = Time.parse(lines.shift.split(/\|/)[2]).getlocal("+09:00")
    puts "#{time.asctime}  #{committer}"
    puts
    lines.shift(2) # skip "merge" line
    lines.shift while lines.first == "\n"
    lines.pop while lines.last == "\n"
    lines.each do |line|
      line.chomp!
      line = "\t#{line}" if line[0] != "\t" && line != ""
      puts line
    end
    puts
    STDERR.puts "#{rev} is processed."
  end
end
