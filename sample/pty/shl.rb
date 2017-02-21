# frozen_string_literal: true
#
#  old-fashioned 'shl' like program
#  by A. Ito
#
#  commands:
#     c        creates new shell
#     C-z      suspends shell
#     p        lists all shell
#     0,1,...  choose shell
#     q        quit

require 'pty'
require 'io/console'

$shells = []

$r_pty = nil
$w_pty = nil

def writer
  STDIN.raw!
  begin
    while true
      c = STDIN.getc
      if c == ?\C-z then
        $reader.raise('Suspend')
        return 'Suspend'
      end
      $w_pty.print c.chr
      $w_pty.flush
    end
  rescue
    $reader.raise('Exit')
    return 'Exit'
  ensure
    STDIN.cooked!
  end
end

$reader = Thread.new {
  while true
    begin
      Thread.stop unless $r_pty
      c = $r_pty.getc
      if c.nil? then
        Thread.main.raise('Exit')
        Thread.stop
      end
      print c.chr
      STDOUT.flush
    rescue
      Thread.stop
    end
  end
}

# $reader.raise(nil)


while true
  print ">> "
  STDOUT.flush
  n = nil
  case gets
  when /^c/i
    $shells << PTY.spawn("/bin/csh")
    n = -1
  when /^p/i
    $shells.each_with_index do |s, i|
      if s
        print i,"\n"
      end
    end
  when /^([0-9]+)/
    n = $1.to_i
    if $shells[n].nil?
      print "\##{i} doesn't exist\n"
      n = nil
    end
  when /^q/i
    exit
  end
  if n
    $r_pty, $w_pty, pid = $shells[n]
    $reader.run
    if writer == 'Exit' then
      Process.wait(pid)
      $shells[n] = nil
      $shells.pop until $shells.empty? or $shells[-1]
    end
  end
end
