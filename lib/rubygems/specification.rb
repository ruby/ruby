#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'
require 'rubygems/version'
require 'rubygems/platform'

# :stopdoc:
# Time::today has been deprecated in 0.9.5 and will be removed.
if RUBY_VERSION < '1.9' then
  def Time.today
    t = Time.now
    t - ((t.to_i + t.gmt_offset) % 86400)
  end unless defined? Time.today
end
# :startdoc:

module Gem

  # == Gem::Specification
  #
  # The Specification class contains the metadata for a Gem.  Typically
  # defined in a .gemspec file or a Rakefile, and looks like this:
  #
  #   spec = Gem::Specification.new do |s|
  #     s.name = 'rfoo'
  #     s.version = '1.0'
  #     s.summary = 'Example gem specification'
  #     ...
  #   end
  #
  # There are many <em>gemspec attributes</em>, and the best place to learn
  # about them in the "Gemspec Reference" linked from the RubyGems wiki.
  #
  class Specification

    # Allows deinstallation of gems with legacy platforms.
    attr_accessor :original_platform # :nodoc:

    # ------------------------- Specification version contstants.

    # The the version number of a specification that does not specify one
    # (i.e. RubyGems 0.7 or earlier).
    NONEXISTENT_SPECIFICATION_VERSION = -1

    # The specification version applied to any new Specification instances
    # created.  This should be bumped whenever something in the spec format
    # changes.
    CURRENT_SPECIFICATION_VERSION = 2

    # An informal list of changes to the specification.  The highest-valued
    # key should be equal to the CURRENT_SPECIFICATION_VERSION.
    SPECIFICATION_VERSION_HISTORY = {
      -1 => ['(RubyGems versions up to and including 0.7 did not have versioned specifications)'],
      1  => [
        'Deprecated "test_suite_file" in favor of the new, but equivalent, "test_files"',
        '"test_file=x" is a shortcut for "test_files=[x]"'
      ],
      2  => [
        'Added "required_rubygems_version"',
        'Now forward-compatible with future versions',
      ],
    }

    # :stopdoc:
    MARSHAL_FIELDS = { -1 => 16, 1 => 16, 2 => 16 }

    now = Time.at(Time.now.to_i)
    TODAY = now - ((now.to_i + now.gmt_offset) % 86400)
    # :startdoc:

    # ------------------------- Class variables.

    # List of Specification instances.
    @@list = []

    # Optional block used to gather newly defined instances.
    @@gather = nil

    # List of attribute names: [:name, :version, ...]
    @@required_attributes = []

    # List of _all_ attributes and default values: [[:name, nil], [:bindir, 'bin'], ...]
    @@attributes = []

    @@nil_attributes = []
    @@non_nil_attributes = [:@original_platform]

    # List of array attributes
    @@array_attributes = []

    # Map of attribute names to default values.
    @@default_value = {}

    # ------------------------- Convenience class methods.

    def self.attribute_names
      @@attributes.map { |name, default| name }
    end

    def self.attribute_defaults
      @@attributes.dup
    end

    def self.default_value(name)
      @@default_value[name]
    end

    def self.required_attributes
      @@required_attributes.dup
    end

    def self.required_attribute?(name)
      @@required_attributes.include? name.to_sym
    end

    def self.array_attributes
      @@array_attributes.dup
    end

    # ------------------------- Infrastructure class methods.

    # A list of Specification instances that have been defined in this Ruby instance.
    def self.list
      @@list
    end

    # Used to specify the name and default value of a specification
    # attribute.  The side effects are:
    # * the name and default value are added to the @@attributes list
    #   and @@default_value map
    # * a standard _writer_ method (<tt>attribute=</tt>) is created
    # * a non-standard _reader method (<tt>attribute</tt>) is created
    #
    # The reader method behaves like this:
    #   def attribute
    #     @attribute ||= (copy of default value)
    #   end
    #
    # This allows lazy initialization of attributes to their default
    # values. 
    #
    def self.attribute(name, default=nil)
      ivar_name = "@#{name}".intern
      if default.nil? then
        @@nil_attributes << ivar_name
      else
        @@non_nil_attributes << [ivar_name, default]
      end

      @@attributes << [name, default]
      @@default_value[name] = default
      attr_accessor(name)
    end

    # Same as :attribute, but ensures that values assigned to the
    # attribute are array values by applying :to_a to the value.
    def self.array_attribute(name)
      @@non_nil_attributes << ["@#{name}".intern, []]

      @@array_attributes << name
      @@attributes << [name, []]
      @@default_value[name] = []
      code = %{
        def #{name}
          @#{name} ||= []
        end
        def #{name}=(value)
          @#{name} = Array(value)
        end
      }

      module_eval code, __FILE__, __LINE__ - 9
    end

    # Same as attribute above, but also records this attribute as mandatory.
    def self.required_attribute(*args)
      @@required_attributes << args.first
      attribute(*args)
    end

    # Sometimes we don't want the world to use a setter method for a particular attribute.
    # +read_only+ makes it private so we can still use it internally.
    def self.read_only(*names)
      names.each do |name|
        private "#{name}="
      end
    end

    # Shortcut for creating several attributes at once (each with a default value of
    # +nil+).
    def self.attributes(*args)
      args.each do |arg|
        attribute(arg, nil)
      end
    end

    # Some attributes require special behaviour when they are accessed.  This allows for
    # that.
    def self.overwrite_accessor(name, &block)
      remove_method name
      define_method(name, &block)
    end

    # Defines a _singular_ version of an existing _plural_ attribute
    # (i.e. one whose value is expected to be an array).  This means
    # just creating a helper method that takes a single value and
    # appends it to the array.  These are created for convenience, so
    # that in a spec, one can write 
    #
    #   s.require_path = 'mylib'
    #
    # instead of
    #
    #   s.require_paths = ['mylib']
    #
    # That above convenience is available courtesy of
    #
    #   attribute_alias_singular :require_path, :require_paths 
    #
    def self.attribute_alias_singular(singular, plural)
      define_method("#{singular}=") { |val|
        send("#{plural}=", [val])
      }
      define_method("#{singular}") { 
        val = send("#{plural}")
        val.nil? ? nil : val.first
      }
    end

    # Dump only crucial instance variables.
    #
    # MAINTAIN ORDER!
    def _dump(limit) # :nodoc:
      Marshal.dump [
        @rubygems_version,
        @specification_version,
        @name,
        @version,
        (Time === @date ? @date : (require 'time'; Time.parse(@date.to_s))),
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
        @has_rdoc,
        @new_platform,
      ]
    end

    # Load custom marshal format, re-initializing defaults as needed
    def self._load(str)
      array = Marshal.load str

      spec = Gem::Specification.new
      spec.instance_variable_set :@specification_version, array[1]

      current_version = CURRENT_SPECIFICATION_VERSION

      field_count = MARSHAL_FIELDS[spec.specification_version]

      if field_count.nil? or array.size < field_count then
        raise TypeError, "invalid Gem::Specification format #{array.inspect}"
      end

      spec.instance_variable_set :@rubygems_version,          array[0]
      # spec version
      spec.instance_variable_set :@name,                      array[2]
      spec.instance_variable_set :@version,                   array[3]
      spec.instance_variable_set :@date,                      array[4]
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
      spec.instance_variable_set :@loaded,                    false

      spec
    end

    # REQUIRED gemspec attributes ------------------------------------
    
    required_attribute :rubygems_version, Gem::RubyGemsVersion
    required_attribute :specification_version, CURRENT_SPECIFICATION_VERSION
    required_attribute :name
    required_attribute :version
    required_attribute :date, TODAY
    required_attribute :summary
    required_attribute :require_paths, ['lib']

    # OPTIONAL gemspec attributes ------------------------------------
    
    attributes :email, :homepage, :rubyforge_project, :description
    attributes :autorequire, :default_executable

    attribute :bindir,                     'bin'
    attribute :has_rdoc,                   false
    attribute :required_ruby_version,      Gem::Requirement.default
    attribute :required_rubygems_version,  Gem::Requirement.default
    attribute :platform,                   Gem::Platform::RUBY

    attribute :signing_key,            nil
    attribute :cert_chain,             []
    attribute :post_install_message,   nil

    array_attribute :authors
    array_attribute :files
    array_attribute :test_files
    array_attribute :rdoc_options
    array_attribute :extra_rdoc_files
    array_attribute :executables

    # Array of extensions to build.  See Gem::Installer#build_extensions for
    # valid values.

    array_attribute :extensions
    array_attribute :requirements
    array_attribute :dependencies

    read_only :dependencies

    # ALIASED gemspec attributes -------------------------------------
    
    attribute_alias_singular :executable,   :executables
    attribute_alias_singular :author,   :authors
    attribute_alias_singular :require_path, :require_paths
    attribute_alias_singular :test_file,    :test_files

    # DEPRECATED gemspec attributes ----------------------------------
    
    def test_suite_file
      warn 'test_suite_file deprecated, use test_files'
      test_files.first
    end

    def test_suite_file=(val)
      warn 'test_suite_file= deprecated, use test_files='
      @test_files = [] unless defined? @test_files
      @test_files << val
    end

    # true when this gemspec has been loaded from a specifications directory.
    # This attribute is not persisted.

    attr_writer :loaded

    # Path this gemspec was loaded from.  This attribute is not persisted.
    attr_accessor :loaded_from

    # Special accessor behaviours (overwriting default) --------------
    
    overwrite_accessor :version= do |version|
      @version = Version.create(version)
    end

    overwrite_accessor :platform do
      @new_platform
    end

    overwrite_accessor :platform= do |platform|
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

      @new_platform
    end

    overwrite_accessor :required_ruby_version= do |value|
      @required_ruby_version = Gem::Requirement.create(value)
    end

    overwrite_accessor :required_rubygems_version= do |value|
      @required_rubygems_version = Gem::Requirement.create(value)
    end

    overwrite_accessor :date= do |date|
      # We want to end up with a Time object with one-day resolution.
      # This is the cleanest, most-readable, faster-than-using-Date
      # way to do it.
      case date
      when String then
        @date = if /\A(\d{4})-(\d{2})-(\d{2})\Z/ =~ date then
                  Time.local($1.to_i, $2.to_i, $3.to_i)
                else
                  require 'time'
                  Time.parse date
                end
      when Time then
        @date = Time.local(date.year, date.month, date.day)
      when Date then
        @date = Time.local(date.year, date.month, date.day)
      else
        @date = TODAY
      end
    end

    overwrite_accessor :date do
      self.date = nil if @date.nil?  # HACK Sets the default value for date
      @date
    end

    overwrite_accessor :summary= do |str|
      @summary = if str then
                   str.strip.
                   gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').
                   gsub(/\n[ \t]*/, " ")
                 end
    end

    overwrite_accessor :description= do |str|
      @description = if str then
                       str.strip.
                       gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').
                       gsub(/\n[ \t]*/, " ")
                     end
    end

    overwrite_accessor :default_executable do
      begin
        if defined? @default_executable and @default_executable
          result = @default_executable
        elsif @executables and @executables.size == 1
          result = Array(@executables).first
        else
          result = nil
        end
        result
      rescue
        nil
      end
    end

    def add_bindir(executables)
      if not defined? @executables || @executables.nil?
        return nil
      end

      if defined? @bindir and @bindir then
        Array(@executables).map {|e| File.join(@bindir, e) }
      else
        @executables
      end
    rescue
      return nil
    end

    overwrite_accessor :files do
      result = []
      result.push(*@files) if defined?(@files)
      result.push(*@test_files) if defined?(@test_files)
      result.push(*(add_bindir(@executables)))
      result.push(*@extra_rdoc_files) if defined?(@extra_rdoc_files)
      result.push(*@extensions) if defined?(@extensions)
      result.uniq.compact
    end

    # Files in the Gem under one of the require_paths
    def lib_files
      @files.select do |file|
        require_paths.any? do |path|
          file.index(path) == 0
        end
      end
    end

    overwrite_accessor :test_files do
      # Handle the possibility that we have @test_suite_file but not
      # @test_files.  This will happen when an old gem is loaded via
      # YAML.
      if defined? @test_suite_file then
        @test_files = [@test_suite_file].flatten
        @test_suite_file = nil
      end
      if defined? @test_files and @test_files then
        @test_files
      else
        @test_files = []
      end
    end

    # Predicates -----------------------------------------------------
    
    def loaded?; @loaded ? true : false ; end
    def has_rdoc?; has_rdoc ? true : false ; end
    def has_unit_tests?; not test_files.empty?; end
    alias has_test_suite? has_unit_tests?               # (deprecated)
    
    # Constructors ---------------------------------------------------
    
    # Specification constructor.  Assigns the default values to the
    # attributes, adds this spec to the list of loaded specs (see
    # Specification.list), and yields itself for further initialization.
    #
    def initialize
      @new_platform = nil
      assign_defaults
      @loaded = false
      @@list << self

      yield self if block_given?

      @@gather.call(self) if @@gather
    end

    # Each attribute has a default value (possibly nil).  Here, we
    # initialize all attributes to their default value.  This is
    # done through the accessor methods, so special behaviours will
    # be honored.  Furthermore, we take a _copy_ of the default so
    # each specification instance has its own empty arrays, etc.
    def assign_defaults
      @@nil_attributes.each do |name|
        instance_variable_set name, nil
      end

      @@non_nil_attributes.each do |name, default|
        value = case default
                when Time, Numeric, Symbol, true, false, nil then default
                else default.dup
                end

        instance_variable_set name, value
      end

      # HACK
      instance_variable_set :@new_platform, Gem::Platform::RUBY
    end

    # Special loader for YAML files.  When a Specification object is
    # loaded from a YAML file, it bypasses the normal Ruby object
    # initialization routine (#initialize).  This method makes up for
    # that and deals with gems of different ages.
    #
    # 'input' can be anything that YAML.load() accepts: String or IO. 
    #
    def self.from_yaml(input)
      input = normalize_yaml_input input
      spec = YAML.load input

      if spec && spec.class == FalseClass then
        raise Gem::EndOfYAMLException
      end

      unless Gem::Specification === spec then
        raise Gem::Exception, "YAML data doesn't evaluate to gem specification"
      end

      unless (spec.instance_variables.include? '@specification_version' or
              spec.instance_variables.include? :@specification_version) and
             spec.instance_variable_get :@specification_version
        spec.instance_variable_set :@specification_version, 
                                   NONEXISTENT_SPECIFICATION_VERSION
      end

      spec
    end 

    def self.load(filename)
      gemspec = nil
      fail "NESTED Specification.load calls not allowed!" if @@gather
      @@gather = proc { |gs| gemspec = gs }
      data = File.read(filename)
      eval(data)
      gemspec
    ensure
      @@gather = nil
    end

    # Make sure the yaml specification is properly formatted with dashes.
    def self.normalize_yaml_input(input)
      result = input.respond_to?(:read) ? input.read : input
      result = "--- " + result unless result =~ /^--- /
      result
    end
    
    # Instance methods -----------------------------------------------
    
    # Sets the rubygems_version to Gem::RubyGemsVersion.
    #
    def mark_version
      @rubygems_version = RubyGemsVersion
    end

    # Ignore unknown attributes if the 
    def method_missing(sym, *a, &b) # :nodoc:
      if @specification_version > CURRENT_SPECIFICATION_VERSION and
         sym.to_s =~ /=$/ then
        warn "ignoring #{sym} loading #{full_name}" if $DEBUG
      else
        super
      end
    end

    # Adds a dependency to this Gem.  For example,
    #
    #   spec.add_dependency('jabber4r', '> 0.1', '<= 0.5')
    #
    # gem:: [String or Gem::Dependency] The Gem name/dependency.
    # requirements:: [default=">= 0"] The version requirements.
    #
    def add_dependency(gem, *requirements)
      requirements = if requirements.empty? then
                       Gem::Requirement.default
                     else
                       requirements.flatten
                     end

      unless gem.respond_to?(:name) && gem.respond_to?(:version_requirements)
        gem = Dependency.new(gem, requirements)
      end

      dependencies << gem
    end
    
    # Returns the full name (name-version) of this Gem.  Platform information
    # is included (name-version-platform) if it is specified (and not the
    # default Ruby platform).
    #
    def full_name
      if platform == Gem::Platform::RUBY or platform.nil? then
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{platform}"
      end
    end

    # Returns the full name (name-version) of this gemspec using the original
    # platform.
    #
    def original_name # :nodoc:
      if platform == Gem::Platform::RUBY or platform.nil? then
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{@original_platform}"
      end
    end

    # The full path to the gem (install path + full name).
    #
    # return:: [String] the full gem path
    #
    def full_gem_path
      path = File.join installation_path, 'gems', full_name
      return path if File.directory? path
      File.join installation_path, 'gems', original_name
    end
    
    # The default (generated) file name of the gem.
    def file_name
      full_name + ".gem"
    end
    
    # The root directory that the gem was installed into.
    #
    # return:: [String] the installation path
    #
    def installation_path
      (File.dirname(@loaded_from).split(File::SEPARATOR)[0..-2]).
        join(File::SEPARATOR)
    end
    
    # Checks if this Specification meets the requirement of the supplied
    # dependency.
    # 
    # dependency:: [Gem::Dependency] the dependency to check
    # return:: [Boolean] true if dependency is met, otherwise false
    #
    def satisfies_requirement?(dependency)
      return @name == dependency.name && 
        dependency.version_requirements.satisfied_by?(@version)
    end

    # Comparison methods ---------------------------------------------

    def sort_obj
      [@name, @version.to_ints, @new_platform == Gem::Platform::RUBY ? -1 : 1]
    end

    def <=>(other) # :nodoc:
      sort_obj <=> other.sort_obj
    end

    # Tests specs for equality (across all attributes).
    def ==(other) # :nodoc:
      self.class === other && same_attributes?(other)
    end

    alias eql? == # :nodoc:

    def same_attributes?(other)
      @@attributes.each do |name, default|
        return false unless self.send(name) == other.send(name)
      end
      true
    end
    private :same_attributes?

    def hash # :nodoc:
      @@attributes.inject(0) { |hash_code, (name, default_value)|
        n = self.send(name).hash
        hash_code + n
      }
    end

    # Export methods (YAML and Ruby code) ----------------------------

    def to_yaml(opts = {}) # :nodoc:
      mark_version

      attributes = @@attributes.map { |name,| name.to_s }.sort
      attributes = attributes - %w[name version platform]

      yaml = YAML.quick_emit object_id, opts do |out|
        out.map taguri, to_yaml_style do |map|
          map.add 'name', @name
          map.add 'version', @version
          platform = case @original_platform
                     when nil, '' then
                       'ruby'
                     when String then
                       @original_platform
                     else
                       @original_platform.to_s
                     end
          map.add 'platform', platform

          attributes.each do |name|
            map.add name, instance_variable_get("@#{name}")
          end
        end
      end
    end

    def yaml_initialize(tag, vals) # :nodoc:
      vals.each do |ivar, val|
        instance_variable_set "@#{ivar}", val
      end

      @original_platform = @platform # for backwards compatibility
      self.platform = Gem::Platform.new @platform
    end

    # Returns a Ruby code representation of this specification, such that it
    # can be eval'ed and reconstruct the same specification later.  Attributes
    # that still have their default values are omitted.
    def to_ruby
      mark_version
      result = []
      result << "Gem::Specification.new do |s|"

      result << "  s.name = #{ruby_code name}"
      result << "  s.version = #{ruby_code version}"
      unless platform.nil? or platform == Gem::Platform::RUBY then
        result << "  s.platform = #{ruby_code original_platform}"
      end
      result << ""
      result << "  s.specification_version = #{specification_version} if s.respond_to? :specification_version="
      result << ""
      result << "  s.required_rubygems_version = #{ruby_code required_rubygems_version} if s.respond_to? :required_rubygems_version="

      handled = [
        :dependencies,
        :name,
        :platform,
        :required_rubygems_version,
        :specification_version,
        :version,
      ]

      attributes = @@attributes.sort_by { |attr_name,| attr_name.to_s }

      attributes.each do |attr_name, default|
        next if handled.include? attr_name
        current_value = self.send(attr_name)
        if current_value != default or
           self.class.required_attribute? attr_name then
          result << "  s.#{attr_name} = #{ruby_code current_value}"
        end
      end

      result << "" unless dependencies.empty?

      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "  s.add_dependency(%q<#{dep.name}>, #{version_reqs_param})"
      end

      result << "end"
      result << ""

      result.join "\n"
    end

    # Validation and normalization methods ---------------------------

    # Checks that the specification contains all required fields, and
    # does a very basic sanity check.
    #
    # Raises InvalidSpecificationException if the spec does not pass
    # the checks..
    def validate
      extend Gem::UserInteraction

      normalize

      if rubygems_version != RubyGemsVersion then
        raise Gem::InvalidSpecificationException,
              "expected RubyGems version #{RubyGemsVersion}, was #{rubygems_version}"
      end

      @@required_attributes.each do |symbol|
        unless self.send symbol then
          raise Gem::InvalidSpecificationException,
                "missing value for attribute #{symbol}"
        end
      end 

      if require_paths.empty? then
        raise Gem::InvalidSpecificationException,
              "specification must have at least one require_path"
      end

      case platform
      when Gem::Platform, Platform::RUBY then # ok
      else
        raise Gem::InvalidSpecificationException,
              "invalid platform #{platform.inspect}, see Gem::Platform"
      end

      unless Array === authors and
             authors.all? { |author| String === author } then
        raise Gem::InvalidSpecificationException,
              'authors must be Array of Strings'
      end

      # Warnings

      %w[author email homepage rubyforge_project summary].each do |attribute|
        value = self.send attribute
        alert_warning "no #{attribute} specified" if value.nil? or value.empty?
      end

      alert_warning "RDoc will not be generated (has_rdoc == false)" unless
        has_rdoc

      alert_warning "deprecated autorequire specified" if autorequire

      executables.each do |executable|
        executable_path = File.join bindir, executable
        shebang = File.read(executable_path, 2) == '#!'

        alert_warning "#{executable_path} is missing #! line" unless shebang
      end

      true
    end

    # Normalize the list of files so that:
    # * All file lists have redundancies removed.
    # * Files referenced in the extra_rdoc_files are included in the
    #   package file list. 
    #
    # Also, the summary and description are converted to a normal
    # format. 
    def normalize
      if defined? @extra_rdoc_files and @extra_rdoc_files then
        @extra_rdoc_files.uniq!
        @files ||= []
        @files.concat(@extra_rdoc_files)
      end
      @files.uniq! if @files
    end

    # Dependency methods ---------------------------------------------
    
    # Return a list of all gems that have a dependency on this
    # gemspec.  The list is structured with entries that conform to:
    #
    #   [depending_gem, dependency, [list_of_gems_that_satisfy_dependency]]
    #
    # return:: [Array] [[dependent_gem, dependency, [list_of_satisfiers]]]
    #
    def dependent_gems
      out = []
      Gem.source_index.each do |name,gem|
        gem.dependencies.each do |dep|
          if self.satisfies_requirement?(dep) then
            sats = []
            find_all_satisfiers(dep) do |sat|
              sats << sat
            end
            out << [gem, dep, sats]
          end
        end
      end
      out
    end

    def to_s
      "#<Gem::Specification name=#{@name} version=#{@version}>"
    end

    private

    def find_all_satisfiers(dep)
      Gem.source_index.each do |name,gem|
        if(gem.satisfies_requirement?(dep)) then
          yield gem
        end
      end
    end

    # Return a string containing a Ruby code representation of the
    # given object.
    def ruby_code(obj)
      case obj
      when String            then '%q{' + obj + '}'
      when Array             then obj.inspect
      when Gem::Version      then obj.to_s.inspect
      when Date              then '%q{' + obj.strftime('%Y-%m-%d') + '}'
      when Time              then '%q{' + obj.strftime('%Y-%m-%d') + '}'
      when Numeric           then obj.inspect
      when true, false, nil  then obj.inspect
      when Gem::Platform     then "Gem::Platform.new(#{obj.to_a.inspect})"
      when Gem::Requirement  then "Gem::Requirement.new(#{obj.to_s.inspect})"
      else raise Exception, "ruby_code case not handled: #{obj.class}"
      end
    end

  end

end

