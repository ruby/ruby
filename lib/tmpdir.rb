#
# tmpdir - retrieve temporary directory path
#
# $Id$
#

class Dir

  @@systmpdir = '/tmp'

  begin
    require 'Win32API'
    max_pathlen = 260
    windir = ' '*(max_pathlen+1)
    begin
      getdir = Win32API.new('kernel32', 'GetSystemWindowsDirectory', 'PL', 'L')
    rescue RuntimeError
      getdir = Win32API.new('kernel32', 'GetWindowsDirectory', 'PL', 'L')
    end
    getdir.call(windir, windir.size)
    windir = File.expand_path(windir.rstrip.untaint)
    temp = File.join(windir, 'temp')
    @@systmpdir = temp if File.directory?(temp) and File.writable?(temp)
  rescue LoadError
  end

  ##
  # Returns the operating system's temporary file path.

  def Dir::tmpdir
    tmp = '.'
    if $SAFE > 0
      tmp = @@systmpdir
    else
      for dir in [ENV['TMPDIR'], ENV['TMP'], ENV['TEMP'],
	          ENV['USERPROFILE'], @@systmpdir, '/tmp']
	if dir and File.directory?(dir) and File.writable?(dir)
	  tmp = dir
	  break
	end
      end
    end
    File.expand_path(tmp)
  end
end
