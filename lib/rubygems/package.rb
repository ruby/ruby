# -*- coding: utf-8 -*-
# frozen_string_literal: true
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++
#
# Example using a Gem::Package
#
# Builds a .gem file given a Gem::Specification. A .gem file is a tarball
# which contains a data.tar.gz and metadata.gz, and possibly signatures.
#
#   require 'rubygems'
#   require 'rubygems/package'
#
#   spec = Gem::Specification.new do |s|
#     s.summary = "Ruby based make-like utility."
#     s.name = 'rake'
#     s.version = PKG_VERSION
#     s.requirements << 'none'
#     s.files = PKG_FILES
#     s.description = <<-EOF
#   Rake is a Make-like program implemented in Ruby. Tasks
#   and dependencies are specified in standard Ruby syntax.
#     EOF
#   end
#
#   Gem::Package.build spec
#
# Reads a .gem file.
#
#   require 'rubygems'
#   require 'rubygems/package'
#
#   the_gem = Gem::Package.new(path_to_dot_gem)
#   the_gem.contents # get the files in the gem
#   the_gem.extract_files destination_directory # extract the gem into a directory
#   the_gem.spec # get the spec out of the gem
#   the_gem.verify # check the gem is OK (contains valid gem specification, contains a not corrupt contents archive)
#
# #files are the files in the .gem tar file, not the Ruby files in the gem
# #extract_files and #contents automatically call #verify

require 'rubygems/security'
require 'rubygems/specification'
require 'rubygems/user_interaction'
require 'zlib'

class Gem::Package

  include Gem::UserInteraction

  class Error < Gem::Exception; end

  class FormatError < Error
    attr_reader :path

    def initialize message, source = nil
      if source
        @path = source.path

        message = message + " in #{path}" if path
      end

      super message
    end

  end

  class PathError < Error
    def initialize destination, destination_dir
      super "installing into parent path %s of %s is not allowed" %
              [destination, destination_dir]
    end
  end

  class NonSeekableIO < Error; end

  class TooLongFileName < Error; end

  ##
  # Raised when a tar file is corrupt

  class TarInvalidError < Error; end


  attr_accessor :build_time # :nodoc:

  ##
  # Checksums for the contents of the package

  attr_reader :checksums

  ##
  # The files in this package.  This is not the contents of the gem, just the
  # files in the top-level container.

  attr_reader :files

  ##
  # The security policy used for verifying the contents of this package.

  attr_accessor :security_policy

  ##
  # Sets the Gem::Specification to use to build this package.

  attr_writer :spec

  def self.build spec, skip_validation=false
    gem_file = spec.file_name

    package = new gem_file
    package.spec = spec
    package.build skip_validation

    gem_file
  end

  ##
  # Creates a new Gem::Package for the file at +gem+. +gem+ can also be
  # provided as an IO object.
  #
  # If +gem+ is an existing file in the old format a Gem::Package::Old will be
  # returned.

  def self.new gem, security_policy = nil
    gem = if gem.is_a?(Gem::Package::Source)
            gem
          elsif gem.respond_to? :read
            Gem::Package::IOSource.new gem
          else
            Gem::Package::FileSource.new gem
          end

    return super unless Gem::Package == self
    return super unless gem.present?

    return super unless gem.start
    return super unless gem.start.include? 'MD5SUM ='

    Gem::Package::Old.new gem
  end

  ##
  # Creates a new package that will read or write to the file +gem+.

  def initialize gem, security_policy # :notnew:
    @gem = gem

    @build_time      = Time.now
    @checksums       = {}
    @contents        = nil
    @digests         = Hash.new { |h, algorithm| h[algorithm] = {} }
    @files           = nil
    @security_policy = security_policy
    @signatures      = {}
    @signer          = nil
    @spec            = nil
  end

  ##
  # Copies this package to +path+ (if possible)

  def copy_to path
    FileUtils.cp @gem.path, path unless File.exist? path
  end

  ##
  # Adds a checksum for each entry in the gem to checksums.yaml.gz.

  def add_checksums tar
    Gem.load_yaml

    checksums_by_algorithm = Hash.new { |h, algorithm| h[algorithm] = {} }

    @checksums.each do |name, digests|
      digests.each do |algorithm, digest|
        checksums_by_algorithm[algorithm][name] = digest.hexdigest
      end
    end

    tar.add_file_signed 'checksums.yaml.gz', 0444, @signer do |io|
      gzip_to io do |gz_io|
        YAML.dump checksums_by_algorithm, gz_io
      end
    end
  end

  ##
  # Adds the files listed in the packages's Gem::Specification to data.tar.gz
  # and adds this file to the +tar+.

  def add_contents tar # :nodoc:
    digests = tar.add_file_signed 'data.tar.gz', 0444, @signer do |io|
      gzip_to io do |gz_io|
        Gem::Package::TarWriter.new gz_io do |data_tar|
          add_files data_tar
        end
      end
    end

    @checksums['data.tar.gz'] = digests
  end

  ##
  # Adds files included the package's Gem::Specification to the +tar+ file

  def add_files tar # :nodoc:
    @spec.files.each do |file|
      stat = File.lstat file

      if stat.symlink?
        relative_dir = File.dirname(file).sub("#{Dir.pwd}/", '')
        target_path = File.join(relative_dir, File.readlink(file))
        tar.add_symlink file, target_path, stat.mode
      end

      next unless stat.file?

      tar.add_file_simple file, stat.mode, stat.size do |dst_io|
        open file, 'rb' do |src_io|
          dst_io.write src_io.read 16384 until src_io.eof?
        end
      end
    end
  end

  ##
  # Adds the package's Gem::Specification to the +tar+ file

  def add_metadata tar # :nodoc:
    digests = tar.add_file_signed 'metadata.gz', 0444, @signer do |io|
      gzip_to io do |gz_io|
        gz_io.write @spec.to_yaml
      end
    end

    @checksums['metadata.gz'] = digests
  end

  ##
  # Builds this package based on the specification set by #spec=

  def build skip_validation = false
    Gem.load_yaml
    require 'rubygems/security'

    @spec.mark_version
    @spec.validate unless skip_validation

    setup_signer

    @gem.with_write_io do |gem_io|
      Gem::Package::TarWriter.new gem_io do |gem|
        add_metadata gem
        add_contents gem
        add_checksums gem
      end
    end

    say <<-EOM
  Successfully built RubyGem
  Name: #{@spec.name}
  Version: #{@spec.version}
  File: #{File.basename @spec.cache_file}
EOM
  ensure
    @signer = nil
  end

  ##
  # A list of file names contained in this gem

  def contents
    return @contents if @contents

    verify unless @spec

    @contents = []

    @gem.with_read_io do |io|
      gem_tar = Gem::Package::TarReader.new io

      gem_tar.each do |entry|
        next unless entry.full_name == 'data.tar.gz'

        open_tar_gz entry do |pkg_tar|
          pkg_tar.each do |contents_entry|
            @contents << contents_entry.full_name
          end
        end

        return @contents
      end
    end
  end

  ##
  # Creates a digest of the TarEntry +entry+ from the digest algorithm set by
  # the security policy.

  def digest entry # :nodoc:
    algorithms = if @checksums then
                   @checksums.keys
                 else
                   [Gem::Security::DIGEST_NAME].compact
                 end

    algorithms.each do |algorithm|
      digester =
        if defined?(OpenSSL::Digest) then
          OpenSSL::Digest.new algorithm
        else
          Digest.const_get(algorithm).new
        end

      digester << entry.read(16384) until entry.eof?

      entry.rewind

      @digests[algorithm][entry.full_name] = digester
    end

    @digests
  end

  ##
  # Extracts the files in this package into +destination_dir+
  #
  # If +pattern+ is specified, only entries matching that glob will be
  # extracted.

  def extract_files destination_dir, pattern = "*"
    verify unless @spec

    FileUtils.mkdir_p destination_dir

    @gem.with_read_io do |io|
      reader = Gem::Package::TarReader.new io

      reader.each do |entry|
        next unless entry.full_name == 'data.tar.gz'

        extract_tar_gz entry, destination_dir, pattern

        return # ignore further entries
      end
    end
  end

  ##
  # Extracts all the files in the gzipped tar archive +io+ into
  # +destination_dir+.
  #
  # If an entry in the archive contains a relative path above
  # +destination_dir+ or an absolute path is encountered an exception is
  # raised.
  #
  # If +pattern+ is specified, only entries matching that glob will be
  # extracted.

  def extract_tar_gz io, destination_dir, pattern = "*" # :nodoc:
    open_tar_gz io do |tar|
      tar.each do |entry|
        next unless File.fnmatch pattern, entry.full_name, File::FNM_DOTMATCH

        destination = install_location entry.full_name, destination_dir

        FileUtils.rm_rf destination

        mkdir_options = {}
        mkdir_options[:mode] = entry.header.mode if entry.directory?
        mkdir =
          if entry.directory? then
            destination
          else
            File.dirname destination
          end

        FileUtils.mkdir_p mkdir, mkdir_options

        open destination, 'wb' do |out|
          out.write entry.read
          FileUtils.chmod entry.header.mode, destination
        end if entry.file?

        File.symlink(entry.header.linkname, destination) if entry.symlink?

        verbose destination
      end
    end
  end

  ##
  # Gzips content written to +gz_io+ to +io+.
  #--
  # Also sets the gzip modification time to the package build time to ease
  # testing.

  def gzip_to io # :yields: gz_io
    gz_io = Zlib::GzipWriter.new io, Zlib::BEST_COMPRESSION
    gz_io.mtime = @build_time

    yield gz_io
  ensure
    gz_io.close
  end

  ##
  # Returns the full path for installing +filename+.
  #
  # If +filename+ is not inside +destination_dir+ an exception is raised.

  def install_location filename, destination_dir # :nodoc:
    raise Gem::Package::PathError.new(filename, destination_dir) if
      filename.start_with? '/'

    destination_dir = File.realpath destination_dir if
      File.respond_to? :realpath
    destination_dir = File.expand_path destination_dir

    destination = File.join destination_dir, filename
    destination = File.expand_path destination

    raise Gem::Package::PathError.new(destination, destination_dir) unless
      destination.start_with? destination_dir

    destination.untaint
    destination
  end

  ##
  # Loads a Gem::Specification from the TarEntry +entry+

  def load_spec entry # :nodoc:
    case entry.full_name
    when 'metadata' then
      @spec = Gem::Specification.from_yaml entry.read
    when 'metadata.gz' then
      args = [entry]
      args << { :external_encoding => Encoding::UTF_8 } if
        Object.const_defined?(:Encoding) &&
          Zlib::GzipReader.method(:wrap).arity != 1

      Zlib::GzipReader.wrap(*args) do |gzio|
        @spec = Gem::Specification.from_yaml gzio.read
      end
    end
  end

  ##
  # Opens +io+ as a gzipped tar archive

  def open_tar_gz io # :nodoc:
    Zlib::GzipReader.wrap io do |gzio|
      tar = Gem::Package::TarReader.new gzio

      yield tar
    end
  end

  ##
  # Reads and loads checksums.yaml.gz from the tar file +gem+

  def read_checksums gem
    Gem.load_yaml

    @checksums = gem.seek 'checksums.yaml.gz' do |entry|
      Zlib::GzipReader.wrap entry do |gz_io|
        Gem::SafeYAML.safe_load gz_io.read
      end
    end
  end

  ##
  # Prepares the gem for signing and checksum generation.  If a signing
  # certificate and key are not present only checksum generation is set up.

  def setup_signer
    passphrase = ENV['GEM_PRIVATE_KEY_PASSPHRASE']
    if @spec.signing_key then
      @signer = Gem::Security::Signer.new @spec.signing_key, @spec.cert_chain, passphrase
      @spec.signing_key = nil
      @spec.cert_chain = @signer.cert_chain.map { |cert| cert.to_s }
    else
      @signer = Gem::Security::Signer.new nil, nil, passphrase
      @spec.cert_chain = @signer.cert_chain.map { |cert| cert.to_pem } if
        @signer.cert_chain
    end
  end

  ##
  # The spec for this gem.
  #
  # If this is a package for a built gem the spec is loaded from the
  # gem and returned.  If this is a package for a gem being built the provided
  # spec is returned.

  def spec
    verify unless @spec

    @spec
  end

  ##
  # Verifies that this gem:
  #
  # * Contains a valid gem specification
  # * Contains a contents archive
  # * The contents archive is not corrupt
  #
  # After verification the gem specification from the gem is available from
  # #spec

  def verify
    @files     = []
    @spec      = nil

    @gem.with_read_io do |io|
      Gem::Package::TarReader.new io do |reader|
        read_checksums reader

        verify_files reader
      end
    end

    verify_checksums @digests, @checksums

    @security_policy.verify_signatures @spec, @digests, @signatures if
      @security_policy

    true
  rescue Gem::Security::Exception
    @spec = nil
    @files = []
    raise
  rescue Errno::ENOENT => e
    raise Gem::Package::FormatError.new e.message
  rescue Gem::Package::TarInvalidError => e
    raise Gem::Package::FormatError.new e.message, @gem
  end

  ##
  # Verifies the +checksums+ against the +digests+.  This check is not
  # cryptographically secure.  Missing checksums are ignored.

  def verify_checksums digests, checksums # :nodoc:
    return unless checksums

    checksums.sort.each do |algorithm, gem_digests|
      gem_digests.sort.each do |file_name, gem_hexdigest|
        computed_digest = digests[algorithm][file_name]

        unless computed_digest.hexdigest == gem_hexdigest then
          raise Gem::Package::FormatError.new \
            "#{algorithm} checksum mismatch for #{file_name}", @gem
        end
      end
    end
  end

  ##
  # Verifies +entry+ in a .gem file.

  def verify_entry entry
    file_name = entry.full_name
    @files << file_name

    case file_name
    when /\.sig$/ then
      @signatures[$`] = entry.read if @security_policy
      return
    else
      digest entry
    end

    case file_name
    when /^metadata(.gz)?$/ then
      load_spec entry
    when 'data.tar.gz' then
      verify_gz entry
    end
  rescue => e
    message = "package is corrupt, exception while verifying: " +
              "#{e.message} (#{e.class})"
    raise Gem::Package::FormatError.new message, @gem
  end

  ##
  # Verifies the files of the +gem+

  def verify_files gem
    gem.each do |entry|
      verify_entry entry
    end

    unless @spec then
      raise Gem::Package::FormatError.new 'package metadata is missing', @gem
    end

    unless @files.include? 'data.tar.gz' then
      raise Gem::Package::FormatError.new \
              'package content (data.tar.gz) is missing', @gem
    end
  end

  ##
  # Verifies that +entry+ is a valid gzipped file.

  def verify_gz entry # :nodoc:
    Zlib::GzipReader.wrap entry do |gzio|
      gzio.read 16384 until gzio.eof? # gzip checksum verification
    end
  rescue Zlib::GzipFile::Error => e
    raise Gem::Package::FormatError.new(e.message, entry.full_name)
  end

end

require 'rubygems/package/digest_io'
require 'rubygems/package/source'
require 'rubygems/package/file_source'
require 'rubygems/package/io_source'
require 'rubygems/package/old'
require 'rubygems/package/tar_header'
require 'rubygems/package/tar_reader'
require 'rubygems/package/tar_reader/entry'
require 'rubygems/package/tar_writer'
