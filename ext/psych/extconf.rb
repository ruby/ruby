# -*- coding: us-ascii -*-
# frozen_string_literal: true
require 'mkmf'
require 'fileutils'

# :stopdoc:

dir_config 'libyaml'

bundle = enable_config("bundled-libyaml") do
  save = [$INCFLAGS, $LIBPATH, $libs].map(&:dup)
  pkg =
    case
    when !find_header('yaml.h')
      false
    when !find_library('yaml', 'yaml_get_version')
      false
    else
      # new struct in 0.2.5
      !have_type('yaml_anchors_t', 'yaml.h')
    end
  Logging.message((pkg ? "Use" : "Not use") + " packaged libyaml\n")
  $INCFLAGS, $LIBPATH, $libs = *save unless pkg
  !pkg
end
if bundle
  # Embed libyaml since we could not find it.

  $VPATH << "$(srcdir)/yaml"
  $INCFLAGS << " -I$(srcdir)/yaml"

  $srcs = Dir.glob("#{$srcdir}/{,yaml/}*.c").map {|n| File.basename(n)}.sort

  header = 'yaml/yaml.h'
  header = "{$(VPATH)}#{header}" if $nmake
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

create_makefile 'psych' do |mk|
  mk << "YAML_H = #{header}".strip << "\n"
end

# :startdoc:
