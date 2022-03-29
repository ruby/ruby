# -*- coding: us-ascii -*-
# frozen_string_literal: true
require 'mkmf'

if $mswin or $mingw or $cygwin
  $CPPFLAGS << " -DYAML_DECLARE_STATIC"
end

yaml_source = with_config("libyaml-source-dir") || enable_config("bundled-libyaml", false)
if yaml_source == true
  yaml_source = Dir.glob("#{$srcdir}/yaml{,-*}/").max_by {|n| File.basename(n).scan(/\d+/).map(&:to_i)}
  unless yaml_source
    require_relative '../../tool/extlibs.rb'
    extlibs = ExtLibs.new(cache_dir: File.expand_path("../../tmp/download_cache", $srcdir))
    unless extlibs.process_under($srcdir)
      raise "failed to download libyaml source"
    end
    yaml_source, = Dir.glob("#{$srcdir}/yaml-*/")
  end
elsif yaml_source
  yaml_source = yaml_source.gsub(/\$\((\w+)\)|\$\{(\w+)\}/) {ENV[$1||$2]}
end
if yaml_source
  yaml_configure = "#{File.expand_path(yaml_source)}/configure"
  unless File.exist?(yaml_configure)
    raise "Configure script not found in #{yaml_source.quote}"
  end

  puts("Configuring libyaml source in #{yaml_source.quote}")
  yaml = "libyaml"
  Dir.mkdir(yaml) unless File.directory?(yaml)
  unless system(yaml_configure, "-q",
                "--enable-#{$enable_shared || !$static ? 'shared' : 'static'}",
                *(["CFLAGS=-w"] if RbConfig::CONFIG["GCC"] == "yes"),
                chdir: yaml)
    raise "failed to configure libyaml"
  end
  Logging.message("libyaml configured\n")
  inc = yaml_source.start_with?("#$srcdir/") ? "$(srcdir)#{yaml_source[$srcdir.size..-1]}" : yaml_source
  $INCFLAGS << " -I#{yaml}/include -I#{inc}/include"
  Logging.message("INCLFAG=#$INCLFAG\n")
  libyaml = "#{yaml}/src/.libs/libyaml.#$LIBEXT"
  $LOCAL_LIBS.prepend("$(LIBYAML) ")
else
  pkg_config('yaml-0.1')
  dir_config('libyaml')
  unless find_header('yaml.h') && find_library('yaml', 'yaml_get_version')
    raise "libyaml not found"
  end
end

create_makefile 'psych' do |mk|
  mk << "LIBYAML = #{libyaml}".strip << "\n"
end

# :startdoc:
