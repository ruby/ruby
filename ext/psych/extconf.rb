# -*- coding: us-ascii -*-
# frozen_string_literal: true
require 'mkmf'

if $mswin or $mingw or $cygwin
  $CPPFLAGS << " -DYAML_DECLARE_STATIC"
end

yaml_source = with_config("libyaml-source-dir") || enable_config("bundled-libyaml", false)
unless yaml_source # default to pre-installed libyaml
  pkg_config('yaml-0.1')
  dir_config('libyaml')
  unless find_header('yaml.h') && find_library('yaml', 'yaml_get_version')
    yaml_source = true # fallback to the bundled source if exists
  end
end

if yaml_source == true
  # search the latest libyaml source under $srcdir
  yaml_source = Dir.glob("#{$srcdir}/yaml{,-*}/").max_by {|n| File.basename(n).scan(/\d+/).map(&:to_i)}
  unless yaml_source
    download_failure = "failed to download libyaml source. Try manually installing libyaml?"
    begin
      require_relative '../../tool/extlibs.rb'
    rescue LoadError
      # When running in ruby/ruby, we use miniruby and don't have stdlib.
      # Avoid LoadError because it aborts the whole build. Usually when
      # stdlib extension fail to configure we skip it and continue.
      raise download_failure
    end
    extlibs = ExtLibs.new(cache_dir: File.expand_path("../../tmp/download_cache", $srcdir))
    unless extlibs.process_under($srcdir)
      raise download_failure
    end
    yaml_source, = Dir.glob("#{$srcdir}/yaml-*/")
    raise "libyaml not found" unless yaml_source
  end
elsif yaml_source
  yaml_source = yaml_source.gsub(/\$\((\w+)\)|\$\{(\w+)\}/) {ENV[$1||$2]}
end
if yaml_source
  yaml_source = yaml_source.chomp("/")
  yaml_configure = "#{File.expand_path(yaml_source)}/configure"
  unless File.exist?(yaml_configure)
    raise "Configure script not found in #{yaml_source.quote}"
  end

  puts("Configuring libyaml source in #{yaml_source.quote}")
  yaml = "libyaml"
  Dir.mkdir(yaml) unless File.directory?(yaml)
  shared = $enable_shared || !$static
  args = [
    yaml_configure,
    "--enable-#{shared ? 'shared' : 'static'}",
    "--host=#{RbConfig::CONFIG['host'].sub(/-unknown-/, '-')}",
    "CC=#{RbConfig::CONFIG['CC']}",
    *(["CFLAGS=-w"] if RbConfig::CONFIG["GCC"] == "yes"),
  ]
  puts(args.quote.join(' '))
  unless system(*args, chdir: yaml)
    raise "failed to configure libyaml"
  end
  inc = yaml_source.start_with?("#$srcdir/") ? "$(srcdir)#{yaml_source[$srcdir.size..-1]}" : yaml_source
  $INCFLAGS << " -I#{yaml}/include -I#{inc}/include"
  puts("INCFLAGS=#$INCFLAGS")
  libyaml = "libyaml.#$LIBEXT"
  $cleanfiles << libyaml
  $LOCAL_LIBS.prepend("$(LIBYAML) ")
end

create_makefile 'psych' do |mk|
  mk << "LIBYAML = #{libyaml}".strip << "\n"
  mk << "LIBYAML_OBJDIR = libyaml/src#{shared ? '/.libs' : ''}\n"
  mk << "OBJEXT = #$OBJEXT"
  mk << "RANLIB = #{config_string('RANLIB') || config_string('NULLCMD')}\n"
end

# :startdoc:
