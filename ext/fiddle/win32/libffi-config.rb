#!/usr/bin/ruby
# frozen_string_literal: true
require 'fileutils'

basedir = File.dirname(__FILE__)
conf = {}
enable = {}
until ARGV.empty?
  arg = ARGV.shift
  case arg
  when '-C'
    # ignore
  when /\A--srcdir=(.*)/
    conf['SRCDIR'] = srcdir = $1
  when /\A(CC|CFLAGS|CXX|CXXFLAGS|LD|LDFLAGS)=(.*)/
    conf[$1] = $2
  when /\A--host=(.*)/
    host = $1
  when /\A--enable-([^=]+)(?:=(.*))?/
    enable[$1] = $2 || true
  when /\A--disable-([^=]+)/
    enable[$1] = false
  end
end

IO.foreach("#{srcdir}/configure.ac") do |line|
  if /^AC_INIT\((.*)\)/ =~ line
    version = $1.split(/,\s*/)[1]
    version.gsub!(/\A\[|\]\z/, '')
    conf['VERSION'] = version
    break
  end
end

builddir = srcdir == "." ? (enable['builddir'] || ".") : "."
conf['TARGET'] = /^x64/ =~ host ? "X86_WIN64" : "X86_WIN32"

FileUtils.mkdir_p([builddir, "#{builddir}/include", "#{builddir}/src/x86"])
FileUtils.cp("#{basedir}/fficonfig.h", ".", preserve: true)

hdr = IO.binread("#{srcdir}/include/ffi.h.in")
hdr.gsub!(/@(\w+)@/) {conf[$1] || $&}
hdr.gsub!(/^(#if\s+)@\w+@/, '\10')
IO.binwrite("#{builddir}/include/ffi.h", hdr)

mk = IO.binread("#{basedir}/libffi.mk.tmpl")
mk.gsub!(/@(\w+)@/) {conf[$1] || $&}
IO.binwrite("Makefile", mk)
