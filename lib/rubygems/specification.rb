#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/version'
require 'rubygems/requirement'
require 'rubygems/platform'

# :stopdoc:
class Date; end # for ruby_code if date.rb wasn't required
# :startdoc:

##
# The Specification class contains the metadata for a Gem.  Typically
# defined in a .gemspec file or a Rakefile, and looks like this:
#
#   spec = Gem::Specification.new do |s|
#     s.name = 'example'
#     s.version = '1.0'
#     s.summary = 'Example gem specification'
#     ...
#   end
#
# For a great way to package gems, use Hoe.

class Gem::Specification

  ##
  # Allows deinstallation of gems with legacy platforms.

  attr_accessor :original_platform # :nodoc:

  ##
  # The the version number of a specification that does not specify one
  # (i.e. RubyGems 0.7 or earlier).

  NONEXISTENT_SPECIFICATION_VERSION = -1

  ##
  # The specification version applied to any new Specification instances
  # created.  This should be bumped whenever something in the spec format
  # changes.
  #--
  # When updating this number, be sure to also update #to_ruby.
  #
  # NOTE RubyGems < 1.2 cannot load specification versions > 2.

  CURRENT_SPECIFICATION_VERSION = 3

  ##
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
    3 => [
       'Added Fixnum validation to the specification_version'
    ]
  }

  # :stopdoc:
  MARSHAL_FIELDS = { -1 => 16, 1 => 16, 2 => 16, 3 => 17 }

  now = Time.at(Time.now.to_i)
  TODAY = now - ((now.to_i + now.gmt_offset) % 86400)
  # :startdoc:

  ##
  # Optional block used to gather newly defined instances.

  @@gather = nil

  ##
  # List of attribute names: [:name, :version, ...]

  @@required_attributes = []

  ##
  # List of _all_ attributes and default values:
  #
  #   [[:name, nil],
  #    [:bindir, 'bin'],
  #    ...]

  @@attributes = []

  @@nil_attributes = []
  @@non_nil_attributes = [:@original_platform]

  ##
  # List of array attributes

  @@array_attributes = []

  ##
  # Map of attribute names to default values.

  @@default_value = {}

  ##
  # Names of all specification attributes

  def self.attribute_names
    @@attributes.map { |name, default| name }
  end

  ##
  # Default values for specification attributes

  def self.attribute_defaults
    @@attributes.dup
  end

  ##
  # The default value for specification attribute +name+

  def self.default_value(name)
    @@default_value[name]
  end

  ##
  # Required specification attributes

  def self.required_attributes
    @@required_attributes.dup
  end

  ##
  # Is +name+ a required attribute?

  def self.required_attribute?(name)
    @@required_attributes.include? name.to_sym
  end

  ##
  # Specification attributes that are arrays (appendable and so-forth)

  def self.array_attributes
    @@array_attributes.dup
  end

  ##
  # Specifies the +name+ and +default+ for a specification attribute, and
  # creates a reader and writer method like Module#attr_accessor.
  #
  # The reader method returns the default if the value hasn't been set.

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

  ##
  # Same as :attribute, but ensures that values assigned to the attribute
  # are array values by applying :to_a to the value.

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

  ##
  # Same as attribute above, but also records this attribute as mandatory.

  def self.required_attribute(*args)
    @@required_attributes << args.first
    attribute(*args)
  end

  ##
  # Sometimes we don't want the world to use a setter method for a
  # particular attribute.
  #
  # +read_only+ makes it private so we can still use it internally.

  def self.read_only(*names)
    names.each do |name|
      private "#{name}="
    end
  end

  # Shortcut for creating several attributes at once (each with a default
  # value of +nil+).

  def self.attributes(*args)
    args.each do |arg|
      attribute(arg, nil)
    end
  end

  ##
  # Some attributes require special behaviour when they are accessed.  This
  # allows for that.

  def self.overwrite_accessor(name, &block)
    remove_method name
    define_method(name, &block)
  end

  ##
  # Defines a _singular_ version of an existing _plural_ attribute (i.e. one
  # whose value is expected to be an array).  This means just creating a
  # helper method that takes a single value and appends it to the array.
  # These are created for convenience, so that in a spec, one can write
  #
  #   s.require_path = 'mylib'
  #
  # instead of:
  #
  #   s.require_paths = ['mylib']
  #
  # That above convenience is available courtesy of:
  #
  #   attribute_alias_singular :require_path, :require_paths

  def self.attribute_alias_singular(singular, plural)
    define_method("#{singular}=") { |val|
      send("#{plural}=", [val])
    }
    define_method("#{singular}") {
      val = send("#{plural}")
      val.nil? ? nil : val.first
    }
  end

  ##
  # Dump only crucial instance variables.
  #--
  # MAINTAIN ORDER!

  def _dump(limit)
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
      @licenses
    ]
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
    spec.instance_variable_set :@license,                   array[17]
    spec.instance_variable_set :@loaded,                    false

    spec
  end

  ##
  # List of depedencies that will automatically be activated at runtime.

  def runtime_dependencies
    dependencies.select { |d| d.type == :runtime || d.type == nil }
  end

  ##
  # List of dependencies that are used for development

  def development_dependencies
    dependencies.select { |d| d.type == :development }
  end

  def test_suite_file # :nodoc:
    warn 'test_suite_file deprecated, use test_files'
    test_files.first
  end

  def test_suite_file=(val) # :nodoc:
    warn 'test_suite_file= deprecated, use test_files='
    @test_files = [] unless defined? @test_files
    @test_files << val
  end

  ##
  # true when this gemspec has been loaded from a specifications directory.
  # This attribute is not persisted.

  attr_accessor :loaded

  ##
  # Path this gemspec was loaded from.  This attribute is not persisted.

  attr_accessor :loaded_from

  ##
  # Returns an array with bindir attached to each executable in the
  # executables list

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
  # Files in the Gem under one of the require_paths

  def lib_files
    @files.select do |file|
      require_paths.any? do |path|
        file.index(path) == 0
      end
    end
  end

  ##
  # True if this gem was loaded from disk

  alias :loaded? :loaded

  ##
  # True if this gem has files in test_files

  def has_unit_tests?
    not test_files.empty?
  end

  # :stopdoc:
  alias has_test_suite? has_unit_tests?
  # :startdoc:

  ##
  # Specification constructor.  Assigns the default values to the
  # attributes and yields itself for further
  # initialization. Optionally takes +name+ and +version+.

  def initialize name = nil, version = nil
    @new_platform = nil
    assign_defaults
    @loaded = false
    @loaded_from = nil

    self.name = name if name
    self.version = version if version

    yield self if block_given?

    @@gather.call(self) if @@gather
  end

  ##
  # Duplicates array_attributes from +other_spec+ so state isn't shared.

  def initialize_copy(other_spec)
    other_ivars = other_spec.instance_variables
    other_ivars = other_ivars.map { |ivar| ivar.intern } if # for 1.9
      other_ivars.any? { |ivar| String === ivar }

    self.class.array_attributes.each do |name|
      name = :"@#{name}"
      next unless other_ivars.include? name
      instance_variable_set name, other_spec.instance_variable_get(name).dup
    end
  end

  ##
  # Each attribute has a default value (possibly nil).  Here, we initialize
  # all attributes to their default value.  This is done through the
  # accessor methods, so special behaviours will be honored.  Furthermore,
  # we take a _copy_ of the default so each specification instance has its
  # own empty arrays, etc.

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

  ##
  # Special loader for YAML files.  When a Specification object is loaded
  # from a YAML file, it bypasses the normal Ruby object initialization
  # routine (#initialize).  This method makes up for that and deals with
  # gems of different ages.
  #
  # 'input' can be anything that YAML.load() accepts: String or IO.

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

  ##
  # Loads ruby format gemspec from +filename+

  def self.load(filename)
    gemspec = nil
    raise "NESTED Specification.load calls not allowed!" if @@gather
    @@gather = proc { |gs| gemspec = gs }
    data = File.read(filename)
    eval(data)
    gemspec
  ensure
    @@gather = nil
  end

  ##
  # Make sure the YAML specification is properly formatted with dashes

  def self.normalize_yaml_input(input)
    result = input.respond_to?(:read) ? input.read : input
    result = "--- " + result unless result =~ /^--- /
    result
  end

  ##
  # Sets the rubygems_version to the current RubyGems version

  def mark_version
    @rubygems_version = Gem::RubyGemsVersion
  end

  ##
  # Ignore unknown attributes while loading

  def method_missing(sym, *a, &b) # :nodoc:
    if @specification_version > CURRENT_SPECIFICATION_VERSION and
      sym.to_s =~ /=$/ then
      warn "ignoring #{sym} loading #{full_name}" if $DEBUG
    else
      super
    end
  end

  ##
  # Adds a development dependency named +gem+ with +requirements+ to this
  # Gem.  For example:
  #
  #   spec.add_development_dependency 'jabber4r', '> 0.1', '<= 0.5'
  #
  # Development dependencies aren't installed by default and aren't
  # activated when a gem is required.

  def add_development_dependency(gem, *requirements)
    add_dependency_with_type(gem, :development, *requirements)
  end

  ##
  # Adds a runtime dependency named +gem+ with +requirements+ to this Gem.
  # For example:
  #
  #   spec.add_runtime_dependency 'jabber4r', '> 0.1', '<= 0.5'

  def add_runtime_dependency(gem, *requirements)
    add_dependency_with_type(gem, :runtime, *requirements)
  end

  ##
  # Adds a runtime dependency

  alias add_dependency add_runtime_dependency

  ##
  # Returns the full name (name-version) of this Gem.  Platform information
  # is included (name-version-platform) if it is specified and not the
  # default Ruby platform.

  def full_name
    if platform == Gem::Platform::RUBY or platform.nil? then
      "#{@name}-#{@version}"
    else
      "#{@name}-#{@version}-#{platform}"
    end
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
  # The full path to the gem (install path + full name).

  def full_gem_path
    path = File.join installation_path, 'gems', full_name
    return path if File.directory? path
    File.join installation_path, 'gems', original_name
  end

  ##
  # The default (generated) file name of the gem.  See also #spec_name.
  #
  #   spec.file_name # => "example-1.0.gem"

  def file_name
    full_name + '.gem'
  end

  ##
  # The directory that this gem was installed into.

  def installation_path
    unless @loaded_from then
      raise Gem::Exception, "spec #{full_name} is not from an installed gem"
    end

    File.expand_path File.dirname(File.dirname(@loaded_from))
  end

  ##
  # Checks if this specification meets the requirement of +dependency+.

  def satisfies_requirement?(dependency)
    return @name == dependency.name &&
      dependency.requirement.satisfied_by?(@version)
  end

  ##
  # Returns an object you can use to sort specifications in #sort_by.

  def sort_obj
    [@name, @version, @new_platform == Gem::Platform::RUBY ? -1 : 1]
  end

  ##
  # The default name of the gemspec.  See also #file_name
  #
  #   spec.spec_name # => "example-1.0.gemspec"

  def spec_name
    full_name + '.gemspec'
  end

  def <=>(other) # :nodoc:
    sort_obj <=> other.sort_obj
  end

  ##
  # Tests specs for equality (across all attributes).

  def ==(other) # :nodoc:
    self.class === other && same_attributes?(other)
  end

  alias eql? == # :nodoc:

  ##
  # True if this gem has the same attributes as +other+.

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

  ##
  # Returns a Ruby code representation of this specification, such that it
  # can be eval'ed and reconstruct the same specification later.  Attributes
  # that still have their default values are omitted.

  def to_ruby
    mark_version
    result = []
    result << "# -*- encoding: utf-8 -*-"
    result << nil
    result << "Gem::Specification.new do |s|"

    result << "  s.name = #{ruby_code name}"
    result << "  s.version = #{ruby_code version}"
    unless platform.nil? or platform == Gem::Platform::RUBY then
      result << "  s.platform = #{ruby_code original_platform}"
    end
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

    result << nil
    result << "  if s.respond_to? :specification_version then"
    result << "    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION"
    result << "    s.specification_version = #{specification_version}"
    result << nil

    result << "    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then"

    unless dependencies.empty? then
      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        dep.instance_variable_set :@type, :runtime if dep.type.nil? # HACK
        result << "      s.add_#{dep.type}_dependency(%q<#{dep.name}>, #{version_reqs_param})"
      end
    end

    result << "    else"

    unless dependencies.empty? then
      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "      s.add_dependency(%q<#{dep.name}>, #{version_reqs_param})"
      end
    end

    result << '    end'

    result << "  else"
      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "    s.add_dependency(%q<#{dep.name}>, #{version_reqs_param})"
      end
    result << "  end"

    result << "end"
    result << nil

    result.join "\n"
  end

  ##
  # Checks that the specification contains all required fields, and does a
  # very basic sanity check.
  #
  # Raises InvalidSpecificationException if the spec does not pass the
  # checks..

  def validate
    extend Gem::UserInteraction
    normalize

    if rubygems_version != Gem::RubyGemsVersion then
      raise Gem::InvalidSpecificationException,
            "expected RubyGems version #{Gem::RubyGemsVersion}, was #{rubygems_version}"
    end

    @@required_attributes.each do |symbol|
      unless self.send symbol then
        raise Gem::InvalidSpecificationException,
              "missing value for attribute #{symbol}"
      end
    end

    unless String === name then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: \"#{name.inspect}\""
    end

    if require_paths.empty? then
      raise Gem::InvalidSpecificationException,
            'specification must have at least one require_path'
    end

    @files.delete_if            do |file| File.directory? file end
    @test_files.delete_if       do |file| File.directory? file end
    @executables.delete_if      do |file|
      File.directory? File.join(bindir, file)
    end
    @extra_rdoc_files.delete_if do |file| File.directory? file end
    @extensions.delete_if       do |file| File.directory? file end

    non_files = files.select do |file|
      !File.file? file
    end

    unless non_files.empty? then
      non_files = non_files.map { |file| file.inspect }
      raise Gem::InvalidSpecificationException,
            "[#{non_files.join ", "}] are not files"
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

    unless Array === authors and
           authors.all? { |author| String === author } then
      raise Gem::InvalidSpecificationException,
            'authors must be Array of Strings'
    end

    licenses.each { |license|
      if license.length > 64
        raise Gem::InvalidSpecificationException,
          "each license must be 64 characters or less"
      end
    }

    # reject FIXME and TODO

    unless authors.grep(/FIXME|TODO/).empty? then
      raise Gem::InvalidSpecificationException,
            '"FIXME" or "TODO" is not an author'
    end

    unless Array(email).grep(/FIXME|TODO/).empty? then
      raise Gem::InvalidSpecificationException,
            '"FIXME" or "TODO" is not an email address'
    end

    if description =~ /FIXME|TODO/ then
      raise Gem::InvalidSpecificationException,
            '"FIXME" or "TODO" is not a description'
    end

    if summary =~ /FIXME|TODO/ then
      raise Gem::InvalidSpecificationException,
            '"FIXME" or "TODO" is not a summary'
    end

    if homepage and not homepage.empty? and
       homepage !~ /\A[a-z][a-z\d+.-]*:/i then
      raise Gem::InvalidSpecificationException,
            "\"#{homepage}\" is not a URI"
    end

    # Warnings

    %w[author description email homepage rubyforge_project summary].each do |attribute|
      value = self.send attribute
      alert_warning "no #{attribute} specified" if value.nil? or value.empty?
    end

    if summary and not summary.empty? and description == summary then
      alert_warning 'description and summary are identical'
    end

    alert_warning "deprecated autorequire specified" if autorequire

    executables.each do |executable|
      executable_path = File.join bindir, executable
      shebang = File.read(executable_path, 2) == '#!'

      alert_warning "#{executable_path} is missing #! line" unless shebang
    end

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
    @files.uniq! if @files
  end

  ##
  # Return a list of all gems that have a dependency on this gemspec.  The
  # list is structured with entries that conform to:
  #
  #   [depending_gem, dependency, [list_of_gems_that_satisfy_dependency]]

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

  def to_s # :nodoc:
    "#<Gem::Specification name=#{@name} version=#{@version}>"
  end

  def pretty_print(q) # :nodoc:
    q.group 2, 'Gem::Specification.new do |s|', 'end' do
      q.breakable

      attributes = @@attributes.sort_by { |attr_name,| attr_name.to_s }

      attributes.each do |attr_name, default|
        current_value = self.send attr_name
        if current_value != default or
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
      dependency.respond_to?(:version_requirements)

      dependency = Gem::Dependency.new(dependency, requirements, type)
    end

    dependencies << dependency
  end

  private :add_dependency_with_type

  ##
  # Finds all gems that satisfy +dep+

  def find_all_satisfiers(dep)
    Gem.source_index.each do |_, gem|
      yield gem if gem.satisfies_requirement? dep
    end
  end

  private :find_all_satisfiers

  ##
  # Return a string containing a Ruby code representation of the given
  # object.

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
    else raise Gem::Exception, "ruby_code case not handled: #{obj.class}"
    end
  end

  private :ruby_code

  # :section: Required gemspec attributes

  ##
  # :attr_accessor: rubygems_version
  #
  # The version of RubyGems used to create this gem.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  required_attribute :rubygems_version, Gem::RubyGemsVersion

  ##
  # :attr_accessor: specification_version
  #
  # The Gem::Specification version of this gemspec.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  required_attribute :specification_version, CURRENT_SPECIFICATION_VERSION

  ##
  # :attr_accessor: name
  #
  # This gem's name

  required_attribute :name

  ##
  # :attr_accessor: version
  #
  # This gem's version

  required_attribute :version

  ##
  # :attr_accessor: date
  #
  # The date this gem was created
  #
  # Do not set this, it is set automatically when the gem is packaged.

  required_attribute :date, TODAY

  ##
  # :attr_accessor: summary
  #
  # A short summary of this gem's description.  Displayed in `gem list -d`.
  #
  # The description should be more detailed than the summary.  For example,
  # you might wish to copy the entire README into the description.
  #
  # As of RubyGems 1.3.2 newlines are no longer stripped.

  required_attribute :summary

  ##
  # :attr_accessor: require_paths
  #
  # Paths in the gem to add to $LOAD_PATH when this gem is activated.
  #
  # The default 'lib' is typically sufficient.

  required_attribute :require_paths, ['lib']

  # :section: Optional gemspec attributes

  ##
  # :attr_accessor: email
  #
  # A contact email for this gem
  #
  # If you are providing multiple authors and multiple emails they should be
  # in the same order such that:
  #
  #   Hash[*spec.authors.zip(spec.emails).flatten]
  #
  # Gives a hash of author name to email address.

  attribute :email

  ##
  # :attr_accessor: homepage
  #
  # The URL of this gem's home page

  attribute :homepage

  ##
  # :attr_accessor: rubyforge_project
  #
  # The rubyforge project this gem lives under.  i.e. RubyGems'
  # rubyforge_project is "rubygems".

  attribute :rubyforge_project

  ##
  # :attr_accessor: description
  #
  # A long description of this gem

  attribute :description

  ##
  # :attr_accessor: autorequire
  #
  # Autorequire was used by old RubyGems to automatically require a file.
  # It no longer is supported.

  attribute :autorequire

  ##
  # :attr_accessor: default_executable
  #
  # The default executable for this gem.
  #
  # This is not used.

  attribute :default_executable

  ##
  # :attr_accessor: bindir
  #
  # The path in the gem for executable scripts

  attribute :bindir, 'bin'

  ##
  # :attr_accessor: has_rdoc
  #
  # Deprecated and ignored, defaults to true.
  #
  # Formerly used to indicate this gem was RDoc-capable.

  attribute :has_rdoc, true

  ##
  # True if this gem supports RDoc

  alias :has_rdoc? :has_rdoc

  ##
  # :attr_accessor: required_ruby_version
  #
  # The version of ruby required by this gem

  attribute :required_ruby_version, Gem::Requirement.default

  ##
  # :attr_accessor: required_rubygems_version
  #
  # The RubyGems version required by this gem

  attribute :required_rubygems_version, Gem::Requirement.default

  ##
  # :attr_accessor: platform
  #
  # The platform this gem runs on.  See Gem::Platform for details.
  #
  # Setting this to any value other than Gem::Platform::RUBY or
  # Gem::Platform::CURRENT is probably wrong.

  attribute :platform, Gem::Platform::RUBY

  ##
  # :attr_accessor: signing_key
  #
  # The key used to sign this gem.  See Gem::Security for details.

  attribute :signing_key, nil

  ##
  # :attr_accessor: cert_chain
  #
  # The certificate chain used to sign this gem.  See Gem::Security for
  # details.

  attribute :cert_chain, []

  ##
  # :attr_accessor: post_install_message
  #
  # A message that gets displayed after the gem is installed

  attribute :post_install_message, nil

  ##
  # :attr_accessor: authors
  #
  # The list of author names who wrote this gem.
  #
  # If you are providing multiple authors and multiple emails they should be
  # in the same order such that:
  #
  #   Hash[*spec.authors.zip(spec.emails).flatten]
  #
  # Gives a hash of author name to email address.

  array_attribute :authors

  ##
  # :attr_accessor: licenses
  #
  # The license(s) for the library.  Each license must be a short name, no
  # more than 64 characters.

  array_attribute :licenses

  ##
  # :attr_accessor: files
  #
  # Files included in this gem.  You cannot append to this accessor, you must
  # assign to it.
  #
  # Only add files you can require to this list, not directories, etc.
  #
  # Directories are automatically stripped from this list when building a gem,
  # other non-files cause an error.

  array_attribute :files

  ##
  # :attr_accessor: test_files
  #
  # Test files included in this gem.  You cannot append to this accessor, you
  # must assign to it.

  array_attribute :test_files

  ##
  # :attr_accessor: rdoc_options
  #
  # An ARGV style array of options to RDoc

  array_attribute :rdoc_options

  ##
  # :attr_accessor: extra_rdoc_files
  #
  # Extra files to add to RDoc such as README or doc/examples.txt

  array_attribute :extra_rdoc_files

  ##
  # :attr_accessor: executables
  #
  # Executables included in the gem.

  array_attribute :executables

  ##
  # :attr_accessor: extensions
  #
  # Extensions to build when installing the gem.  See
  # Gem::Installer#build_extensions for valid values.

  array_attribute :extensions

  ##
  # :attr_accessor: requirements
  #
  # An array or things required by this gem.  Not used by anything
  # presently.

  array_attribute :requirements

  ##
  # :attr_reader: dependencies
  #
  # A list of Gem::Dependency objects this gem depends on.
  #
  # Use #add_dependency or #add_development_dependency to add dependencies to
  # a gem.

  array_attribute :dependencies

  read_only :dependencies

  # :section: Aliased gemspec attributes

  ##
  # Singular accessor for #executables

  attribute_alias_singular :executable, :executables

  ##
  # Singular accessor for #authors

  attribute_alias_singular :author, :authors

  ##
  # Singular accessor for #licenses

  attribute_alias_singular :license, :licenses

  ##
  # Singular accessor for #require_paths

  attribute_alias_singular :require_path, :require_paths

  ##
  # Singular accessor for #test_files

  attribute_alias_singular :test_file, :test_files

  ##
  # has_rdoc is now ignored

  overwrite_accessor :has_rdoc do
    true
  end

  ##
  # has_rdoc is now ignored

  overwrite_accessor :has_rdoc= do |value|
    @has_rdoc = true
  end

  overwrite_accessor :version= do |version|
    @version = Gem::Version.create(version)
    self.required_rubygems_version = '> 1.3.1' if @version.prerelease?
    return @version
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
    @description = str.to_s
  end

  overwrite_accessor :default_executable do
    begin
      if defined?(@default_executable) and @default_executable
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

  overwrite_accessor :test_files do
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

  overwrite_accessor :files do
    result = []
    result.push(*@files) if defined?(@files)
    result.push(*@test_files) if defined?(@test_files)
    result.push(*(add_bindir(@executables)))
    result.push(*@extra_rdoc_files) if defined?(@extra_rdoc_files)
    result.push(*@extensions) if defined?(@extensions)
    result.uniq.compact
  end

end

