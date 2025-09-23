# -*- coding: us-ascii -*-
# frozen_string_literal: true
require 'mkmf'

if $mswin or $mingw or $cygwin
  $CPPFLAGS << " -DYAML_DECLARE_STATIC"
end

yaml_source = with_config("libyaml-source-dir")
if yaml_source
  yaml_source = yaml_source.gsub(/\$\((\w+)\)|\$\{(\w+)\}/) {ENV[$1||$2]}
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
    "--host=#{RbConfig::CONFIG['host'].sub(/-unknown-/, '-').sub(/arm64/, 'arm')}",
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

  # default to pre-installed libyaml
elsif pkg_config('yaml-0.1')
  # found with pkg-config
else
  dir_config('libyaml')
  find_header('yaml.h') or abort "yaml.h not found"
  find_library('yaml', 'yaml_get_version') or abort "libyaml not found"
end

create_makefile 'psych' do |mk|
  mk << "LIBYAML = #{libyaml}".strip << "\n"
  mk << "LIBYAML_OBJDIR = libyaml/src#{shared ? '/.libs' : ''}\n"
  mk << "OBJEXT = #$OBJEXT"
  mk << "RANLIB = #{config_string('RANLIB') || config_string('NULLCMD')}\n"
end

# :startdoc:
