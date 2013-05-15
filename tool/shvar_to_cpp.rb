#!/usr/bin/ruby

require './rbconfig'
C = RbConfig::MAKEFILE_CONFIG.dup
C["ruby_version"] = '"RUBY_LIB_VERSION"'
C["arch"] = '"arch"'
C["sitearch"] = '"arch"'
C["vendorarchdir"] = '"RUBY_VENDOR_ARCH_LIB"'
C["sitearchdir"] = '"RUBY_SITE_ARCH_LIB"'
C["vendorlibdir"] = '"RUBY_VENDOR_LIB2"'
C["sitelibdir"] = '"RUBY_SITE_LIB2"'
C["vendordir"] = '"RUBY_VENDOR_LIB"'
C["sitedir"] = '"RUBY_SITE_LIB"'
C["rubylibdir"] = '"RUBY_LIB"'
C["rubylibprefix"] = '"RUBY_LIB_PREFIX"'
C["rubyarchprefix"] = '"RUBY_ARCH_PREFIX_FOR(arch)"'
C["rubysitearchprefix"] = '"RUBY_SITEARCH_PREFIX_FOR(arch)"'
C["exec_prefix"] = '"RUBY_EXEC_PREFIX"'

verconf = File.read(ARGV[0])
verconf.gsub!(/^(#define\s+\S+\s+)(.*)/) {
  $1 + RbConfig.expand($2, C).gsub(/^""(?!$)|(.)""$/, '\1')
}

puts verconf
