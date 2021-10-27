# frozen_string_literal: true
#
# extconf.rb
#
# $Id$
#

require 'mkmf'
require 'rbconfig'

dir_config 'zlib'

libs = $libs
if %w'z libz zlib1 zlib zdll zlibwapi'.find {|z| have_library(z, 'deflateReset')} and
    have_header('zlib.h') then
  have_zlib = true
else
  $libs = libs
  unless File.directory?(zsrc = "#{$srcdir}/zlib")
    dirs = Dir.open($srcdir) {|z| z.grep(/\Azlib-\d+[.\d]*\z/) {|x|"#{$srcdir}/#{x}"}}
    dirs.delete_if {|x| !File.directory?(x)}
    zsrc = dirs.max_by {|x| x.scan(/\d+/).map(&:to_i)}
  end
  if zsrc
    addconf = [
      "ZSRC = $(srcdir)/#{File.basename(zsrc)}\n",
      "all:\n",
    ]
    $INCFLAGS << " -I$(ZSRC)"
    if $mswin or $mingw
      dll = "zlib1.dll"
      $extso << dll
      $cleanfiles << "$(topdir)/#{dll}" << "$(ZIMPLIB)"
      zmk = "\t$(MAKE) -f $(ZMKFILE) TOP=$(ZSRC)"
      zopts = []
      if $nmake
        zmkfile = "$(ZSRC)/win32/Makefile.msc"
        m = "#{zsrc}/win32/Makefile.msc"
        # zopts << "USE_ASM=1"
        zopts << "ARCH=#{RbConfig::CONFIG['target_cpu']}"
      else
        zmkfile = "$(ZSRC)/win32/Makefile.gcc"
        m = "#{zsrc}/win32/Makefile.gcc"
        zmk += " PREFIX="
        zmk << CONFIG['CC'][/(.*-)gcc([^\/]*)\z/, 1]
        zmk << " CC=$(CC)" if $2
      end
      m = File.read(m)
      zimplib = m[/^IMPLIB[ \t]*=[ \t]*(\S+)/, 1]
      ($LOCAL_LIBS << " ./" << zimplib).strip!
      unless $nmake or /^TOP[ \t]/ =~ m
        m.gsub!(/win32\/zlib\.def/, '$(TOP)/\&')
        m.gsub!(/^(\t.*[ \t])(\S+\.rc)/, '\1-I$(<D) $<')
        m = "TOP = .\n""VPATH=$(TOP)\n" + m
        zmkfile = File.basename(zmkfile)
        File.rename(zmkfile, zmkfile+".orig") if File.exist?(zmkfile)
        File.write(zmkfile, m)
      end
      addconf.push(
        "ZMKFILE = #{zmkfile}\n",
        "ZIMPLIB = #{zimplib}\n",
        "ZOPTS = #{zopts.join(' ')}\n",
        "$(TARGET_SO): $(ZIMPLIB)\n",
        "$(ZIMPLIB):\n",
        "#{zmk} $(ZOPTS) $@\n",
        "install-so static: $(topdir)/#{dll}",
        "$(topdir)/#{dll}: $(ZIMPLIB)\n",
        "\t$(Q) $(COPY) #{dll} $(@D)\n",
        "clean: clean-zsrc\n",
        "clean-zsrc:\n",
        "#{zmk} clean\n",
      )
    end
    Logging.message "using zlib in #{zsrc}\n"
    $defs << "-DHAVE_ZLIB_H"
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

  if zsrc
    $defs << "-DHAVE_CRC32_COMBINE"
    $defs << "-DHAVE_ADLER32_COMBINE"
    $defs << "-DHAVE_TYPE_Z_CRC_T"
  else
    have_func('crc32_combine', 'zlib.h')
    have_func('adler32_combine', 'zlib.h')
    have_type('z_crc_t', 'zlib.h')
  end

  create_makefile('zlib') {|conf|
    if zsrc
      conf.concat addconf if addconf
    end
    conf
  }

end
