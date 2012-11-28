require 'mkmf'
require 'fileutils'

# :stopdoc:

dir_config 'libyaml'

unless find_header('yaml.h') && find_library('yaml', 'yaml_get_version')
  # Embed libyaml since we could not find it.

  srcdir = File.expand_path File.dirname __FILE__
  files = Dir.chdir File.join(srcdir, 'yaml') do
    Dir.entries(Dir.pwd).find_all { |f|
      File.file?(f) && File.extname(f) =~ /^\.[hc]/
    }.map { |f| File.expand_path f }
  end

  FileUtils.cp_r files, srcdir

  if $mswin
    $CFLAGS += " -DYAML_DECLARE_STATIC -DHAVE_CONFIG_H"
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
