#
# tmpdir - retrieve temporary directory path
#
# $Id$
#

class Dir
  begin
    require "Win32API"
    max_pathlen = 260
    t_path = ' '*(max_pathlen+1)
    t_path[0, Win32API.new('kernel32', 'GetTempPath', 'LP', 'L').call(t_path.size, t_path)]
    t_path.untaint
    TMPDIR = t_path
  rescue LoadError
    if $SAFE > 0
      TMPDIR = '/tmp'
    else
      TMPDIR = ENV['TMPDIR']||ENV['TMP']||ENV['TEMP']||'/tmp'
    end
  end
end

if __FILE__ == $0
  puts Dir::TMPDIR
end
