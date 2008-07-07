#
# tmpdir - retrieve temporary directory path
#
# $Id$
#

class Dir

  @@systmpdir = '/tmp'

  begin
    require 'Win32API'
    CSIDL_LOCAL_APPDATA = 0x001c
    max_pathlen = 260
    windir = ' '*(max_pathlen+1)
    begin
      getdir = Win32API.new('shell32', 'SHGetFolderPath', 'LLLLP', 'L')
      raise RuntimeError if getdir.call(0, CSIDL_LOCAL_APPDATA, 0, 0, windir) != 0
      windir = File.expand_path(windir.rstrip)
    rescue RuntimeError
      begin
        getdir = Win32API.new('kernel32', 'GetSystemWindowsDirectory', 'PL', 'L')
      rescue RuntimeError
        getdir = Win32API.new('kernel32', 'GetWindowsDirectory', 'PL', 'L')
      end
      len = getdir.call(windir, windir.size)
      windir = File.expand_path(windir[0, len])
    end
    temp = File.join(windir.untaint, 'temp')
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
      File.expand_path(tmp)
    end
  end
end
