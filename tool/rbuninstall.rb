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
  if $dryrun
    $files.each do |file|
      puts "rm #{file}"
    end
    $dirs.reverse_each do |dir|
      puts "rmdir #{dir}"
    end
  else
    $files.each do |file|
      begin
        File.unlink(file)
      rescue Errno::ENOENT
      rescue
        status = false
        puts $!
      end
    end
    $dirs.reverse_each do |dir|
      begin
        begin
          Dir.rmdir(dir)
        rescue Errno::ENOTDIR
          raise unless File.symlink?(dir)
          File.unlink(dir)
        end
      rescue Errno::ENOENT, Errno::ENOTEMPTY
      rescue
        status = false
        puts $!
      end
    end
  end
  exit(status)
}
