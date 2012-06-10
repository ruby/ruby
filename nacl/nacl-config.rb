#!/usr/bin/ruby
#
# Copyright:: Copyright 2012 Google Inc.
# License:: All Rights Reserved.
# Original Author:: Yugui Sonoda (mailto:yugui@google.com)
#
# Convenient functions/constants for native client specific configurations.
require 'rbconfig'

module NaClConfig
  config = RbConfig::CONFIG

  cpu_nick = config['host_alias'].sub(/-gnu$|-newlib$/, '').sub(/-nacl$/, '').sub(/i.86/, 'x86_32')
  ARCH = cpu_nick.sub('x86_64', 'x86-64').sub('x86_32', 'x86-32')
  HOST = ARCH.sub(/x86-../, 'x86_64') + '-nacl'

  lib_suffix = config['host_cpu'][/i.86/] ? '32' : ''
  PYTHON = config['PYTHON']
  OBJDUMP = config['OBJDUMP']
  SDK_ROOT = config['NACL_SDK_ROOT']
  CREATE_NMF = [
    File.join(SDK_ROOT, 'build_tools', 'nacl_sdk_scons', 'site_tools', 'create_nmf.py'),
    File.join(SDK_ROOT, 'tools', 'create_nmf.py')
  ].find{|path| File.exist?(path) } or raise "No create_nmf found"
  HOST_LIB = File.join(SDK_ROOT, 'toolchain', config['NACL_TOOLCHAIN'], HOST, "lib#{lib_suffix}")

  INSTALL_PROGRAM = config['INSTALL_PROGRAM']
  INSTALL_LIBRARY = config['INSTALL_DATA']

  SEL_LDR = [
    File.join(SDK_ROOT, 'toolchain', config['NACL_TOOLCHAIN'], 'bin', "sel_ldr_#{cpu_nick}"),
    File.join(SDK_ROOT, 'tools', "sel_ldr_#{cpu_nick}")
  ].find{|path| File.executable?(path)} or raise "No sel_ldr found"
  IRT_CORE = [
    File.join(SDK_ROOT, 'toolchain', config['NACL_TOOLCHAIN'], 'bin', "irt_core_#{cpu_nick}.nexe"),
    File.join(SDK_ROOT, 'tools', "irt_core_#{cpu_nick}.nexe")
  ].find{|path| File.executable?(path)} or raise "No irt_core found"
  RUNNABLE_LD = File.join(HOST_LIB, 'runnable-ld.so')

  module_function

  def newlib?
    RbConfig::CONFIG['NACL_SDK_VARIANT'] == 'newlib'
  end

  def self.config(name)
    if NaClConfig::const_defined?(name.upcase)
      NaClConfig::const_get(name.upcase)
    elsif NaClConfig::respond_to?(name) and NaClConfig::method(name).arity == 0
      NaClConfig::send(name)
    else
      raise ArgumentError, "No such config: #{name}"
    end
  end
end

if $0 == __FILE__
  ARGV.each do |arg|
    puts NaClConfig::config(arg)
  end
end
