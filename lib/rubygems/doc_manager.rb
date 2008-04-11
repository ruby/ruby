#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'

module Gem

  class DocManager
  
    include UserInteraction
  
    # Create a document manager for the given gem spec.
    #
    # spec::      The Gem::Specification object representing the gem.
    # rdoc_args:: Optional arguments for RDoc (template etc.) as a String.
    #
    def initialize(spec, rdoc_args="")
      @spec = spec
      @doc_dir = File.join(spec.installation_path, "doc", spec.full_name)
      @rdoc_args = rdoc_args.nil? ? [] : rdoc_args.split
    end
    
    # Is the RDoc documentation installed?
    def rdoc_installed?
      return File.exist?(File.join(@doc_dir, "rdoc"))
    end
    
    # Generate the RI documents for this gem spec.
    #
    # Note that if both RI and RDoc documents are generated from the
    # same process, the RI docs should be done first (a likely bug in
    # RDoc will cause RI docs generation to fail if run after RDoc).
    def generate_ri
      if @spec.has_rdoc then
        load_rdoc
        install_ri # RDoc bug, ri goes first
      end

      FileUtils.mkdir_p @doc_dir unless File.exist?(@doc_dir)
    end

    # Generate the RDoc documents for this gem spec.
    #
    # Note that if both RI and RDoc documents are generated from the
    # same process, the RI docs should be done first (a likely bug in
    # RDoc will cause RI docs generation to fail if run after RDoc).
    def generate_rdoc
      if @spec.has_rdoc then
        load_rdoc
        install_rdoc
      end

      FileUtils.mkdir_p @doc_dir unless File.exist?(@doc_dir)
    end

    # Load the RDoc documentation generator library.
    def load_rdoc
      if File.exist?(@doc_dir) && !File.writable?(@doc_dir) then
        raise Gem::FilePermissionError.new(@doc_dir)
      end

      FileUtils.mkdir_p @doc_dir unless File.exist?(@doc_dir)

      begin
        gem 'rdoc'
      rescue Gem::LoadError
        # use built-in RDoc
      end

      begin
        require 'rdoc/rdoc'
      rescue LoadError => e
        raise Gem::DocumentError,
          "ERROR: RDoc documentation generator not installed!"
      end
    end

    def install_rdoc
      rdoc_dir = File.join @doc_dir, 'rdoc'

      FileUtils.rm_rf rdoc_dir

      say "Installing RDoc documentation for #{@spec.full_name}..."
      run_rdoc '--op', rdoc_dir
    end

    def install_ri
      ri_dir = File.join @doc_dir, 'ri'

      FileUtils.rm_rf ri_dir

      say "Installing ri documentation for #{@spec.full_name}..."
      run_rdoc '--ri', '--op', ri_dir
    end

    def run_rdoc(*args)
      args << @spec.rdoc_options
      args << DocManager.configured_args
      args << '--quiet'
      args << @spec.require_paths.clone
      args << @spec.extra_rdoc_files
      args.flatten!

      r = RDoc::RDoc.new

      old_pwd = Dir.pwd
      Dir.chdir(@spec.full_gem_path)
      begin
        r.document args
      rescue Errno::EACCES => e
        dirname = File.dirname e.message.split("-")[1].strip
        raise Gem::FilePermissionError.new(dirname)
      rescue RuntimeError => ex
        alert_error "While generating documentation for #{@spec.full_name}"
        ui.errs.puts "... MESSAGE:   #{ex}"
        ui.errs.puts "... RDOC args: #{args.join(' ')}"
        ui.errs.puts "\t#{ex.backtrace.join "\n\t"}" if
          Gem.configuration.backtrace
        ui.errs.puts "(continuing with the rest of the installation)"
      ensure
        Dir.chdir(old_pwd)
      end
    end

    def uninstall_doc
      raise Gem::FilePermissionError.new(@spec.installation_path) unless
        File.writable? @spec.installation_path

      original_name = [
        @spec.name, @spec.version, @spec.original_platform].join '-'

      doc_dir = File.join @spec.installation_path, 'doc', @spec.full_name
      unless File.directory? doc_dir then
        doc_dir = File.join @spec.installation_path, 'doc', original_name
      end

      FileUtils.rm_rf doc_dir

      ri_dir = File.join @spec.installation_path, 'ri', @spec.full_name

      unless File.directory? ri_dir then
        ri_dir = File.join @spec.installation_path, 'ri', original_name
      end

      FileUtils.rm_rf ri_dir
    end

    class << self
      def configured_args
        @configured_args ||= []
      end

      def configured_args=(args)
        case args
        when Array
          @configured_args = args
        when String
          @configured_args = args.split
        end
      end
    end
    
  end
end
