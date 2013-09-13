#! /usr/bin/ruby -nl
BEGIN {
  $dryrun = false
  until ARGV.empty?
    case ARGV[0]
    when /\A--destdir=(.*)/
      $destdir = $1
    when /\A-n\z/
      $dryrun = true
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
  $files.each do |file|
    if $dryrun
      puts "rm #{file}"
    else
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
    if $dryrun
      puts "rmdir #{dir}"
    else
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
  exit(status)
}
