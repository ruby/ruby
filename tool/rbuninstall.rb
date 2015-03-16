#! /usr/bin/ruby -nl
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
$_ = File.join($destdir, $_) if $destdir
list << $_
END {
  status = true
  $\ = ors = (!$dryrun and $tty) ? "\e[K\r" : "\n"
  $files.each do |file|
    print "rm #{file}"
    unless $dryrun
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
    print "rmdir #{dir}"
    unless $dryrun
      begin
        begin
          unlink.delete(dir)
          Dir.rmdir(dir)
        rescue Errno::ENOTDIR
          raise unless File.symlink?(dir)
          File.unlink(dir)
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
  $\ = nil
  print ors.chomp
  exit(status)
}
