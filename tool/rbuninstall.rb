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
}
list = ($_.chomp!('/') ? $dirs : $files)
list << $_
END {
  status = true
  $\ = nil
  ors = (!$dryrun and $tty) ? "\e[K\r" : "\n"
  $files.each do |file|
    print "rm #{file}#{ors}"
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
  while dir = $dirs.pop
    dir = File.dirname(dir) while File.basename(dir) == '.'
    print "rmdir #{dir}#{ors}"
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
      rescue Errno::ENOENT, Errno::ENOTEMPTY
      rescue
        status = false
        puts $!
      else
        parent = File.dirname(dir)
        $dirs.push(parent) unless parent == dir or unlink[parent]
      end
    end
  end
  print ors.chomp
  exit(status)
}
