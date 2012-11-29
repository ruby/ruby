# -*- coding: us-ascii -*-
require 'mkmf'
require 'fileutils'

# :stopdoc:

dir_config 'libyaml'

if enable_config("bundled-libyaml", false) || !(find_header('yaml.h') && find_library('yaml', 'yaml_get_version'))
  # Embed libyaml since we could not find it.

  $VPATH << "$(srcdir)/yaml"
  $INCFLAGS << " -I$(srcdir)/yaml"

  $srcs = Dir.glob("#{$srcdir}/{,yaml/}*.c").map {|n| File.basename(n)}

  if have_macro("_WIN32")
    $CPPFLAGS << " -DYAML_DECLARE_STATIC -DHAVE_CONFIG_H"
  end

  have_header 'dlfcn.h'
  have_header 'inttypes.h'
  have_header 'memory.h'
  have_header 'stdint.h'
  have_header 'stdlib.h'
  have_header 'strings.h'
  have_header 'string.h'
  have_header 'sys/stat.h'
  have_header 'sys/types.h'
  have_header 'unistd.h'

  find_header 'yaml.h'
  have_header 'config.h'
end

create_makefile 'psych'

# :startdoc:
