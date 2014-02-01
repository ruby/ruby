require 'rubygems'
require 'rubygems/user_interaction'
require 'fileutils'

begin
  gem 'rdoc'
rescue Gem::LoadError
  # swallow
else
  # This will force any deps that 'rdoc' might have
  # (such as json) that are ambiguous to be activated, which
  # is important because we end up using Specification.reset
  # and we don't want the warning it pops out.
  Gem.finish_resolve
end

loaded_hook = false

begin
  require 'rdoc/rubygems_hook'
  loaded_hook = true
  module Gem
    RDoc = RDoc::RubygemsHook
  end
rescue LoadError
end

##
# Gem::RDoc provides methods to generate RDoc and ri data for installed gems.
# It works for RDoc 1.0.1 (in Ruby 1.8) up to RDoc 3.6.
#
# This implementation is considered obsolete.  The RDoc project is the
# appropriate location to find this functionality.  This file provides the
# hooks to load RDoc generation code from the "rdoc" gem and a fallback in
# case the installed version of RDoc does not have them.

class Gem::RDoc # :nodoc: all

  include Gem::UserInteraction
  extend  Gem::UserInteraction

  @rdoc_version = nil
  @specs = []

  ##
  # Force installation of documentation?

  attr_accessor :force

  ##
  # Generate rdoc?

  attr_accessor :generate_rdoc

  ##
  # Generate ri data?

  attr_accessor :generate_ri

  class << self

    ##
    # Loaded version of RDoc.  Set by ::load_rdoc

    attr_reader :rdoc_version

  end

  ##
  # Post installs hook that generates documentation for each specification in
  # +specs+

  def self.generation_hook installer, specs
    start = Time.now
    types = installer.document

    generate_rdoc = types.include? 'rdoc'
    generate_ri   = types.include? 'ri'

    specs.each do |spec|
      new(spec, generate_rdoc, generate_ri).generate
    end

    return unless generate_rdoc or generate_ri

    duration = (Time.now - start).to_i
    names    = specs.map(&:name).join ', '

    say "Done installing documentation for #{names} after #{duration} seconds"
  end

  ##
  # Loads the RDoc generator

  def self.load_rdoc
    return if @rdoc_version

    require 'rdoc/rdoc'

    @rdoc_version = if ::RDoc.const_defined? :VERSION then
                      Gem::Version.new ::RDoc::VERSION
                    else
                      Gem::Version.new '1.0.1'
                    end

  rescue LoadError => e
    raise Gem::DocumentError, "RDoc is not installed: #{e}"
  end

  ##
  # Creates a new documentation generator for +spec+.  RDoc and ri data
  # generation can be enabled or disabled through +generate_rdoc+ and
  # +generate_ri+ respectively.
  #
  # Only +generate_ri+ is enabled by default.

  def initialize spec, generate_rdoc = true, generate_ri = true
    @doc_dir   = spec.doc_dir
    @file_info = nil
    @force     = false
    @rdoc      = nil
    @spec      = spec

    @generate_rdoc = generate_rdoc
    @generate_ri   = generate_ri

    @rdoc_dir = spec.doc_dir 'rdoc'
    @ri_dir   = spec.doc_dir 'ri'
  end

  ##
  # Removes legacy rdoc arguments from +args+
  #--
  # TODO move to RDoc::Options

  def delete_legacy_args args
    args.delete '--inline-source'
    args.delete '--promiscuous'
    args.delete '-p'
    args.delete '--one-file'
  end

  ##
  # Generates documentation using the named +generator+ ("darkfish" or "ri")
  # and following the given +options+.
  #
  # Documentation will be generated into +destination+

  def document generator, options, destination
    generator_name = generator

    options = options.dup
    options.exclude ||= [] # TODO maybe move to RDoc::Options#finish
    options.setup_generator generator
    options.op_dir = destination
    options.finish

    generator = options.generator.new @rdoc.store, options

    @rdoc.options = options
    @rdoc.generator = generator

    say "Installing #{generator_name} documentation for #{@spec.full_name}"

    FileUtils.mkdir_p options.op_dir

    Dir.chdir options.op_dir do
      begin
        @rdoc.class.current = @rdoc
        @rdoc.generator.generate @file_info
      ensure
        @rdoc.class.current = nil
      end
    end
  end

  ##
  # Generates RDoc and ri data

  def generate
    return unless @generate_ri or @generate_rdoc

    setup

    options = nil

    if Gem::Requirement.new('< 3').satisfied_by? self.class.rdoc_version then
      generate_legacy
      return
    end

    ::RDoc::TopLevel.reset # TODO ::RDoc::RDoc.reset
    ::RDoc::Parser::C.reset

    args = @spec.rdoc_options
    args.concat @spec.require_paths
    args.concat @spec.extra_rdoc_files

    case config_args = Gem.configuration[:rdoc]
    when String then
      args = args.concat config_args.split
    when Array then
      args = args.concat config_args
    end

    delete_legacy_args args

    Dir.chdir @spec.full_gem_path do
      options = ::RDoc::Options.new
      options.default_title = "#{@spec.full_name} Documentation"
      options.parse args
    end

    options.quiet = !Gem.configuration.really_verbose

    @rdoc = new_rdoc
    @rdoc.options = options

    say "Parsing documentation for #{@spec.full_name}"

    Dir.chdir @spec.full_gem_path do
      @file_info = @rdoc.parse_files options.files
    end

    document 'ri',       options, @ri_dir if
      @generate_ri   and (@force or not File.exist? @ri_dir)

    document 'darkfish', options, @rdoc_dir if
      @generate_rdoc and (@force or not File.exist? @rdoc_dir)
  end

  ##
  # Generates RDoc and ri data for legacy RDoc versions.  This method will not
  # exist in future versions.

  def generate_legacy
    if @generate_rdoc then
      FileUtils.rm_rf @rdoc_dir
      say "Installing RDoc documentation for #{@spec.full_name}"
      legacy_rdoc '--op', @rdoc_dir
    end

    if @generate_ri then
      FileUtils.rm_rf @ri_dir
      say "Installing ri documentation for #{@spec.full_name}"
      legacy_rdoc '--ri', '--op', @ri_dir
    end
  end

  ##
  # Generates RDoc using a legacy version of RDoc from the ARGV-like +args+.
  # This method will not exist in future versions.

  def legacy_rdoc *args
    args << @spec.rdoc_options
    args << '--quiet'
    args << @spec.require_paths.clone
    args << @spec.extra_rdoc_files
    args << '--title' << "#{@spec.full_name} Documentation"
    args = args.flatten.map do |arg| arg.to_s end

    delete_legacy_args args if
      Gem::Requirement.new('>= 2.4.0') =~ self.class.rdoc_version

    r = new_rdoc
    say "rdoc #{args.join ' '}" if Gem.configuration.really_verbose

    Dir.chdir @spec.full_gem_path do
      begin
        r.document args
      rescue Errno::EACCES => e
        dirname = File.dirname e.message.split("-")[1].strip
        raise Gem::FilePermissionError, dirname
      rescue Interrupt => e
        raise e
      rescue Exception => ex
        alert_error "While generating documentation for #{@spec.full_name}"
        ui.errs.puts "... MESSAGE:   #{ex}"
        ui.errs.puts "... RDOC args: #{args.join(' ')}"
        ui.backtrace ex
        ui.errs.puts "(continuing with the rest of the installation)"
      ensure
      end
    end
  end

  ##
  # #new_rdoc creates a new RDoc instance.  This method is provided only to
  # make testing easier.

  def new_rdoc # :nodoc:
    ::RDoc::RDoc.new
  end

  ##
  # Is rdoc documentation installed?

  def rdoc_installed?
    File.exist? @rdoc_dir
  end

  ##
  # Removes generated RDoc and ri data

  def remove
    base_dir = @spec.base_dir

    raise Gem::FilePermissionError, base_dir unless File.writable? base_dir

    FileUtils.rm_rf @rdoc_dir
    FileUtils.rm_rf @ri_dir
  end

  ##
  # Is ri data installed?

  def ri_installed?
    File.exist? @ri_dir
  end

  ##
  # Prepares the spec for documentation generation

  def setup
    self.class.load_rdoc

    raise Gem::FilePermissionError, @doc_dir if
      File.exist?(@doc_dir) and not File.writable?(@doc_dir)

    FileUtils.mkdir_p @doc_dir unless File.exist? @doc_dir
  end

end unless loaded_hook

Gem.done_installing(&Gem::RDoc.method(:generation_hook))

