#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module Gem

  ##
  # The Builder class processes RubyGem specification files
  # to produce a .gem file.
  #
  class Builder
  
    include UserInteraction
    ##
    # Constructs a builder instance for the provided specification
    #
    # spec:: [Gem::Specification] The specification instance
    #
    def initialize(spec)
      require "yaml"
      require "rubygems/package"
      require "rubygems/security"

      @spec = spec
    end

    ##
    # Builds the gem from the specification.  Returns the name of the file
    # written.
    #
    def build
      @spec.mark_version
      @spec.validate
      @signer = sign
      write_package
      say success
      @spec.file_name
    end
    
    def success
      <<-EOM
  Successfully built RubyGem
  Name: #{@spec.name}
  Version: #{@spec.version}
  File: #{@spec.full_name+'.gem'}
EOM
    end

    private

    def sign
      # if the signing key was specified, then load the file, and swap
      # to the public key (TODO: we should probably just omit the
      # signing key in favor of the signing certificate, but that's for
      # the future, also the signature algorithm should be configurable)
      signer = nil
      if @spec.respond_to?(:signing_key) && @spec.signing_key
        signer = Gem::Security::Signer.new(@spec.signing_key, @spec.cert_chain)
        @spec.signing_key = nil
        @spec.cert_chain = signer.cert_chain.map { |cert| cert.to_s }
      end
      signer
    end

    def write_package
      open @spec.file_name, 'wb' do |gem_io|
        Gem::Package.open gem_io, 'w', @signer do |pkg|
          pkg.metadata = @spec.to_yaml

          @spec.files.each do |file|
            next if File.directory? file

            stat = File.stat file
            mode = stat.mode & 0777
            size = stat.size

            pkg.add_file_simple file, mode, size do |tar_io|
              tar_io.write open(file, "rb") { |f| f.read }
            end
          end
        end
      end
    end
  end
end

