#! /usr/bin/ruby -nl

# Used by the "make uninstall" target to uninstall Ruby.
# See common.mk for more details.

BEGIN {
  $dryrun = false
  $tty = STDOUT.tty?
  until ARGV.empty?
    case ARGV[0]
    when /\A--destdir=(.*)/
      $destdir = $1
    when /\A-n\z/
      $dryrun = true
    when /\A--(?:no-)?tty\z/
      $tty = !$1
    else
      break
    end
    ARGV.shift
  end
  $dirs = []
  $files = []
  COLUMNS = $tty && (ENV["COLUMNS"]&.to_i || begin require 'io/console/size'; rescue; else IO.console_size&.at(1); end)&.then do |n|
    n-1 if n > 1
  end
  if COLUMNS
    $column = 0
    def message(str = nil)
      $stdout.print "\b \b" * $column
      if str
        if str.size > COLUMNS
          str = "..." + str[(-COLUMNS+3)..-1]
        end
        $stdout.print str
      end
      $stdout.flush
      $column = str&.size || 0
    end
  else
    alias message puts
  end
}
list = ($_.chomp!('/') ? $dirs : $files)
list << $_
END {
  status = true
  $\ = nil
  $files.each do |file|
    message "rm #{file}"
    unless $dryrun
      file = File.join($destdir, file) if $destdir
      begin
        File.unlink(file)
      rescue Errno::ENOENT
      rescue
        status = false
        puts $!
      end
    end
  end
  unlink = {}
  $dirs.each do |dir|
    unlink[dir] = true
  end
  nonempty = {}
  while dir = $dirs.pop
    dir = File.dirname(dir) while File.basename(dir) == '.'
    message "rmdir #{dir}"
    unless $dryrun
      realdir = $destdir ? File.join($destdir, dir) : dir
      begin
        begin
          unlink.delete(dir)
          Dir.rmdir(realdir)
        rescue Errno::ENOTDIR
          raise unless File.symlink?(realdir)
          File.unlink(realdir)
        end
      rescue Errno::ENOTEMPTY
        nonempty[dir] = true
      rescue Errno::ENOENT
      rescue
        status = false
        puts $!
      else
        nonempty.delete(dir)
        parent = File.dirname(dir)
        $dirs.push(parent) unless parent == dir or unlink[parent]
      end
    end
  end
  message
  unless nonempty.empty?
    puts "Non empty director#{nonempty.size == 1 ? 'y' : 'ies'}:"
    nonempty.each_key {|dir| print "    #{dir}\n"}
  end
  exit(status)
}
