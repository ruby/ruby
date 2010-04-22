# -*- coding: utf-8 -*-
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++

require 'fileutils'
require 'find'
require 'stringio'
require 'yaml'
require 'zlib'

require 'rubygems/security'
require 'rubygems/specification'

##
# Wrapper for FileUtils meant to provide logging and additional operations if
# needed.

class Gem::FileOperations

  def initialize(logger = nil)
    @logger = logger
  end

  def method_missing(meth, *args, &block)
    case
    when FileUtils.respond_to?(meth)
      @logger.log "#{meth}: #{args}" if @logger
      FileUtils.send meth, *args, &block
    when Gem::FileOperations.respond_to?(meth)
      @logger.log "#{meth}: #{args}" if @logger
      Gem::FileOperations.send meth, *args, &block
    else
      super
    end
  end

end

module Gem::Package

  class Error < StandardError; end
  class NonSeekableIO < Error; end
  class ClosedIO < Error; end
  class BadCheckSum < Error; end
  class TooLongFileName < Error; end
  class FormatError < Error; end

  def self.open(io, mode = "r", signer = nil, &block)
    tar_type = case mode
               when 'r' then TarInput
               when 'w' then TarOutput
               else
                 raise "Unknown Package open mode"
               end

    tar_type.open(io, signer, &block)
  end

  def self.pack(src, destname, signer = nil)
    TarOutput.open(destname, signer) do |outp|
      dir_class.chdir(src) do
        outp.metadata = (file_class.read("RPA/metadata") rescue nil)
        find_class.find('.') do |entry|
          case
          when file_class.file?(entry)
            entry.sub!(%r{\./}, "")
            next if entry =~ /\ARPA\//
            stat = File.stat(entry)
            outp.add_file_simple(entry, stat.mode, stat.size) do |os|
              file_class.open(entry, "rb") do |f|
                os.write(f.read(4096)) until f.eof?
              end
            end
          when file_class.dir?(entry)
            entry.sub!(%r{\./}, "")
            next if entry == "RPA"
            outp.mkdir(entry, file_class.stat(entry).mode)
          else
            raise "Don't know how to pack this yet!"
          end
        end
      end
    end
  end

end

require 'rubygems/package/f_sync_dir'
require 'rubygems/package/tar_header'
require 'rubygems/package/tar_input'
require 'rubygems/package/tar_output'
require 'rubygems/package/tar_reader'
require 'rubygems/package/tar_reader/entry'
require 'rubygems/package/tar_writer'

