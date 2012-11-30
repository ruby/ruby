##
# A Requirement is a set of one or more version restrictions. It supports a
# few (<tt>=, !=, >, <, >=, <=, ~></tt>) different restriction operators.

# REFACTOR: The fact that a requirement is singular or plural is kind of
# awkward. Is Requirement the right name for this? Or should it be one
# [op, number] pair, and we call the list of requirements something else?
# Since a Requirement is held by a Dependency, maybe this should be made
# singular and the list aspect should be pulled up into Dependency?

require "rubygems/version"
require "rubygems/deprecate"

# If we're being loaded after yaml was already required, then
# load our yaml + workarounds now.
Gem.load_yaml if defined? ::YAML

class Gem::Requirement
  OPS = { #:nodoc:
    "="  =>  lambda { |v, r| v == r },
    "!=" =>  lambda { |v, r| v != r },
    ">"  =>  lambda { |v, r| v >  r },
    "<"  =>  lambda { |v, r| v <  r },
    ">=" =>  lambda { |v, r| v >= r },
    "<=" =>  lambda { |v, r| v <= r },
    "~>" =>  lambda { |v, r| v >= r && v.release < r.bump }
  }

  quoted  = OPS.keys.map { |k| Regexp.quote k }.join "|"
  PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{Gem::Version::VERSION_PATTERN})\\s*"
  PATTERN = /\A#{PATTERN_RAW}\z/

  DefaultRequirement = [">=", Gem::Version.new(0)]

  class BadRequirementError < ArgumentError; end

  ##
  # Factory method to create a Gem::Requirement object.  Input may be
  # a Version, a String, or nil.  Intended to simplify client code.
  #
  # If the input is "weird", the default version requirement is
  # returned.

  # REFACTOR: There's no reason that this can't be unified with .new.
  # .new is the standard Ruby factory method.

  def self.create input
    case input
    when Gem::Requirement then
      input
    when Gem::Version, Array then
      new input
    else
      if input.respond_to? :to_str then
        new [input.to_str]
      else
        default
      end
    end
  end

  ##
  # A default "version requirement" can surely _only_ be '>= 0'.

  def self.default
    new '>= 0'
  end

  ##
  # Parse +obj+, returning an <tt>[op, version]</tt> pair. +obj+ can
  # be a String or a Gem::Version.
  #
  # If +obj+ is a String, it can be either a full requirement
  # specification, like <tt>">= 1.2"</tt>, or a simple version number,
  # like <tt>"1.2"</tt>.
  #
  #     parse("> 1.0")                 # => [">", "1.0"]
  #     parse("1.0")                   # => ["=", "1.0"]
  #     parse(Gem::Version.new("1.0")) # => ["=,  "1.0"]

  # REFACTOR: Little two element arrays like this have no real semantic
  # value. I'd love to see something like this:
  # Constraint = Struct.new(:operator, :version); (or similar)
  # and have a Requirement be a list of Constraints.

  def self.parse obj
    return ["=", obj] if Gem::Version === obj

    unless PATTERN =~ obj.to_s
      raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
    end

    if $1 == ">=" && $2 == "0"
      DefaultRequirement
    else
      [$1 || "=", Gem::Version.new($2)]
    end
  end

  ##
  # An array of requirement pairs. The first element of the pair is
  # the op, and the second is the Gem::Version.

  attr_reader :requirements #:nodoc:

  ##
  # Constructs a requirement from +requirements+. Requirements can be
  # Strings, Gem::Versions, or Arrays of those. +nil+ and duplicate
  # requirements are ignored. An empty set of +requirements+ is the
  # same as <tt>">= 0"</tt>.

  def initialize *requirements
    requirements = requirements.flatten
    requirements.compact!
    requirements.uniq!

    if requirements.empty?
      @requirements = [DefaultRequirement]
    else
      @requirements = requirements.map! { |r| self.class.parse r }
    end
  end

  ##
  # true if this gem has no requirements.

  # FIX: maybe this should be using #default ?
  def none?
    if @requirements.size == 1
      @requirements[0] == DefaultRequirement
    else
      false
    end
  end

  def as_list # :nodoc:
    requirements.map { |op, version| "#{op} #{version}" }.sort
  end

  def hash # :nodoc:
    requirements.hash
  end

  def marshal_dump # :nodoc:
    fix_syck_default_key_in_requirements

    [@requirements]
  end

  def marshal_load array # :nodoc:
    @requirements = array[0]

    fix_syck_default_key_in_requirements
  end

  def yaml_initialize(tag, vals) # :nodoc:
    vals.each do |ivar, val|
      instance_variable_set "@#{ivar}", val
    end

    Gem.load_yaml
    fix_syck_default_key_in_requirements
  end

  def init_with coder # :nodoc:
    yaml_initialize coder.tag, coder.map
  end

  def to_yaml_properties
    ["@requirements"]
  end

  def encode_with(coder)
    coder.add 'requirements', @requirements
  end

  ##
  # A requirement is a prerelease if any of the versions inside of it
  # are prereleases

  def prerelease?
    requirements.any? { |r| r.last.prerelease? }
  end

  def pretty_print q # :nodoc:
    q.group 1, 'Gem::Requirement.new(', ')' do
      q.pp as_list
    end
  end

  ##
  # True if +version+ satisfies this Requirement.

  def satisfied_by? version
    raise ArgumentError, "Need a Gem::Version: #{version.inspect}" unless
      Gem::Version === version
    # #28965: syck has a bug with unquoted '=' YAML.loading as YAML::DefaultKey
    requirements.all? { |op, rv| (OPS[op] || OPS["="]).call version, rv }
  end

  alias :=== :satisfied_by?
  alias :=~ :satisfied_by?

  ##
  # True if the requirement will not always match the latest version.

  def specific?
    return true if @requirements.length > 1 # GIGO, > 1, > 2 is silly

    not %w[> >=].include? @requirements.first.first # grab the operator
  end

  def to_s # :nodoc:
    as_list.join ", "
  end

  # DOC: this should probably be :nodoc'd
  def == other
    Gem::Requirement === other and to_s == other.to_s
  end

  private

  # DOC: this should probably be :nodoc'd
  def fix_syck_default_key_in_requirements
    Gem.load_yaml

    # Fixup the Syck DefaultKey bug
    @requirements.each do |r|
      if r[0].kind_of? Gem::SyckDefaultKey
        r[0] = "="
      end
    end
  end
end

# This is needed for compatibility with older yaml
# gemspecs.

class Gem::Version
  Requirement = Gem::Requirement
end
