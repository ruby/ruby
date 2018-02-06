# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/package'
require 'rubygems/installer'

##
# Validator performs various gem file and gem database validation

class Gem::Validator

  include Gem::UserInteraction

  def initialize # :nodoc:
    require 'find'
  end

  ##
  # Given a gem file's contents, validates against its own MD5 checksum
  # gem_data:: [String] Contents of the gem file

  def verify_gem(gem_data)
    # TODO remove me? The code here only validate an MD5SUM that was
    # in some old formatted gems, but hasn't been for a long time.
  end

  ##
  # Given the path to a gem file, validates against its own MD5 checksum
  #
  # gem_path:: [String] Path to gem file

  def verify_gem_file(gem_path)
    File.open gem_path, Gem.binary_mode do |file|
      gem_data = file.read
      verify_gem gem_data
    end
  rescue Errno::ENOENT, Errno::EINVAL
    raise Gem::VerificationError, "missing gem file #{gem_path}"
  end

  private

  def find_files_for_gem(gem_directory)
    installed_files = []

    Find.find gem_directory do |file_name|
      fn = file_name[gem_directory.size..file_name.size-1].sub(/^\//, "")
      installed_files << fn unless
        fn =~ /CVS/ || fn.empty? || File.directory?(file_name)
    end

    installed_files
  end

  public

  ##
  # Describes a problem with a file in a gem.

  ErrorData = Struct.new :path, :problem do
    def <=> other # :nodoc:
      return nil unless self.class === other

      [path, problem] <=> [other.path, other.problem]
    end
  end

  ##
  # Checks the gem directory for the following potential
  # inconsistencies/problems:
  #
  # * Checksum gem itself
  # * For each file in each gem, check consistency of installed versions
  # * Check for files that aren't part of the gem but are in the gems directory
  # * 1 cache - 1 spec - 1 directory.
  #
  # returns a hash of ErrorData objects, keyed on the problem gem's name.
  #--
  # TODO needs further cleanup

  def alien(gems=[])
    errors = Hash.new { |h,k| h[k] = {} }

    Gem::Specification.each do |spec|
      next unless gems.include? spec.name unless gems.empty?
      next if spec.default_gem?

      gem_name      = spec.file_name
      gem_path      = spec.cache_file
      spec_path     = spec.spec_file
      gem_directory = spec.full_gem_path

      unless File.directory? gem_directory then
        errors[gem_name][spec.full_name] =
          "Gem registered but doesn't exist at #{gem_directory}"
        next
      end

      unless File.exist? spec_path then
        errors[gem_name][spec_path] = "Spec file missing for installed gem"
      end

      begin
        verify_gem_file(gem_path)

        good, gone, unreadable = nil, nil, nil, nil

        File.open gem_path, Gem.binary_mode do |file|
          package = Gem::Package.new gem_path

          good, gone = package.contents.partition { |file_name|
            File.exist? File.join(gem_directory, file_name)
          }

          gone.sort.each do |path|
            errors[gem_name][path] = "Missing file"
          end

          good, unreadable = good.partition { |file_name|
            File.readable? File.join(gem_directory, file_name)
          }

          unreadable.sort.each do |path|
            errors[gem_name][path] = "Unreadable file"
          end

          good.each do |entry, data|
            begin
              next unless data # HACK `gem check -a mkrf`

              source = File.join gem_directory, entry['path']

              File.open source, Gem.binary_mode do |f|
                unless f.read == data then
                  errors[gem_name][entry['path']] = "Modified from original"
                end
              end
            end
          end
        end

        installed_files = find_files_for_gem(gem_directory)
        extras = installed_files - good - unreadable

        extras.each do |extra|
          errors[gem_name][extra] = "Extra file"
        end
      rescue Gem::VerificationError => e
        errors[gem_name][gem_path] = e.message
      end
    end

    errors.each do |name, subhash|
      errors[name] = subhash.map do |path, msg|
        ErrorData.new path, msg
      end.sort
    end

    errors
  end
end

