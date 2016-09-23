# frozen_string_literal: false
#
# extconf.rb
#
# $Id$
#

require 'mkmf'
require 'rbconfig'

dir_config 'zlib'


if %w'z libz zlib1 zlib zdll zlibwapi'.find {|z| have_library(z, 'deflateReset')} and
    have_header('zlib.h') then
  have_zlib = true
else
  unless File.directory?(zsrc = "#{$srcdir}/zlib")
    dirs = Dir.open($srcdir) {|z| z.grep(/\Azlib-\d+[.\d]*\z/) {|x|"#{$srcdir}/#{x}"}}
    dirs.delete_if {|x| !File.directory?(x)}
    zsrc = dirs.max_by {|x| x.scan(/\d+/).map(&:to_i)}
  end
  if zsrc
    $INCFLAGS << " -I$(ZSRC)"
    if $mswin or $mingw
      $libs = append_library($libs, "zdll")
      dll = "zlib1.dll"
    end
    have_zlib = true
  end
end

if have_zlib
  defines = []

  Logging::message 'checking for kind of operating system... '
  os_code = with_config('os-code') ||
    case RUBY_PLATFORM.split('-',2)[1]
    when 'amigaos' then
      os_code = 'AMIGA'
    when /mswin|mingw|bccwin/ then
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
    raise "invalid OS_CODE `#{os_code}'"
  end
  Logging::message "#{OS_NAMES[os_code]}\n"
  defines << "OS_CODE=#{os_code}"

  $defs.concat(defines.collect{|d|' -D'+d})

  have_func('crc32_combine', 'zlib.h')
  have_func('adler32_combine', 'zlib.h')
  have_type('z_crc_t', 'zlib.h')

  create_makefile('zlib') {|conf|
    if zsrc
      conf << "ZSRC = $(srcdir)/#{File.basename(zsrc)}\n"
      conf << "all:\n"
      if $mingw or $mswin
        conf << "ZIMPLIB = zdll.lib\n"
        conf << "$(TARGET_SO): $(ZIMPLIB)\n"
        conf << "$(ZIMPLIB):\n"
        conf << "\t$(MAKE) -f $(ZSRC)/win32/Makefile.#{$nmake ? 'msc' : 'gcc'} TOP=$(ZSRC) $@\n"
        conf << "install-so: $(topdir)/#{dll}"
        conf << "$(topdir)/#{dll}: $(ZIMPLIB)\n"
        conf << "\t$(Q) $(COPY) #{dll} $(@D)\n"
      end
    end
    conf
  }

end
