# -*- coding: utf-8 -*-
# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++


require 'rubygems/version'
require 'rubygems/requirement'
require 'rubygems/platform'
require 'rubygems/deprecate'
require 'rubygems/basic_specification'
require 'rubygems/stub_specification'
require 'rubygems/util/list'
require 'stringio'

##
# The Specification class contains the information for a Gem.  Typically
# defined in a .gemspec file or a Rakefile, and looks like this:
#
#   Gem::Specification.new do |s|
#     s.name        = 'example'
#     s.version     = '0.1.0'
#     s.licenses    = ['MIT']
#     s.summary     = "This is an example!"
#     s.description = "Much longer explanation of the example!"
#     s.authors     = ["Ruby Coder"]
#     s.email       = 'rubycoder@example.com'
#     s.files       = ["lib/example.rb"]
#     s.homepage    = 'https://rubygems.org/gems/example'
#   end
#
# Starting in RubyGems 2.0, a Specification can hold arbitrary
# metadata.  See #metadata for restrictions on the format and size of metadata
# items you may add to a specification.

class Gem::Specification < Gem::BasicSpecification

  # REFACTOR: Consider breaking out this version stuff into a separate
  # module. There's enough special stuff around it that it may justify
  # a separate class.

  ##
  # The version number of a specification that does not specify one
  # (i.e. RubyGems 0.7 or earlier).

  NONEXISTENT_SPECIFICATION_VERSION = -1

  ##
  # The specification version applied to any new Specification instances
  # created.  This should be bumped whenever something in the spec format
  # changes.
  #
  # Specification Version History:
  #
  #   spec   ruby
  #    ver    ver yyyy-mm-dd description
  #     -1 <0.8.0            pre-spec-version-history
  #      1  0.8.0 2004-08-01 Deprecated "test_suite_file" for "test_files"
  #                          "test_file=x" is a shortcut for "test_files=[x]"
  #      2  0.9.5 2007-10-01 Added "required_rubygems_version"
  #                          Now forward-compatible with future versions
  #      3  1.3.2 2009-01-03 Added Fixnum validation to specification_version
  #      4  1.9.0 2011-06-07 Added metadata
  #--
  # When updating this number, be sure to also update #to_ruby.
  #
  # NOTE RubyGems < 1.2 cannot load specification versions > 2.

  CURRENT_SPECIFICATION_VERSION = 4 # :nodoc:

  ##
  # An informal list of changes to the specification.  The highest-valued
  # key should be equal to the CURRENT_SPECIFICATION_VERSION.

  SPECIFICATION_VERSION_HISTORY = { # :nodoc:
    -1 => ['(RubyGems versions up to and including 0.7 did not have versioned specifications)'],
    1  => [
      'Deprecated "test_suite_file" in favor of the new, but equivalent, "test_files"',
      '"test_file=x" is a shortcut for "test_files=[x]"'
    ],
    2  => [
      'Added "required_rubygems_version"',
      'Now forward-compatible with future versions',
    ],
    3 => [
       'Added Fixnum validation to the specification_version'
    ],
    4 => [
      'Added sandboxed freeform metadata to the specification version.'
    ]
  }

  MARSHAL_FIELDS = { # :nodoc:
    -1 => 16,
     1 => 16,
     2 => 16,
     3 => 17,
     4 => 18,
  }

  today = Time.now.utc
  TODAY = Time.utc(today.year, today.month, today.day) # :nodoc:

  LOAD_CACHE = {} # :nodoc:

  private_constant :LOAD_CACHE if defined? private_constant

  VALID_NAME_PATTERN = /\A[a-zA-Z0-9\.\-\_]+\z/ # :nodoc:

  # :startdoc:

  ##
  # List of attribute names: [:name, :version, ...]

  @@required_attributes = [:rubygems_version,
                           :specification_version,
                           :name,
                           :version,
                           :date,
                           :summary,
                           :require_paths]

  ##
  # Map of attribute names to default values.

  @@default_value = {
    :authors                   => [],
    :autorequire               => nil,
    :bindir                    => 'bin',
    :cert_chain                => [],
    :date                      => TODAY,
    :dependencies              => [],
    :description               => nil,
    :email                     => nil,
    :executables               => [],
    :extensions                => [],
    :extra_rdoc_files          => [],
    :files                     => [],
    :homepage                  => nil,
    :licenses                  => [],
    :metadata                  => {},
    :name                      => nil,
    :platform                  => Gem::Platform::RUBY,
    :post_install_message      => nil,
    :rdoc_options              => [],
    :require_paths             => ['lib'],
    :required_ruby_version     => Gem::Requirement.default,
    :required_rubygems_version => Gem::Requirement.default,
    :requirements              => [],
    :rubyforge_project         => nil,
    :rubygems_version          => Gem::VERSION,
    :signing_key               => nil,
    :specification_version     => CURRENT_SPECIFICATION_VERSION,
    :summary                   => nil,
    :test_files                => [],
    :version                   => nil,
  }

  Dupable = { } # :nodoc:

  @@default_value.each do |k,v|
    case v
    when Time, Numeric, Symbol, true, false, nil
      Dupable[k] = false
    else
      Dupable[k] = true
    end
  end

  @@attributes = @@default_value.keys.sort_by { |s| s.to_s }
  @@array_attributes = @@default_value.reject { |k,v| v != [] }.keys
  @@nil_attributes, @@non_nil_attributes = @@default_value.keys.partition { |k|
    @@default_value[k].nil?
  }

  @@stubs_by_name = {}

  # Sentinel object to represent "not found" stubs
  NOT_FOUND = Struct.new(:to_spec, :this).new # :nodoc:
  @@spec_with_requirable_file          = {}
  @@active_stub_with_requirable_file   = {}

  ######################################################################
  # :section: Required gemspec attributes

  ##
  # This gem's name.
  #
  # Usage:
  #
  #   spec.name = 'rake'

  attr_accessor :name

  ##
  # This gem's version.
  #
  # The version string can contain numbers and periods, such as +1.0.0+.
  # A gem is a 'prerelease' gem if the version has a letter in it, such as
  # +1.0.0.pre+.
  #
  # Usage:
  #
  #   spec.version = '0.4.1'

  attr_reader :version

  ##
  # Paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.
  #
  # See also #require_paths
  #
  # If you have an extension you do not need to add <code>"ext"</code> to the
  # require path, the extension build process will copy the extension files
  # into "lib" for you.
  #
  # The default value is <code>"lib"</code>
  #
  # Usage:
  #
  #   # If all library files are in the root directory...
  #   spec.require_paths = ['.']

  def require_paths=(val)
    @require_paths = Array(val)
  end

  ##
  # The version of RubyGems used to create this gem.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  attr_accessor :rubygems_version

  ##
  # A short summary of this gem's description.  Displayed in `gem list -d`.
  #
  # The #description should be more detailed than the summary.
  #
  # Usage:
  #
  #   spec.summary = "This is a small summary of my gem"

  attr_reader :summary

  ##
  # Singular writer for #authors
  #
  # Usage:
  #
  #   spec.author = 'John Jones'

  def author= o
    self.authors = [o]
  end

  ##
  # Sets the list of authors, ensuring it is an array.
  #
  # Usage:
  #
  #   spec.authors = ['John Jones', 'Mary Smith']

  def authors= value
    @authors = Array(value).flatten.grep(String)
  end

  ##
  # The platform this gem runs on.
  #
  # This is usually Gem::Platform::RUBY or Gem::Platform::CURRENT.
  #
  # Most gems contain pure Ruby code; they should simply leave the default
  # value in place.  Some gems contain C (or other) code to be compiled into a
  # Ruby "extension".  The gem should leave the default value in place unless
  # the code will only compile on a certain type of system.  Some gems consist
  # of pre-compiled code ("binary gems").  It's especially important that they
  # set the platform attribute appropriately.  A shortcut is to set the
  # platform to Gem::Platform::CURRENT, which will cause the gem builder to set
  # the platform to the appropriate value for the system on which the build is
  # being performed.
  #
  # If this attribute is set to a non-default value, it will be included in
  # the filename of the gem when it is built such as:
  # nokogiri-1.6.0-x86-mingw32.gem
  #
  # Usage:
  #
  #   spec.platform = Gem::Platform.local

  def platform= platform
    if @original_platform.nil? or
       @original_platform == Gem::Platform::RUBY then
      @original_platform = platform
    end

    case platform
    when Gem::Platform::CURRENT then
      @new_platform = Gem::Platform.local
      @original_platform = @new_platform.to_s

    when Gem::Platform then
      @new_platform = platform

    # legacy constants
    when nil, Gem::Platform::RUBY then
      @new_platform = Gem::Platform::RUBY
    when 'mswin32' then # was Gem::Platform::WIN32
      @new_platform = Gem::Platform.new 'x86-mswin32'
    when 'i586-linux' then # was Gem::Platform::LINUX_586
      @new_platform = Gem::Platform.new 'x86-linux'
    when 'powerpc-darwin' then # was Gem::Platform::DARWIN
      @new_platform = Gem::Platform.new 'ppc-darwin'
    else
      @new_platform = Gem::Platform.new platform
    end

    @platform = @new_platform.to_s

    invalidate_memoized_attributes

    @new_platform
  end

  ##
  # Files included in this gem.  You cannot append to this accessor, you must
  # assign to it.
  #
  # Only add files you can require to this list, not directories, etc.
  #
  # Directories are automatically stripped from this list when building a gem,
  # other non-files cause an error.
  #
  # Usage:
  #
  #   require 'rake'
  #   spec.files = FileList['lib/**/*.rb',
  #                         'bin/*',
  #                         '[A-Z]*',
  #                         'test/**/*'].to_a
  #
  #   # or without Rake...
  #   spec.files = Dir['lib/**/*.rb'] + Dir['bin/*']
  #   spec.files += Dir['[A-Z]*'] + Dir['test/**/*']
  #   spec.files.reject! { |fn| fn.include? "CVS" }

  def files
    # DO NOT CHANGE TO ||= ! This is not a normal accessor. (yes, it sucks)
    # DOC: Why isn't it normal? Why does it suck? How can we fix this?
    @files = [@files,
              @test_files,
              add_bindir(@executables),
              @extra_rdoc_files,
              @extensions,
             ].flatten.compact.uniq.sort
  end

  ######################################################################
  # :section: Optional gemspec attributes

  ##
  # The path in the gem for executable scripts.  Usually 'bin'
  #
  # Usage:
  #
  #   spec.bindir = 'bin'

  attr_accessor :bindir

  ##
  # The certificate chain used to sign this gem.  See Gem::Security for
  # details.

  attr_accessor :cert_chain

  ##
  # A long description of this gem
  #
  # The description should be more detailed than the summary but not
  # excessively long.  A few paragraphs is a recommended length with no
  # examples or formatting.
  #
  # Usage:
  #
  #   spec.description = <<-EOF
  #     Rake is a Make-like program implemented in Ruby. Tasks and
  #     dependencies are specified in standard Ruby syntax.
  #   EOF

  attr_reader :description

  ##
  # :category: Recommended gemspec attributes
  #
  # A contact email address (or addresses) for this gem
  #
  # Usage:
  #
  #   spec.email = 'john.jones@example.com'
  #   spec.email = ['jack@example.com', 'jill@example.com']

  attr_accessor :email

  ##
  # :category: Recommended gemspec attributes
  #
  # The URL of this gem's home page
  #
  # Usage:
  #
  #   spec.homepage = 'https://github.com/ruby/rake'

  attr_accessor :homepage

  ##
  # A message that gets displayed after the gem is installed.
  #
  # Usage:
  #
  #   spec.post_install_message = "Thanks for installing!"

  attr_accessor :post_install_message

  ##
  # The version of Ruby required by this gem

  attr_reader :required_ruby_version

  ##
  # The RubyGems version required by this gem

  attr_reader :required_rubygems_version

  ##
  # The key used to sign this gem.  See Gem::Security for details.

  attr_accessor :signing_key

  ##
  # :attr_accessor: metadata
  #
  # The metadata holds extra data for this gem that may be useful to other
  # consumers and is settable by gem authors without requiring an update to
  # the rubygems software.
  #
  # Metadata items have the following restrictions:
  #
  # * The metadata must be a Hash object
  # * All keys and values must be Strings
  # * Keys can be a maximum of 128 bytes and values can be a maximum of 1024
  #   bytes
  # * All strings must be UTF-8, no binary data is allowed
  #
  # To add metadata for the location of a issue tracker:
  #
  #   s.metadata = { "issue_tracker" => "https://example/issues" }

  attr_accessor :metadata

  ##
  # Adds a development dependency named +gem+ with +requirements+ to this
  # gem.
  #
  # Usage:
  #
  #   spec.add_development_dependency 'example', '~> 1.1', '>= 1.1.4'
  #
  # Development dependencies aren't installed by default and aren't
  # activated when a gem is required.

  def add_development_dependency(gem, *requirements)
    add_dependency_with_type(gem, :development, *requirements)
  end

  ##
  # Adds a runtime dependency named +gem+ with +requirements+ to this gem.
  #
  # Usage:
  #
  #   spec.add_runtime_dependency 'example', '~> 1.1', '>= 1.1.4'

  def add_runtime_dependency(gem, *requirements)
    add_dependency_with_type(gem, :runtime, *requirements)
  end

  ##
  # Executables included in the gem.
  #
  # For example, the rake gem has rake as an executable. You don’t specify the
  # full path (as in bin/rake); all application-style files are expected to be
  # found in bindir.  These files must be executable Ruby files.  Files that
  # use bash or other interpreters will not work.
  #
  # Executables included may only be ruby scripts, not scripts for other
  # languages or compiled binaries.
  #
  # Usage:
  #
  #   spec.executables << 'rake'

  def executables
    @executables ||= []
  end

  ##
  # Extensions to build when installing the gem, specifically the paths to
  # extconf.rb-style files used to compile extensions.
  #
  # These files will be run when the gem is installed, causing the C (or
  # whatever) code to be compiled on the user’s machine.
  #
  # Usage:
  #
  #  spec.extensions << 'ext/rmagic/extconf.rb'
  #
  # See Gem::Ext::Builder for information about writing extensions for gems.

  def extensions
    @extensions ||= []
  end

  ##
  # Extra files to add to RDoc such as README or doc/examples.txt
  #
  # When the user elects to generate the RDoc documentation for a gem (typically
  # at install time), all the library files are sent to RDoc for processing.
  # This option allows you to have some non-code files included for a more
  # complete set of documentation.
  #
  # Usage:
  #
  #  spec.extra_rdoc_files = ['README', 'doc/user-guide.txt']

  def extra_rdoc_files
    @extra_rdoc_files ||= []
  end

  ##
  # The version of RubyGems that installed this gem.  Returns
  # <code>Gem::Version.new(0)</code> for gems installed by versions earlier
  # than RubyGems 2.2.0.

  def installed_by_version # :nodoc:
    @installed_by_version ||= Gem::Version.new(0)
  end

  ##
  # Sets the version of RubyGems that installed this gem.  See also
  # #installed_by_version.

  def installed_by_version= version # :nodoc:
    @installed_by_version = Gem::Version.new version
  end

  ##
  # :category: Recommended gemspec attributes
  #
  # The license for this gem.
  #
  # The license must be no more than 64 characters.
  #
  # This should just be the name of your license. The full text of the license
  # should be inside of the gem (at the top level) when you build it.
  #
  # The simplest way, is to specify the standard SPDX ID
  # https://spdx.org/licenses/ for the license.
  # Ideally you should pick one that is OSI (Open Source Initiative)
  # http://opensource.org/licenses/alphabetical approved.
  #
  # The most commonly used OSI approved licenses are MIT and Apache-2.0.
  # GitHub also provides a license picker at http://choosealicense.com/.
  #
  # You should specify a license for your gem so that people know how they are
  # permitted to use it, and any restrictions you're placing on it.  Not
  # specifying a license means all rights are reserved; others have no rights
  # to use the code for any purpose.
  #
  # You can set multiple licenses with #licenses=
  #
  # Usage:
  #   spec.license = 'MIT'

  def license=o
    self.licenses = [o]
  end

  ##
  # :category: Recommended gemspec attributes
  # The license(s) for the library.
  #
  # Each license must be a short name, no more than 64 characters.
  #
  # This should just be the name of your license. The full
  # text of the license should be inside of the gem when you build it.
  #
  # See #license= for more discussion
  #
  # Usage:
  #   spec.licenses = ['MIT', 'GPL-2.0']

  def licenses= licenses
    @licenses = Array licenses
  end

  ##
  # Specifies the rdoc options to be used when generating API documentation.
  #
  # Usage:
  #
  #   spec.rdoc_options << '--title' << 'Rake -- Ruby Make' <<
  #     '--main' << 'README' <<
  #     '--line-numbers'

  def rdoc_options
    @rdoc_options ||= []
  end

  ##
  # The version of Ruby required by this gem.  The ruby version can be
  # specified to the patch-level:
  #
  #   $ ruby -v -e 'p Gem.ruby_version'
  #   ruby 2.0.0p247 (2013-06-27 revision 41674) [x86_64-darwin12.4.0]
  #   #<Gem::Version "2.0.0.247">
  #
  # Because patch-level is taken into account, be very careful specifying using
  # `<=`: `<= 2.2.2` will not match any patch-level of 2.2.2 after the `p0`
  # release. It is much safer to specify `< 2.2.3` instead
  #
  # Usage:
  #
  #  # This gem will work with 1.8.6 or greater...
  #  spec.required_ruby_version = '>= 1.8.6'
  #
  #  # Only with ruby 2.0.x
  #  spec.required_ruby_version = '~> 2.0'
  #
  #  # Only with ruby between 2.2.0 and 2.2.2
  #  spec.required_ruby_version = ['>= 2.2.0', '< 2.2.3']

  def required_ruby_version= req
    @required_ruby_version = Gem::Requirement.create req
  end

  ##
  # The RubyGems version required by this gem

  def required_rubygems_version= req
    @required_rubygems_version = Gem::Requirement.create req
  end

  ##
  # Lists the external (to RubyGems) requirements that must be met for this gem
  # to work.  It's simply information for the user.
  #
  # Usage:
  #
  #   spec.requirements << 'libmagick, v6.0'
  #   spec.requirements << 'A good graphics card'

  def requirements
    @requirements ||= []
  end

  ##
  # A collection of unit test files.  They will be loaded as unit tests when
  # the user requests a gem to be unit tested.
  #
  # Usage:
  #   spec.test_files = Dir.glob('test/tc_*.rb')
  #   spec.test_files = ['tests/test-suite.rb']

  def test_files= files # :nodoc:
    @test_files = Array files
  end

  ######################################################################
  # :section: Specification internals

  ##
  # True when this gemspec has been activated. This attribute is not persisted.

  attr_accessor :activated

  alias :activated? :activated

  ##
  # Autorequire was used by old RubyGems to automatically require a file.
  #
  # Deprecated: It is neither supported nor functional.

  attr_accessor :autorequire # :nodoc:

  ##
  # Sets the default executable for this gem.
  #
  # Deprecated: You must now specify the executable name to  Gem.bin_path.

  attr_writer :default_executable

  ##
  # Allows deinstallation of gems with legacy platforms.

  attr_writer :original_platform # :nodoc:

  ##
  # The rubyforge project this gem lives under.  i.e. RubyGems'
  # rubyforge_project is "rubygems".
  #
  # This option is deprecated.

  attr_accessor :rubyforge_project

  ##
  # The Gem::Specification version of this gemspec.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  attr_accessor :specification_version

  def self._all # :nodoc:
    unless defined?(@@all) && @@all then
      @@all = stubs.map(&:to_spec)

      # After a reset, make sure already loaded specs
      # are still marked as activated.
      specs = {}
      Gem.loaded_specs.each_value{|s| specs[s] = true}
      @@all.each{|s| s.activated = true if specs[s]}
    end
    @@all
  end

  def self._clear_load_cache # :nodoc:
    LOAD_CACHE.clear
  end

  def self.each_gemspec(dirs) # :nodoc:
    dirs.each do |dir|
      Dir[File.join(dir, "*.gemspec")].each do |path|
        yield path.untaint
      end
    end
  end

  def self.gemspec_stubs_in dir, pattern
    Dir[File.join(dir, pattern)].map { |path| yield path }.select(&:valid?)
  end
  private_class_method :gemspec_stubs_in

  def self.default_stubs pattern
    base_dir = Gem.default_dir
    gems_dir = File.join base_dir, "gems"
    gemspec_stubs_in(default_specifications_dir, pattern) do |path|
      Gem::StubSpecification.default_gemspec_stub(path, base_dir, gems_dir)
    end
  end
  private_class_method :default_stubs

  def self.installed_stubs dirs, pattern
    map_stubs(dirs, pattern) do |path, base_dir, gems_dir|
      Gem::StubSpecification.gemspec_stub(path, base_dir, gems_dir)
    end
  end
  private_class_method :installed_stubs

  if [].respond_to? :flat_map
    def self.map_stubs(dirs, pattern) # :nodoc:
      dirs.flat_map { |dir|
        base_dir = File.dirname dir
        gems_dir = File.join base_dir, "gems"
        gemspec_stubs_in(dir, pattern) { |path| yield path, base_dir, gems_dir }
      }
    end
  else # FIXME: remove when 1.8 is dropped
    def self.map_stubs(dirs, pattern) # :nodoc:
      dirs.map { |dir|
        base_dir = File.dirname dir
        gems_dir = File.join base_dir, "gems"
        gemspec_stubs_in(dir, pattern) { |path| yield path, base_dir, gems_dir }
      }.flatten 1
    end
  end
  private_class_method :map_stubs

  uniq_takes_a_block = false
  [1,2].uniq { uniq_takes_a_block = true }

  if uniq_takes_a_block
    def self.uniq_by(list, &block) # :nodoc:
      list.uniq(&block)
    end
  else # FIXME: remove when 1.8 is dropped
    def self.uniq_by(list) # :nodoc:
      values = {}
      list.each { |item|
        value = yield item
        values[value] ||= item
      }
      values.values
    end
  end
  private_class_method :uniq_by

  if [].respond_to? :sort_by!
    def self.sort_by! list, &block
      list.sort_by!(&block)
    end
  else # FIXME: remove when 1.8 is dropped
    def self.sort_by! list, &block
      list.replace list.sort_by(&block)
    end
  end
  private_class_method :sort_by!

  def self.each_spec(dirs) # :nodoc:
    each_gemspec(dirs) do |path|
      spec = self.load path
      yield spec if spec
    end
  end

  ##
  # Returns a Gem::StubSpecification for every installed gem

  def self.stubs
    @@stubs ||= begin
      pattern = "*.gemspec"
      stubs = default_stubs(pattern).concat installed_stubs(dirs, pattern)
      stubs = uniq_by(stubs) { |stub| stub.full_name }

      _resort!(stubs)
      @@stubs_by_name = stubs.group_by(&:name)
      stubs
    end
  end

  EMPTY = [].freeze # :nodoc:

  ##
  # Returns a Gem::StubSpecification for installed gem named +name+

  def self.stubs_for name
    if @@stubs
      @@stubs_by_name[name] || []
    else
      pattern = "#{name}-*.gemspec"
      stubs = default_stubs(pattern) + installed_stubs(dirs, pattern)
      stubs = uniq_by(stubs) { |stub| stub.full_name }.group_by(&:name)
      stubs.each_value { |v| sort_by!(v) { |i| i.version } }

      @@stubs_by_name.merge! stubs
      @@stubs_by_name[name] ||= EMPTY
    end
  end

  def self._resort!(specs) # :nodoc:
    specs.sort! { |a, b|
      names = a.name <=> b.name
      next names if names.nonzero?
      b.version <=> a.version
    }
  end

  ##
  # Loads the default specifications. It should be called only once.

  def self.load_defaults
    each_spec([default_specifications_dir]) do |spec|
      # #load returns nil if the spec is bad, so we just ignore
      # it at this stage
      Gem.register_default_spec(spec)
    end
  end

  ##
  # Adds +spec+ to the known specifications, keeping the collection
  # properly sorted.

  def self.add_spec spec
    warn "Gem::Specification.add_spec is deprecated and will be removed in Rubygems 3.0" unless Gem::Deprecate.skip
    # TODO: find all extraneous adds
    # puts
    # p :add_spec => [spec.full_name, caller.reject { |s| s =~ /minitest/ }]

    # TODO: flush the rest of the crap from the tests
    # raise "no dupes #{spec.full_name} in #{all_names.inspect}" if
    #   _all.include? spec

    raise "nil spec!" unless spec # TODO: remove once we're happy with tests

    return if _all.include? spec

    _all << spec
    stubs << spec
    (@@stubs_by_name[spec.name] ||= []) << spec
    sort_by!(@@stubs_by_name[spec.name]) { |s| s.version }
    _resort!(_all)
    _resort!(stubs)
  end

  ##
  # Adds multiple specs to the known specifications.

  def self.add_specs *specs
    warn "Gem::Specification.add_specs is deprecated and will be removed in Rubygems 3.0" unless Gem::Deprecate.skip

    raise "nil spec!" if specs.any?(&:nil?) # TODO: remove once we're happy

    # TODO: this is much more efficient, but we need the extra checks for now
    # _all.concat specs
    # _resort!

    Gem::Deprecate.skip_during do
      specs.each do |spec| # TODO: slow
        add_spec spec
      end
    end
  end

  ##
  # Returns all specifications. This method is discouraged from use.
  # You probably want to use one of the Enumerable methods instead.

  def self.all
    warn "NOTE: Specification.all called from #{caller.first}" unless
      Gem::Deprecate.skip
    _all
  end

  ##
  # Sets the known specs to +specs+. Not guaranteed to work for you in
  # the future. Use at your own risk. Caveat emptor. Doomy doom doom.
  # Etc etc.
  #
  #--
  # Makes +specs+ the known specs
  # Listen, time is a river
  # Winter comes, code breaks
  #
  # -- wilsonb

  def self.all= specs
    @@stubs_by_name = specs.group_by(&:name)
    @@all = @@stubs = specs
  end

  ##
  # Return full names of all specs in sorted order.

  def self.all_names
    self._all.map(&:full_name)
  end

  ##
  # Return the list of all array-oriented instance variables.
  #--
  # Not sure why we need to use so much stupid reflection in here...

  def self.array_attributes
    @@array_attributes.dup
  end

  ##
  # Return the list of all instance variables.
  #--
  # Not sure why we need to use so much stupid reflection in here...

  def self.attribute_names
    @@attributes.dup
  end

  ##
  # Return the directories that Specification uses to find specs.

  def self.dirs
    @@dirs ||= Gem.path.collect { |dir|
      File.join dir.dup.untaint, "specifications"
    }
  end

  ##
  # Set the directories that Specification uses to find specs. Setting
  # this resets the list of known specs.

  def self.dirs= dirs
    self.reset

    @@dirs = Array(dirs).map { |dir| File.join dir, "specifications" }
  end

  extend Enumerable

  ##
  # Enumerate every known spec.  See ::dirs= and ::add_spec to set the list of
  # specs.

  def self.each
    return enum_for(:each) unless block_given?

    self._all.each do |x|
      yield x
    end
  end

  ##
  # Returns every spec that matches +name+ and optional +requirements+.

  def self.find_all_by_name name, *requirements
    requirements = Gem::Requirement.default if requirements.empty?

    # TODO: maybe try: find_all { |s| spec === dep }

    Gem::Dependency.new(name, *requirements).matching_specs
  end

  ##
  # Find the best specification matching a +name+ and +requirements+. Raises
  # if the dependency doesn't resolve to a valid specification.

  def self.find_by_name name, *requirements
    requirements = Gem::Requirement.default if requirements.empty?

    # TODO: maybe try: find { |s| spec === dep }

    Gem::Dependency.new(name, *requirements).to_spec
  end

  ##
  # Return the best specification that contains the file matching +path+.

  def self.find_by_path path
    path = path.dup.freeze
    spec = @@spec_with_requirable_file[path] ||= (stubs.find { |s|
      s.contains_requirable_file? path
    } || NOT_FOUND)
    spec.to_spec
  end

  ##
  # Return the best specification that contains the file matching +path+
  # amongst the specs that are not activated.

  def self.find_inactive_by_path path
    stub = stubs.find { |s|
      s.contains_requirable_file? path unless s.activated?
    }
    stub && stub.to_spec
  end

  def self.find_active_stub_by_path path
    stub = @@active_stub_with_requirable_file[path] ||= (stubs.find { |s|
      s.activated? and s.contains_requirable_file? path
    } || NOT_FOUND)
    stub.this
  end

  ##
  # Return currently unresolved specs that contain the file matching +path+.

  def self.find_in_unresolved path
    # TODO: do we need these?? Kill it
    specs = unresolved_deps.values.map { |dep| dep.to_specs }.flatten

    specs.find_all { |spec| spec.contains_requirable_file? path }
  end

  ##
  # Search through all unresolved deps and sub-dependencies and return
  # specs that contain the file matching +path+.

  def self.find_in_unresolved_tree path
    specs = unresolved_deps.values.map { |dep| dep.to_specs }.flatten

    specs.reverse_each do |spec|
      spec.traverse do |from_spec, dep, to_spec, trail|
        if to_spec.has_conflicts? || to_spec.conficts_when_loaded_with?(trail)
          :next
        else
          return trail.reverse if to_spec.contains_requirable_file? path
        end
      end
    end

    []
  end

  ##
  # Special loader for YAML files.  When a Specification object is loaded
  # from a YAML file, it bypasses the normal Ruby object initialization
  # routine (#initialize).  This method makes up for that and deals with
  # gems of different ages.
  #
  # +input+ can be anything that YAML.load() accepts: String or IO.

  def self.from_yaml(input)
    Gem.load_yaml

    input = normalize_yaml_input input
    spec = Gem::SafeYAML.safe_load input

    if spec && spec.class == FalseClass then
      raise Gem::EndOfYAMLException
    end

    unless Gem::Specification === spec then
      raise Gem::Exception, "YAML data doesn't evaluate to gem specification"
    end

    spec.specification_version ||= NONEXISTENT_SPECIFICATION_VERSION
    spec.reset_nil_attributes_to_default

    spec
  end

  ##
  # Return the latest specs, optionally including prerelease specs if
  # +prerelease+ is true.

  def self.latest_specs prerelease = false
    _latest_specs Gem::Specification._all, prerelease
  end

  def self._latest_specs specs, prerelease = false # :nodoc:
    result = Hash.new { |h,k| h[k] = {} }
    native = {}

    specs.reverse_each do |spec|
      next if spec.version.prerelease? unless prerelease

      native[spec.name] = spec.version if spec.platform == Gem::Platform::RUBY
      result[spec.name][spec.platform] = spec
    end

    result.map(&:last).map(&:values).flatten.reject { |spec|
      minimum = native[spec.name]
      minimum && spec.version < minimum
    }.sort_by{ |tup| tup.name }
  end

  ##
  # Loads Ruby format gemspec from +file+.

  def self.load file
    return unless file

    _spec = LOAD_CACHE[file]
    return _spec if _spec

    file = file.dup.untaint
    return unless File.file?(file)

    code = if defined? Encoding
             File.read file, :mode => 'r:UTF-8:-'
           else
             File.read file
           end

    code.untaint

    begin
      _spec = eval code, binding, file

      if Gem::Specification === _spec
        _spec.loaded_from = File.expand_path file.to_s
        LOAD_CACHE[file] = _spec
        return _spec
      end

      warn "[#{file}] isn't a Gem::Specification (#{_spec.class} instead)."
    rescue SignalException, SystemExit
      raise
    rescue SyntaxError, Exception => e
      warn "Invalid gemspec in [#{file}]: #{e}"
    end

    nil
  end

  ##
  # Specification attributes that must be non-nil

  def self.non_nil_attributes
    @@non_nil_attributes.dup
  end

  ##
  # Make sure the YAML specification is properly formatted with dashes

  def self.normalize_yaml_input(input)
    result = input.respond_to?(:read) ? input.read : input
    result = "--- " + result unless result =~ /\A--- /
    result = result.dup
    result.gsub!(/ !!null \n/, " \n")
    # date: 2011-04-26 00:00:00.000000000Z
    # date: 2011-04-26 00:00:00.000000000 Z
    result.gsub!(/^(date: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+?)Z/, '\1 Z')
    result
  end

  ##
  # Return a list of all outdated local gem names.  This method is HEAVY
  # as it must go fetch specifications from the server.
  #
  # Use outdated_and_latest_version if you wish to retrieve the latest remote
  # version as well.

  def self.outdated
    outdated_and_latest_version.map { |local, _| local.name }
  end

  ##
  # Enumerates the outdated local gems yielding the local specification and
  # the latest remote version.
  #
  # This method may take some time to return as it must check each local gem
  # against the server's index.

  def self.outdated_and_latest_version
    return enum_for __method__ unless block_given?

    # TODO: maybe we should switch to rubygems' version service?
    fetcher = Gem::SpecFetcher.fetcher

    latest_specs(true).each do |local_spec|
      dependency =
        Gem::Dependency.new local_spec.name, ">= #{local_spec.version}"

      remotes, = fetcher.search_for_dependency dependency
      remotes  = remotes.map { |n, _| n.version }

      latest_remote = remotes.sort.last

      yield [local_spec, latest_remote] if
        latest_remote and local_spec.version < latest_remote
    end

    nil
  end

  ##
  # Removes +spec+ from the known specs.

  def self.remove_spec spec
    warn "Gem::Specification.remove_spec is deprecated and will be removed in Rubygems 3.0" unless Gem::Deprecate.skip
    _all.delete spec
    stubs.delete_if { |s| s.full_name == spec.full_name }
    (@@stubs_by_name[spec.name] || []).delete_if { |s| s.full_name == spec.full_name }
    reset
  end

  ##
  # Is +name+ a required attribute?

  def self.required_attribute?(name)
    @@required_attributes.include? name.to_sym
  end

  ##
  # Required specification attributes

  def self.required_attributes
    @@required_attributes.dup
  end

  ##
  # Reset the list of known specs, running pre and post reset hooks
  # registered in Gem.

  def self.reset
    @@dirs = nil
    Gem.pre_reset_hooks.each { |hook| hook.call }
    @@all = nil
    @@stubs = nil
    @@stubs_by_name = {}
    @@spec_with_requirable_file          = {}
    @@active_stub_with_requirable_file   = {}
    _clear_load_cache
    unresolved = unresolved_deps
    unless unresolved.empty? then
      w = "W" + "ARN"
      warn "#{w}: Unresolved specs during Gem::Specification.reset:"
      unresolved.values.each do |dep|
        warn "      #{dep}"
      end
      warn "#{w}: Clearing out unresolved specs."
      warn "Please report a bug if this causes problems."
      unresolved.clear
    end
    Gem.post_reset_hooks.each { |hook| hook.call }
  end

  # DOC: This method needs documented or nodoc'd
  def self.unresolved_deps
    @unresolved_deps ||= Hash.new { |h, n| h[n] = Gem::Dependency.new n }
  end

  ##
  # Load custom marshal format, re-initializing defaults as needed

  def self._load(str)
    array = Marshal.load str

    spec = Gem::Specification.new
    spec.instance_variable_set :@specification_version, array[1]

    current_version = CURRENT_SPECIFICATION_VERSION

    field_count = if spec.specification_version > current_version then
                    spec.instance_variable_set :@specification_version,
                                               current_version
                    MARSHAL_FIELDS[current_version]
                  else
                    MARSHAL_FIELDS[spec.specification_version]
                  end

    if array.size < field_count then
      raise TypeError, "invalid Gem::Specification format #{array.inspect}"
    end

    # Cleanup any YAML::PrivateType. They only show up for an old bug
    # where nil => null, so just convert them to nil based on the type.

    array.map! { |e| e.kind_of?(YAML::PrivateType) ? nil : e }

    spec.instance_variable_set :@rubygems_version,          array[0]
    # spec version
    spec.instance_variable_set :@name,                      array[2]
    spec.instance_variable_set :@version,                   array[3]
    spec.date =                                             array[4]
    spec.instance_variable_set :@summary,                   array[5]
    spec.instance_variable_set :@required_ruby_version,     array[6]
    spec.instance_variable_set :@required_rubygems_version, array[7]
    spec.instance_variable_set :@original_platform,         array[8]
    spec.instance_variable_set :@dependencies,              array[9]
    spec.instance_variable_set :@rubyforge_project,         array[10]
    spec.instance_variable_set :@email,                     array[11]
    spec.instance_variable_set :@authors,                   array[12]
    spec.instance_variable_set :@description,               array[13]
    spec.instance_variable_set :@homepage,                  array[14]
    spec.instance_variable_set :@has_rdoc,                  array[15]
    spec.instance_variable_set :@new_platform,              array[16]
    spec.instance_variable_set :@platform,                  array[16].to_s
    spec.instance_variable_set :@license,                   array[17]
    spec.instance_variable_set :@metadata,                  array[18]
    spec.instance_variable_set :@loaded,                    false
    spec.instance_variable_set :@activated,                 false

    spec
  end

  def <=>(other) # :nodoc:
    sort_obj <=> other.sort_obj
  end

  def == other # :nodoc:
    self.class === other &&
      name == other.name &&
      version == other.version &&
      platform == other.platform
  end

  ##
  # Dump only crucial instance variables.
  #--
  # MAINTAIN ORDER!
  # (down with the man)

  def _dump(limit)
    Marshal.dump [
      @rubygems_version,
      @specification_version,
      @name,
      @version,
      date,
      @summary,
      @required_ruby_version,
      @required_rubygems_version,
      @original_platform,
      @dependencies,
      @rubyforge_project,
      @email,
      @authors,
      @description,
      @homepage,
      true, # has_rdoc
      @new_platform,
      @licenses,
      @metadata
    ]
  end

  ##
  # Activate this spec, registering it as a loaded spec and adding
  # it's lib paths to $LOAD_PATH. Returns true if the spec was
  # activated, false if it was previously activated. Freaks out if
  # there are conflicts upon activation.

  def activate
    other = Gem.loaded_specs[self.name]
    if other then
      check_version_conflict other
      return false
    end

    raise_if_conflicts

    activate_dependencies
    add_self_to_load_path

    Gem.loaded_specs[self.name] = self
    @activated = true
    @loaded = true

    return true
  end

  ##
  # Activate all unambiguously resolved runtime dependencies of this
  # spec. Add any ambiguous dependencies to the unresolved list to be
  # resolved later, as needed.

  def activate_dependencies
    unresolved = Gem::Specification.unresolved_deps

    self.runtime_dependencies.each do |spec_dep|
      if loaded = Gem.loaded_specs[spec_dep.name]
        next if spec_dep.matches_spec? loaded

        msg = "can't satisfy '#{spec_dep}', already activated '#{loaded.full_name}'"
        e = Gem::LoadError.new msg
        e.name = spec_dep.name

        raise e
      end

      specs = spec_dep.to_specs

      if specs.size == 1 then
        specs.first.activate
      else
        name = spec_dep.name
        unresolved[name] = unresolved[name].merge spec_dep
      end
    end

    unresolved.delete self.name
  end

  ##
  # Abbreviate the spec for downloading.  Abbreviated specs are only used for
  # searching, downloading and related activities and do not need deployment
  # specific information (e.g. list of files).  So we abbreviate the spec,
  # making it much smaller for quicker downloads.

  def abbreviate
    self.files = []
    self.test_files = []
    self.rdoc_options = []
    self.extra_rdoc_files = []
    self.cert_chain = []
  end

  ##
  # Sanitize the descriptive fields in the spec.  Sometimes non-ASCII
  # characters will garble the site index.  Non-ASCII characters will
  # be replaced by their XML entity equivalent.

  def sanitize
    self.summary              = sanitize_string(summary)
    self.description          = sanitize_string(description)
    self.post_install_message = sanitize_string(post_install_message)
    self.authors              = authors.collect { |a| sanitize_string(a) }
  end

  ##
  # Sanitize a single string.

  def sanitize_string(string)
    return string unless string

    # HACK the #to_s is in here because RSpec has an Array of Arrays of
    # Strings for authors.  Need a way to disallow bad values on gemspec
    # generation.  (Probably won't happen.)
    string = string.to_s

    begin
      Builder::XChar.encode string
    rescue NameError, NoMethodError
      string.to_xs
    end
  end

  ##
  # Returns an array with bindir attached to each executable in the
  # +executables+ list

  def add_bindir(executables)
    return nil if executables.nil?

    if @bindir then
      Array(executables).map { |e| File.join(@bindir, e) }
    else
      executables
    end
  rescue
    return nil
  end

  ##
  # Adds a dependency on gem +dependency+ with type +type+ that requires
  # +requirements+.  Valid types are currently <tt>:runtime</tt> and
  # <tt>:development</tt>.

  def add_dependency_with_type(dependency, type, *requirements)
    requirements = if requirements.empty? then
                     Gem::Requirement.default
                   else
                     requirements.flatten
                   end

    unless dependency.respond_to?(:name) &&
           dependency.respond_to?(:requirement)
      dependency = Gem::Dependency.new(dependency.to_s, requirements, type)
    end

    dependencies << dependency
  end

  private :add_dependency_with_type

  alias add_dependency add_runtime_dependency

  ##
  # Adds this spec's require paths to LOAD_PATH, in the proper location.

  def add_self_to_load_path
    return if default_gem?

    paths = full_require_paths

    # gem directories must come after -I and ENV['RUBYLIB']
    insert_index = Gem.load_path_insert_index

    if insert_index then
      # gem directories must come after -I and ENV['RUBYLIB']
      $LOAD_PATH.insert(insert_index, *paths)
    else
      # we are probably testing in core, -I and RUBYLIB don't apply
      $LOAD_PATH.unshift(*paths)
    end
  end

  ##
  # Singular reader for #authors.  Returns the first author in the list

  def author
    val = authors and val.first
  end

  ##
  # The list of author names who wrote this gem.
  #
  #   spec.authors = ['Chad Fowler', 'Jim Weirich', 'Rich Kilmer']

  def authors
    @authors ||= []
  end

  ##
  # Returns the full path to installed gem's bin directory.
  #
  # NOTE: do not confuse this with +bindir+, which is just 'bin', not
  # a full path.

  def bin_dir
    @bin_dir ||= File.join gem_dir, bindir # TODO: this is unfortunate
  end

  ##
  # Returns the full path to an executable named +name+ in this gem.

  def bin_file name
    File.join bin_dir, name
  end

  ##
  # Returns the build_args used to install the gem

  def build_args
    if File.exist? build_info_file
      build_info = File.readlines build_info_file
      build_info = build_info.map { |x| x.strip }
      build_info.delete ""
      build_info
    else
      []
    end
  end

  ##
  # Builds extensions for this platform if the gem has extensions listed and
  # the gem.build_complete file is missing.

  def build_extensions # :nodoc:
    return if default_gem?
    return if extensions.empty?
    return if installed_by_version < Gem::Version.new('2.2.0.preview.2')
    return if File.exist? gem_build_complete_path
    return if !File.writable?(base_dir)
    return if !File.exist?(File.join(base_dir, 'extensions'))

    begin
      # We need to require things in $LOAD_PATH without looking for the
      # extension we are about to build.
      unresolved_deps = Gem::Specification.unresolved_deps.dup
      Gem::Specification.unresolved_deps.clear

      require 'rubygems/config_file'
      require 'rubygems/ext'
      require 'rubygems/user_interaction'

      ui = Gem::SilentUI.new
      Gem::DefaultUserInteraction.use_ui ui do
        builder = Gem::Ext::Builder.new self
        builder.build_extensions
      end
    ensure
      ui.close if ui
      Gem::Specification.unresolved_deps.replace unresolved_deps
    end
  end

  ##
  # Returns the full path to the build info directory

  def build_info_dir
    File.join base_dir, "build_info"
  end

  ##
  # Returns the full path to the file containing the build
  # information generated when the gem was installed

  def build_info_file
    File.join build_info_dir, "#{full_name}.info"
  end

  ##
  # Used to detect if the gem is bundled in older version of Ruby, but not
  # detectable as default gem (see BasicSpecification#default_gem?).

  def bundled_gem_in_old_ruby?
    !default_gem? &&
      RUBY_VERSION < "2.0.0" &&
      summary == "This #{name} is bundled with Ruby"
  end

  ##
  # Returns the full path to the cache directory containing this
  # spec's cached gem.

  def cache_dir
    @cache_dir ||= File.join base_dir, "cache"
  end

  ##
  # Returns the full path to the cached gem for this spec.

  def cache_file
    @cache_file ||= File.join cache_dir, "#{full_name}.gem"
  end

  ##
  # Return any possible conflicts against the currently loaded specs.

  def conflicts
    conflicts = {}
    self.runtime_dependencies.each { |dep|
      spec = Gem.loaded_specs[dep.name]
      if spec and not spec.satisfies_requirement? dep
        (conflicts[spec] ||= []) << dep
      end
    }
    conflicts
  end

  ##
  # return true if there will be conflict when spec if loaded together with the list of specs.

  def conficts_when_loaded_with?(list_of_specs) # :nodoc:
    result = list_of_specs.any? { |spec|
      spec.dependencies.any? { |dep| dep.runtime? && (dep.name == name) && !satisfies_requirement?(dep) }
    }
    result
  end

  ##
  # Return true if there are possible conflicts against the currently loaded specs.

  def has_conflicts?
    self.dependencies.any? { |dep|
      if dep.runtime? then
        spec = Gem.loaded_specs[dep.name]
        spec and not spec.satisfies_requirement? dep
      else
        false
      end
    }
  end

  ##
  # The date this gem was created.  Lazily defaults to the current UTC date.
  #
  # There is no need to set this in your gem specification.

  def date
    @date ||= TODAY
  end

  DateLike = Object.new # :nodoc:
  def DateLike.===(obj) # :nodoc:
    defined?(::Date) and Date === obj
  end

  DateTimeFormat = # :nodoc:
    /\A
     (\d{4})-(\d{2})-(\d{2})
     (\s+ \d{2}:\d{2}:\d{2}\.\d+ \s* (Z | [-+]\d\d:\d\d) )?
     \Z/x

  ##
  # The date this gem was created
  #
  # DO NOT set this, it is set automatically when the gem is packaged.

  def date= date
    # We want to end up with a Time object with one-day resolution.
    # This is the cleanest, most-readable, faster-than-using-Date
    # way to do it.
    @date = case date
            when String then
              if DateTimeFormat =~ date then
                Time.utc($1.to_i, $2.to_i, $3.to_i)

              # Workaround for where the date format output from psych isn't
              # parsed as a Time object by syck and thus comes through as a
              # string.
              elsif /\A(\d{4})-(\d{2})-(\d{2}) \d{2}:\d{2}:\d{2}\.\d+?Z\z/ =~ date then
                Time.utc($1.to_i, $2.to_i, $3.to_i)
              else
                raise(Gem::InvalidSpecificationException,
                      "invalid date format in specification: #{date.inspect}")
              end
            when Time, DateLike then
              Time.utc(date.year, date.month, date.day)
            else
              TODAY
            end
  end

  ##
  # The default executable for this gem.
  #
  # Deprecated: The name of the gem is assumed to be the name of the
  # executable now.  See Gem.bin_path.

  def default_executable # :nodoc:
    if defined?(@default_executable) and @default_executable
      result = @default_executable
    elsif @executables and @executables.size == 1
      result = Array(@executables).first
    else
      result = nil
    end
    result
  end

  ##
  # The default value for specification attribute +name+

  def default_value name
    @@default_value[name]
  end

  ##
  # A list of Gem::Dependency objects this gem depends on.
  #
  # Use #add_dependency or #add_development_dependency to add dependencies to
  # a gem.

  def dependencies
    @dependencies ||= []
  end

  ##
  # Return a list of all gems that have a dependency on this gemspec.  The
  # list is structured with entries that conform to:
  #
  #   [depending_gem, dependency, [list_of_gems_that_satisfy_dependency]]

  def dependent_gems
    out = []
    Gem::Specification.each do |spec|
      spec.dependencies.each do |dep|
        if self.satisfies_requirement?(dep) then
          sats = []
          find_all_satisfiers(dep) do |sat|
            sats << sat
          end
          out << [spec, dep, sats]
        end
      end
    end
    out
  end

  ##
  # Returns all specs that matches this spec's runtime dependencies.

  def dependent_specs
    runtime_dependencies.map { |dep| dep.to_specs }.flatten
  end

  ##
  # A detailed description of this gem.  See also #summary

  def description= str
    @description = str.to_s
  end

  ##
  # List of dependencies that are used for development

  def development_dependencies
    dependencies.select { |d| d.type == :development }
  end

  ##
  # Returns the full path to this spec's documentation directory.  If +type+
  # is given it will be appended to the end.  For example:
  #
  #   spec.doc_dir      # => "/path/to/gem_repo/doc/a-1"
  #
  #   spec.doc_dir 'ri' # => "/path/to/gem_repo/doc/a-1/ri"

  def doc_dir type = nil
    @doc_dir ||= File.join base_dir, 'doc', full_name

    if type then
      File.join @doc_dir, type
    else
      @doc_dir
    end
  end

  def encode_with coder # :nodoc:
    mark_version

    coder.add 'name', @name
    coder.add 'version', @version
    platform = case @original_platform
               when nil, '' then
                 'ruby'
               when String then
                 @original_platform
               else
                 @original_platform.to_s
               end
    coder.add 'platform', platform

    attributes = @@attributes.map(&:to_s) - %w[name version platform]
    attributes.each do |name|
      coder.add name, instance_variable_get("@#{name}")
    end
  end

  def eql? other # :nodoc:
    self.class === other && same_attributes?(other)
  end

  ##
  # Singular accessor for #executables

  def executable
    val = executables and val.first
  end

  ##
  # Singular accessor for #executables

  def executable=o
    self.executables = [o]
  end

  ##
  # Sets executables to +value+, ensuring it is an array. Don't
  # use this, push onto the array instead.

  def executables= value
    # TODO: warn about setting instead of pushing
    @executables = Array(value)
  end

  ##
  # Sets extensions to +extensions+, ensuring it is an array. Don't
  # use this, push onto the array instead.

  def extensions= extensions
    # TODO: warn about setting instead of pushing
    @extensions = Array extensions
  end

  ##
  # Sets extra_rdoc_files to +files+, ensuring it is an array. Don't
  # use this, push onto the array instead.

  def extra_rdoc_files= files
    # TODO: warn about setting instead of pushing
    @extra_rdoc_files = Array files
  end

  ##
  # The default (generated) file name of the gem.  See also #spec_name.
  #
  #   spec.file_name # => "example-1.0.gem"

  def file_name
    "#{full_name}.gem"
  end

  ##
  # Sets files to +files+, ensuring it is an array.

  def files= files
    @files = Array files
  end

  ##
  # Finds all gems that satisfy +dep+

  def find_all_satisfiers dep
    Gem::Specification.each do |spec|
      yield spec if spec.satisfies_requirement? dep
    end
  end

  private :find_all_satisfiers

  ##
  # Creates a duplicate spec without large blobs that aren't used at runtime.

  def for_cache
    spec = dup

    spec.files = nil
    spec.test_files = nil

    spec
  end

  def full_name
    @full_name ||= super
  end

  ##
  # Work around bundler removing my methods

  def gem_dir # :nodoc:
    super
  end

  def gems_dir
    # TODO: this logic seems terribly broken, but tests fail if just base_dir
    @gems_dir ||= File.join(loaded_from && base_dir || Gem.dir, "gems")
  end

  ##
  # Deprecated and ignored, defaults to true.
  #
  # Formerly used to indicate this gem was RDoc-capable.

  def has_rdoc # :nodoc:
    true
  end

  ##
  # Deprecated and ignored.
  #
  # Formerly used to indicate this gem was RDoc-capable.

  def has_rdoc= ignored # :nodoc:
    @has_rdoc = true
  end

  alias :has_rdoc? :has_rdoc # :nodoc:

  ##
  # True if this gem has files in test_files

  def has_unit_tests? # :nodoc:
    not test_files.empty?
  end

  # :stopdoc:
  alias has_test_suite? has_unit_tests?
  # :startdoc:

  def hash # :nodoc:
    name.hash ^ version.hash
  end

  def init_with coder # :nodoc:
    @installed_by_version ||= nil
    yaml_initialize coder.tag, coder.map
  end

  ##
  # Specification constructor. Assigns the default values to the attributes
  # and yields itself for further initialization.  Optionally takes +name+ and
  # +version+.

  def initialize name = nil, version = nil
    super()
    @gems_dir              = nil
    @base_dir              = nil
    @loaded = false
    @activated = false
    @loaded_from = nil
    @original_platform = nil
    @installed_by_version = nil

    @@nil_attributes.each do |key|
      instance_variable_set "@#{key}", nil
    end

    @@non_nil_attributes.each do |key|
      default = default_value(key)
      value = Dupable[key] ? default.dup : default
      instance_variable_set "@#{key}", value
    end

    @new_platform = Gem::Platform::RUBY

    self.name = name if name
    self.version = version if version

    yield self if block_given?
  end

  ##
  # Duplicates array_attributes from +other_spec+ so state isn't shared.

  def initialize_copy other_spec
    self.class.array_attributes.each do |name|
      name = :"@#{name}"
      next unless other_spec.instance_variable_defined? name

      begin
        val = other_spec.instance_variable_get(name)
        if val then
          instance_variable_set name, val.dup
        elsif Gem.configuration.really_verbose
          warn "WARNING: #{full_name} has an invalid nil value for #{name}"
        end
      rescue TypeError
        e = Gem::FormatException.new \
          "#{full_name} has an invalid value for #{name}"

        e.file_path = loaded_from
        raise e
      end
    end
  end

  def base_dir
    return Gem.dir unless loaded_from
    @base_dir ||= if default_gem? then
                    File.dirname File.dirname File.dirname loaded_from
                  else
                    File.dirname File.dirname loaded_from
                  end
  end

  ##
  # Expire memoized instance variables that can incorrectly generate, replace
  # or miss files due changes in certain attributes used to compute them.

  def invalidate_memoized_attributes
    @full_name = nil
    @cache_file = nil
  end

  private :invalidate_memoized_attributes

  def inspect # :nodoc:
    if $DEBUG
      super
    else
      "#<#{self.class}:0x#{__id__.to_s(16)} #{full_name}>"
    end
  end

  ##
  # Files in the Gem under one of the require_paths

  def lib_files
    @files.select do |file|
      require_paths.any? do |path|
        file.start_with? path
      end
    end
  end

  ##
  # Singular accessor for #licenses

  def license
    licenses.first
  end

  ##
  # Plural accessor for setting licenses
  #
  # See #license= for details

  def licenses
    @licenses ||= []
  end

  def internal_init # :nodoc:
    super
    @bin_dir       = nil
    @cache_dir     = nil
    @cache_file    = nil
    @doc_dir       = nil
    @ri_dir        = nil
    @spec_dir      = nil
    @spec_file     = nil
  end

  ##
  # Sets the rubygems_version to the current RubyGems version.

  def mark_version
    @rubygems_version = Gem::VERSION
  end

  ##
  # Warn about unknown attributes while loading a spec.

  def method_missing(sym, *a, &b) # :nodoc:
    if @specification_version > CURRENT_SPECIFICATION_VERSION and
      sym.to_s =~ /=$/ then
      warn "ignoring #{sym} loading #{full_name}" if $DEBUG
    else
      super
    end
  end

  ##
  # Is this specification missing its extensions?  When this returns true you
  # probably want to build_extensions

  def missing_extensions?
    return false if default_gem?
    return false if extensions.empty?
    return false if installed_by_version < Gem::Version.new('2.2.0.preview.2')
    return false if File.exist? gem_build_complete_path

    true
  end

  ##
  # Normalize the list of files so that:
  # * All file lists have redundancies removed.
  # * Files referenced in the extra_rdoc_files are included in the package
  #   file list.

  def normalize
    if defined?(@extra_rdoc_files) and @extra_rdoc_files then
      @extra_rdoc_files.uniq!
      @files ||= []
      @files.concat(@extra_rdoc_files)
    end

    @files            = @files.uniq if @files
    @extensions       = @extensions.uniq if @extensions
    @test_files       = @test_files.uniq if @test_files
    @executables      = @executables.uniq if @executables
    @extra_rdoc_files = @extra_rdoc_files.uniq if @extra_rdoc_files
  end

  ##
  # Return a NameTuple that represents this Specification

  def name_tuple
    Gem::NameTuple.new name, version, original_platform
  end

  ##
  # Returns the full name (name-version) of this gemspec using the original
  # platform.  For use with legacy gems.

  def original_name # :nodoc:
    if platform == Gem::Platform::RUBY or platform.nil? then
      "#{@name}-#{@version}"
    else
      "#{@name}-#{@version}-#{@original_platform}"
    end
  end

  ##
  # Cruft. Use +platform+.

  def original_platform # :nodoc:
    @original_platform ||= platform
  end

  ##
  # The platform this gem runs on.  See Gem::Platform for details.

  def platform
    @new_platform ||= Gem::Platform::RUBY
  end

  def pretty_print(q) # :nodoc:
    q.group 2, 'Gem::Specification.new do |s|', 'end' do
      q.breakable

      attributes = @@attributes - [:name, :version]
      attributes.unshift :installed_by_version
      attributes.unshift :version
      attributes.unshift :name

      attributes.each do |attr_name|
        current_value = self.send attr_name
        if current_value != default_value(attr_name) or
           self.class.required_attribute? attr_name then

          q.text "s.#{attr_name} = "

          if attr_name == :date then
            current_value = current_value.utc

            q.text "Time.utc(#{current_value.year}, #{current_value.month}, #{current_value.day})"
          else
            q.pp current_value
          end

          q.breakable
        end
      end
    end
  end

  ##
  # Raise an exception if the version of this spec conflicts with the one
  # that is already loaded (+other+)

  def check_version_conflict other # :nodoc:
    return if self.version == other.version

    # This gem is already loaded.  If the currently loaded gem is not in the
    # list of candidate gems, then we have a version conflict.

    msg = "can't activate #{full_name}, already activated #{other.full_name}"

    e = Gem::LoadError.new msg
    e.name = self.name
    # TODO: e.requirement = dep.requirement

    raise e
  end

  private :check_version_conflict

  ##
  # Check the spec for possible conflicts and freak out if there are any.

  def raise_if_conflicts # :nodoc:
    if has_conflicts? then
      raise Gem::ConflictError.new self, conflicts
    end
  end

  ##
  # Sets rdoc_options to +value+, ensuring it is an array. Don't
  # use this, push onto the array instead.

  def rdoc_options= options
    # TODO: warn about setting instead of pushing
    @rdoc_options = Array options
  end

  ##
  # Singular accessor for #require_paths

  def require_path
    val = require_paths and val.first
  end

  ##
  # Singular accessor for #require_paths

  def require_path= path
    self.require_paths = Array(path)
  end

  ##
  # Set requirements to +req+, ensuring it is an array. Don't
  # use this, push onto the array instead.

  def requirements= req
    # TODO: warn about setting instead of pushing
    @requirements = Array req
  end

  def respond_to_missing? m, include_private = false # :nodoc:
    false
  end

  ##
  # Returns the full path to this spec's ri directory.

  def ri_dir
    @ri_dir ||= File.join base_dir, 'ri', full_name
  end

  ##
  # Return a string containing a Ruby code representation of the given
  # object.

  def ruby_code(obj)
    case obj
    when String            then obj.dump + ".freeze"
    when Array             then '[' + obj.map { |x| ruby_code x }.join(", ") + ']'
    when Hash              then
      seg = obj.keys.sort.map { |k| "#{k.to_s.dump} => #{obj[k].to_s.dump}" }
      "{ #{seg.join(', ')} }"
    when Gem::Version      then obj.to_s.dump
    when DateLike          then obj.strftime('%Y-%m-%d').dump
    when Time              then obj.strftime('%Y-%m-%d').dump
    when Numeric           then obj.inspect
    when true, false, nil  then obj.inspect
    when Gem::Platform     then "Gem::Platform.new(#{obj.to_a.inspect})"
    when Gem::Requirement  then
      list = obj.as_list
      "Gem::Requirement.new(#{ruby_code(list.size == 1 ? obj.to_s : list)})"
    else raise Gem::Exception, "ruby_code case not handled: #{obj.class}"
    end
  end

  private :ruby_code

  ##
  # List of dependencies that will automatically be activated at runtime.

  def runtime_dependencies
    dependencies.select(&:runtime?)
  end

  ##
  # True if this gem has the same attributes as +other+.

  def same_attributes? spec
    @@attributes.all? { |name, default| self.send(name) == spec.send(name) }
  end

  private :same_attributes?

  ##
  # Checks if this specification meets the requirement of +dependency+.

  def satisfies_requirement? dependency
    return @name == dependency.name &&
      dependency.requirement.satisfied_by?(@version)
  end

  ##
  # Returns an object you can use to sort specifications in #sort_by.

  def sort_obj
    [@name, @version, @new_platform == Gem::Platform::RUBY ? -1 : 1]
  end

  ##
  # Used by Gem::Resolver to order Gem::Specification objects

  def source # :nodoc:
    Gem::Source::Installed.new
  end

  ##
  # Returns the full path to the directory containing this spec's
  # gemspec file. eg: /usr/local/lib/ruby/gems/1.8/specifications

  def spec_dir
    @spec_dir ||= File.join base_dir, "specifications"
  end

  ##
  # Returns the full path to this spec's gemspec file.
  # eg: /usr/local/lib/ruby/gems/1.8/specifications/mygem-1.0.gemspec

  def spec_file
    @spec_file ||= File.join spec_dir, "#{full_name}.gemspec"
  end

  ##
  # The default name of the gemspec.  See also #file_name
  #
  #   spec.spec_name # => "example-1.0.gemspec"

  def spec_name
    "#{full_name}.gemspec"
  end

  ##
  # A short summary of this gem's description.

  def summary= str
    @summary = str.to_s.strip.
      gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').gsub(/\n[ \t]*/, " ") # so. weird.
  end

  ##
  # Singular accessor for #test_files

  def test_file # :nodoc:
    val = test_files and val.first
  end

  ##
  # Singular mutator for #test_files

  def test_file= file # :nodoc:
    self.test_files = [file]
  end

  ##
  # Test files included in this gem.  You cannot append to this accessor, you
  # must assign to it.

  def test_files # :nodoc:
    # Handle the possibility that we have @test_suite_file but not
    # @test_files.  This will happen when an old gem is loaded via
    # YAML.
    if defined? @test_suite_file then
      @test_files = [@test_suite_file].flatten
      @test_suite_file = nil
    end
    if defined?(@test_files) and @test_files then
      @test_files
    else
      @test_files = []
    end
  end

  ##
  # Returns a Ruby code representation of this specification, such that it can
  # be eval'ed and reconstruct the same specification later.  Attributes that
  # still have their default values are omitted.

  def to_ruby
    mark_version
    result = []
    result << "# -*- encoding: utf-8 -*-"
    result << "#{Gem::StubSpecification::PREFIX}#{name} #{version} #{platform} #{raw_require_paths.join("\0")}"
    result << "#{Gem::StubSpecification::PREFIX}#{extensions.join "\0"}" unless
      extensions.empty?
    result << nil
    result << "Gem::Specification.new do |s|"

    result << "  s.name = #{ruby_code name}"
    result << "  s.version = #{ruby_code version}"
    unless platform.nil? or platform == Gem::Platform::RUBY then
      result << "  s.platform = #{ruby_code original_platform}"
    end
    result << ""
    result << "  s.required_rubygems_version = #{ruby_code required_rubygems_version} if s.respond_to? :required_rubygems_version="

    if metadata and !metadata.empty?
      result << "  s.metadata = #{ruby_code metadata} if s.respond_to? :metadata="
    end
    result << "  s.require_paths = #{ruby_code raw_require_paths}"

    handled = [
      :dependencies,
      :name,
      :platform,
      :require_paths,
      :required_rubygems_version,
      :specification_version,
      :version,
      :has_rdoc,
      :default_executable,
      :metadata
    ]

    @@attributes.each do |attr_name|
      next if handled.include? attr_name
      current_value = self.send(attr_name)
      if current_value != default_value(attr_name) or
         self.class.required_attribute? attr_name then
        result << "  s.#{attr_name} = #{ruby_code current_value}"
      end
    end

    if @installed_by_version then
      result << nil
      result << "  s.installed_by_version = \"#{Gem::VERSION}\" if s.respond_to? :installed_by_version"
    end

    unless dependencies.empty? then
      result << nil
      result << "  if s.respond_to? :specification_version then"
      result << "    s.specification_version = #{specification_version}"
      result << nil

      result << "    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then"

      dependencies.each do |dep|
        req = dep.requirements_list.inspect
        dep.instance_variable_set :@type, :runtime if dep.type.nil? # HACK
        result << "      s.add_#{dep.type}_dependency(%q<#{dep.name}>.freeze, #{req})"
      end

      result << "    else"

      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "      s.add_dependency(%q<#{dep.name}>.freeze, #{version_reqs_param})"
      end

      result << '    end'

      result << "  else"
      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "    s.add_dependency(%q<#{dep.name}>.freeze, #{version_reqs_param})"
      end
      result << "  end"
    end

    result << "end"
    result << nil

    result.join "\n"
  end

  ##
  # Returns a Ruby lighter-weight code representation of this specification,
  # used for indexing only.
  #
  # See #to_ruby.

  def to_ruby_for_cache
    for_cache.to_ruby
  end

  def to_s # :nodoc:
    "#<Gem::Specification name=#{@name} version=#{@version}>"
  end

  ##
  # Returns self

  def to_spec
    self
  end

  def to_yaml(opts = {}) # :nodoc:
    if (YAML.const_defined?(:ENGINE) && !YAML::ENGINE.syck?) ||
        (defined?(Psych) && YAML == Psych) then
      # Because the user can switch the YAML engine behind our
      # back, we have to check again here to make sure that our
      # psych code was properly loaded, and load it if not.
      unless Gem.const_defined?(:NoAliasYAMLTree)
        require 'rubygems/psych_tree'
      end

      builder = Gem::NoAliasYAMLTree.create
      builder << self
      ast = builder.tree

      io = StringIO.new
      io.set_encoding Encoding::UTF_8 if Object.const_defined? :Encoding

      Psych::Visitors::Emitter.new(io).accept(ast)

      io.string.gsub(/ !!null \n/, " \n")
    else
      YAML.quick_emit object_id, opts do |out|
        out.map taguri, to_yaml_style do |map|
          encode_with map
        end
      end
    end
  end

  ##
  # Recursively walk dependencies of this spec, executing the +block+ for each
  # hop.

  def traverse trail = [], visited = {}, &block
    trail.push(self)
    begin
      dependencies.each do |dep|
        next unless dep.runtime?
        dep.to_specs.reverse_each do |dep_spec|
          next if visited.has_key?(dep_spec)
          visited[dep_spec] = true
          trail.push(dep_spec)
          begin
            result = block[self, dep, dep_spec, trail]
          ensure
            trail.pop
          end
          unless result == :next
            spec_name = dep_spec.name
            dep_spec.traverse(trail, visited, &block) unless
              trail.any? { |s| s.name == spec_name }
          end
        end
      end
    ensure
      trail.pop
    end
  end

  ##
  # Checks that the specification contains all required fields, and does a
  # very basic sanity check.
  #
  # Raises InvalidSpecificationException if the spec does not pass the
  # checks..

  def validate packaging = true
    @warnings = 0
    require 'rubygems/user_interaction'
    extend Gem::UserInteraction
    normalize

    nil_attributes = self.class.non_nil_attributes.find_all do |attrname|
      instance_variable_get("@#{attrname}").nil?
    end

    unless nil_attributes.empty? then
      raise Gem::InvalidSpecificationException,
        "#{nil_attributes.join ', '} must not be nil"
    end

    if packaging and rubygems_version != Gem::VERSION then
      raise Gem::InvalidSpecificationException,
            "expected RubyGems version #{Gem::VERSION}, was #{rubygems_version}"
    end

    @@required_attributes.each do |symbol|
      unless self.send symbol then
        raise Gem::InvalidSpecificationException,
              "missing value for attribute #{symbol}"
      end
    end

    if !name.is_a?(String) then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: \"#{name.inspect}\" must be a string"
    elsif name !~ /[a-zA-Z]/ then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: #{name.dump} must include at least one letter"
    elsif name !~ VALID_NAME_PATTERN then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: #{name.dump} can only include letters, numbers, dashes, and underscores"
    end

    if raw_require_paths.empty? then
      raise Gem::InvalidSpecificationException,
            'specification must have at least one require_path'
    end

    @files.delete_if            { |x| File.directory?(x) && !File.symlink?(x) }
    @test_files.delete_if       { |x| File.directory?(x) && !File.symlink?(x) }
    @executables.delete_if      { |x| File.directory?(File.join(@bindir, x)) }
    @extra_rdoc_files.delete_if { |x| File.directory?(x) && !File.symlink?(x) }
    @extensions.delete_if       { |x| File.directory?(x) && !File.symlink?(x) }

    non_files = files.reject { |x| File.file?(x) || File.symlink?(x) }

    unless not packaging or non_files.empty? then
      raise Gem::InvalidSpecificationException,
            "[\"#{non_files.join "\", \""}\"] are not files"
    end

    if files.include? file_name then
      raise Gem::InvalidSpecificationException,
            "#{full_name} contains itself (#{file_name}), check your files list"
    end

    unless specification_version.is_a?(Fixnum)
      raise Gem::InvalidSpecificationException,
            'specification_version must be a Fixnum (did you mean version?)'
    end

    case platform
    when Gem::Platform, Gem::Platform::RUBY then # ok
    else
      raise Gem::InvalidSpecificationException,
            "invalid platform #{platform.inspect}, see Gem::Platform"
    end

    self.class.array_attributes.each do |field|
      val = self.send field
      klass = case field
              when :dependencies
                Gem::Dependency
              else
                String
              end

      unless Array === val and val.all? { |x| x.kind_of?(klass) } then
        raise(Gem::InvalidSpecificationException,
              "#{field} must be an Array of #{klass}")
      end
    end

    [:authors].each do |field|
      val = self.send field
      raise Gem::InvalidSpecificationException, "#{field} may not be empty" if
        val.empty?
    end

    unless Hash === metadata
      raise Gem::InvalidSpecificationException,
              'metadata must be a hash'
    end

    metadata.keys.each do |k|
      if !k.kind_of?(String)
        raise Gem::InvalidSpecificationException,
                'metadata keys must be a String'
      end

      if k.size > 128
        raise Gem::InvalidSpecificationException,
                "metadata key too large (#{k.size} > 128)"
      end
    end

    metadata.values.each do |k|
      if !k.kind_of?(String)
        raise Gem::InvalidSpecificationException,
                'metadata values must be a String'
      end

      if k.size > 1024
        raise Gem::InvalidSpecificationException,
                "metadata value too large (#{k.size} > 1024)"
      end
    end

    licenses.each { |license|
      if license.length > 64
        raise Gem::InvalidSpecificationException,
          "each license must be 64 characters or less"
      end

      if !Gem::Licenses.match?(license)
        suggestions = Gem::Licenses.suggestions(license)
        message = <<-warning
license value '#{license}' is invalid.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
        warning
        message += "Did you mean #{suggestions.map { |s| "'#{s}'"}.join(', ')}?\n" unless suggestions.nil?
        warning(message)
      end
    }

    warning <<-warning if licenses.empty?
licenses is empty, but is recommended.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
    warning

    validate_permissions

    # reject lazy developers:

    lazy = '"FIxxxXME" or "TOxxxDO"'.gsub(/xxx/, '')

    unless authors.grep(/FI XME|TO DO/x).empty? then
      raise Gem::InvalidSpecificationException, "#{lazy} is not an author"
    end

    unless Array(email).grep(/FI XME|TO DO/x).empty? then
      raise Gem::InvalidSpecificationException, "#{lazy} is not an email"
    end

    if description =~ /FI XME|TO DO/x then
      raise Gem::InvalidSpecificationException, "#{lazy} is not a description"
    end

    if summary =~ /FI XME|TO DO/x then
      raise Gem::InvalidSpecificationException, "#{lazy} is not a summary"
    end

    if homepage and not homepage.empty? and
       homepage !~ /\A[a-z][a-z\d+.-]*:/i then
      raise Gem::InvalidSpecificationException,
            "\"#{homepage}\" is not a URI"
    end

    # Warnings

    %w[author email homepage summary].each do |attribute|
      value = self.send attribute
      warning "no #{attribute} specified" if value.nil? or value.empty?
    end

    if description == summary then
      warning 'description and summary are identical'
    end

    # TODO: raise at some given date
    warning "deprecated autorequire specified" if autorequire

    executables.each do |executable|
      executable_path = File.join(bindir, executable)
      shebang = File.read(executable_path, 2) == '#!'

      warning "#{executable_path} is missing #! line" unless shebang
    end

    files.each do |file|
      next unless File.symlink?(file)
      warning "#{file} is a symlink, which is not supported on all platforms"
    end

    validate_dependencies

    true
  ensure
    if $! or @warnings > 0 then
      alert_warning "See http://guides.rubygems.org/specification-reference/ for help"
    end
  end

  ##
  # Checks that dependencies use requirements as we recommend.  Warnings are
  # issued when dependencies are open-ended or overly strict for semantic
  # versioning.

  def validate_dependencies # :nodoc:
    # NOTE: see REFACTOR note in Gem::Dependency about types - this might be brittle
    seen = Gem::Dependency::TYPES.inject({}) { |types, type| types.merge({ type => {}}) }

    error_messages = []
    warning_messages = []
    dependencies.each do |dep|
      if prev = seen[dep.type][dep.name] then
        error_messages << <<-MESSAGE
duplicate dependency on #{dep}, (#{prev.requirement}) use:
    add_#{dep.type}_dependency '#{dep.name}', '#{dep.requirement}', '#{prev.requirement}'
        MESSAGE
      end

      seen[dep.type][dep.name] = dep

      prerelease_dep = dep.requirements_list.any? do |req|
        Gem::Requirement.new(req).prerelease?
      end

      warning_messages << "prerelease dependency on #{dep} is not recommended" if
        prerelease_dep && !version.prerelease?

      overly_strict = dep.requirement.requirements.length == 1 &&
        dep.requirement.requirements.any? do |op, version|
          op == '~>' and
            not version.prerelease? and
            version.segments.length > 2 and
            version.segments.first != 0
        end

      if overly_strict then
        _, dep_version = dep.requirement.requirements.first

        base = dep_version.segments.first 2

        warning_messages << <<-WARNING
pessimistic dependency on #{dep} may be overly strict
  if #{dep.name} is semantically versioned, use:
    add_#{dep.type}_dependency '#{dep.name}', '~> #{base.join '.'}', '>= #{dep_version}'
        WARNING
      end

      open_ended = dep.requirement.requirements.all? do |op, version|
        not version.prerelease? and (op == '>' or op == '>=')
      end

      if open_ended then
        op, dep_version = dep.requirement.requirements.first

        base = dep_version.segments.first 2

        bugfix = if op == '>' then
                   ", '> #{dep_version}'"
                 elsif op == '>=' and base != dep_version.segments then
                   ", '>= #{dep_version}'"
                 end

        warning_messages << <<-WARNING
open-ended dependency on #{dep} is not recommended
  if #{dep.name} is semantically versioned, use:
    add_#{dep.type}_dependency '#{dep.name}', '~> #{base.join '.'}'#{bugfix}
        WARNING
      end
    end
    if error_messages.any?
      raise Gem::InvalidSpecificationException, error_messages.join
    end
    if warning_messages.any?
      warning_messages.each { |warning_message| warning warning_message }
    end
  end

  ##
  # Checks to see if the files to be packaged are world-readable.

  def validate_permissions
    return if Gem.win_platform?

    files.each do |file|
      next unless File.file?(file)
      next if File.stat(file).mode & 0444 == 0444
      warning "#{file} is not world-readable"
    end

    executables.each do |name|
      exec = File.join @bindir, name
      next unless File.file?(exec)
      next if File.stat(exec).executable?
      warning "#{exec} is not executable"
    end
  end

  ##
  # Set the version to +version+, potentially also setting
  # required_rubygems_version if +version+ indicates it is a
  # prerelease.

  def version= version
    @version = Gem::Version.create(version)
    self.required_rubygems_version = '> 1.3.1' if @version.prerelease?
    invalidate_memoized_attributes

    return @version
  end

  def stubbed?
    false
  end

  def yaml_initialize(tag, vals) # :nodoc:
    vals.each do |ivar, val|
      case ivar
      when "date"
        # Force Date to go through the extra coerce logic in date=
        self.date = val.untaint
      else
        instance_variable_set "@#{ivar}", val.untaint
      end
    end

    @original_platform = @platform # for backwards compatibility
    self.platform = Gem::Platform.new @platform
  end

  ##
  # Reset nil attributes to their default values to make the spec valid

  def reset_nil_attributes_to_default
    nil_attributes = self.class.non_nil_attributes.find_all do |name|
      !instance_variable_defined?("@#{name}") || instance_variable_get("@#{name}").nil?
    end

    nil_attributes.each do |attribute|
      default = self.default_value attribute

      value = case default
              when Time, Numeric, Symbol, true, false, nil then default
              else default.dup
              end

      instance_variable_set "@#{attribute}", value
    end

    @installed_by_version ||= nil
  end

  def warning statement # :nodoc:
    @warnings += 1

    alert_warning statement
  end

  def raw_require_paths # :nodoc:
    @require_paths
  end

  extend Gem::Deprecate

  # TODO:
  # deprecate :has_rdoc,            :none,       2011, 10
  # deprecate :has_rdoc?,           :none,       2011, 10
  # deprecate :has_rdoc=,           :none,       2011, 10
  # deprecate :default_executable,  :none,       2011, 10
  # deprecate :default_executable=, :none,       2011, 10
  # deprecate :file_name,           :cache_file, 2011, 10
  # deprecate :full_gem_path,     :cache_file, 2011, 10
end

# DOC: What is this and why is it here, randomly, at the end of this file?
Gem.clear_paths
