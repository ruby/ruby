#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'

require 'rubygems/package'

module Gem

  ##
  # The format class knows the guts of the RubyGem .gem file format
  # and provides the capability to read gem files
  #
  class Format
    attr_accessor :spec, :file_entries, :gem_path
    extend Gem::UserInteraction
  
    ##
    # Constructs an instance of a Format object, representing the gem's
    # data structure.
    #
    # gem:: [String] The file name of the gem
    #
    def initialize(gem_path)
      @gem_path = gem_path
    end
    
    ##
    # Reads the named gem file and returns a Format object, representing 
    # the data from the gem file
    #
    # file_path:: [String] Path to the gem file
    #
    def self.from_file_by_path(file_path, security_policy = nil)
      format = nil

      unless File.exist?(file_path)
        raise Gem::Exception, "Cannot load gem at [#{file_path}] in #{Dir.pwd}"
      end

      # check for old version gem
      if File.read(file_path, 20).include?("MD5SUM =")
        require 'rubygems/old_format'

        format = OldFormat.from_file_by_path(file_path)
      else
        open file_path, Gem.binary_mode do |io|
          format = from_io io, file_path, security_policy
        end
      end

      return format
    end

    ##
    # Reads a gem from an io stream and returns a Format object, representing
    # the data from the gem file
    #
    # io:: [IO] Stream from which to read the gem
    #
    def self.from_io(io, gem_path="(io)", security_policy = nil)
      format = new gem_path

      Package.open io, 'r', security_policy do |pkg|
        format.spec = pkg.metadata
        format.file_entries = []

        pkg.each do |entry|
          size = entry.header.size
          mode = entry.header.mode

          format.file_entries << [{
              "size" => size, "mode" => mode, "path" => entry.full_name,
            },
            entry.read
          ]
        end
      end

      format
    end

  end
end
