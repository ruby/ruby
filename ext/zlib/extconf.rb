#
# extconf.rb
#
# $Id$
#

require 'mkmf'
require 'rbconfig'

dir_config 'zlib'


if %w'z libz zlib zdll'.find {|z| have_library(z, 'deflateReset')} and
    have_header('zlib.h') then

  defines = []

  message 'checking for kind of operating system... '
  os_code = with_config('os-code') ||
    case RUBY_PLATFORM.split('-',2)[1]
    when 'amigaos' then
      os_code = 'AMIGA'
    when /\Aos2[\-_]emx\z/ then
      os_code = 'OS2'
    when 'mswin32', 'mingw32', 'bccwin32' then
      # NOTE: cygwin should be regarded as Unix.
      os_code = 'WIN32'
    else
      os_code = 'UNIX'
    end
  os_code = 'OS_' + os_code.upcase

  OS_NAMES = {
    'OS_MSDOS'   => 'MS-DOS',
    'OS_AMIGA'   => 'Amiga',
    'OS_VMS'     => 'VMS',
    'OS_UNIX'    => 'Unix',
    'OS_ATARI'   => 'Atari',
    'OS_OS2'     => 'OS/2',
    'OS_MACOS'   => 'MacOS',
    'OS_TOPS20'  => 'TOPS20',
    'OS_WIN32'   => 'Win32',
    'OS_VMCMS'   => 'VM/CMS',
    'OS_ZSYSTEM' => 'Z-System',
    'OS_CPM'     => 'CP/M',
    'OS_QDOS'    => 'QDOS',
    'OS_RISCOS'  => 'RISCOS',
    'OS_UNKNOWN' => 'Unknown',
  }
  unless OS_NAMES.key? os_code then
    puts "invalid OS_CODE `#{os_code}'"
    exit
  end
  message "#{OS_NAMES[os_code]}\n"
  defines << "OS_CODE=#{os_code}"

  defines = defines.collect{|d|' -D'+d}.join
  if $CPPFLAGS then
    $CPPFLAGS += defines
  else
    $CFLAGS += defines
  end

  create_makefile('zlib')

end
