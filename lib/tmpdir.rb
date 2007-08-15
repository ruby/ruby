#
# tmpdir - retrieve temporary directory path
#
# $Id$
#

require 'fileutils'

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
    len = getdir.call(windir, windir.size)
    windir = File.expand_path(windir[0, len])
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

  # Dir.mktmpdir creates a temporary directory.
  #
  # The directory is created with 0700 permission.
  # The name of the directory is prefixed
  # with <i>prefix</i> argument.
  # If <i>prefix</i> is not given,
  # the prefix "d" is used.
  #
  # The directory is created under Dir.tmpdir or
  # the optional second argument <i>tmpdir</i> if given.
  #
  # If a block is given,
  # it is yielded with the path of the directory.
  # The directory is removed before Dir.mktmpdir returns.
  # The value of the block is returned.
  #
  #  Dir.mktmpdir {|dir|
  #    # use the directory...
  #    open("#{dir}/foo", "w") { ... }
  #  }
  #
  # If a block is not given,
  # The path of the directory is returned.
  # In this case, Dir.mktmpdir doesn't remove the directory.
  #
  #  dir = Dir.mktmpdir
  #  begin
  #    # use the directory...
  #    open("#{dir}/foo", "w") { ... }
  #  ensure
  #    # remove the directory.
  #    FileUtils.remove_entry_secure dir
  #  end
  #
  def Dir.mktmpdir(prefix="d", tmpdir=nil)
    tmpdir ||= Dir.tmpdir
    t = Time.now.strftime("%Y%m%d")
    n = nil
    begin
      path = "#{tmpdir}/#{prefix}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}"
      path << "-#{n}" if n
      Dir.mkdir(path, 0700)
    rescue Errno::EEXIST
      n ||= 0
      n += 1
      retry
    end

    if block_given?
      begin
        yield path
      ensure
        FileUtils.remove_entry_secure path
      end
    else
      path
    end
  end
end
