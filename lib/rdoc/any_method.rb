require 'rdoc/code_object'
require 'rdoc/tokenstream'

##
# AnyMethod is the base class for objects representing methods

class RDoc::AnyMethod < RDoc::CodeObject

  MARSHAL_VERSION = 1 # :nodoc:

  include Comparable

  ##
  # Method name

  attr_writer :name

  ##
  # public, protected, private

  attr_accessor :visibility

  ##
  # Parameters yielded by the called block

  attr_accessor :block_params

  ##
  # Don't rename \#initialize to \::new

  attr_accessor :dont_rename_initialize

  ##
  # Is this a singleton method?

  attr_accessor :singleton

  ##
  # Source file token stream

  attr_reader :text

  ##
  # Array of other names for this method

  attr_reader :aliases

  ##
  # The method we're aliasing

  attr_accessor :is_alias_for

  ##
  # Parameters for this method

  attr_accessor :params

  ##
  # Different ways to call this method

  attr_accessor :call_seq

  include RDoc::TokenStream

  def initialize(text, name)
    super()

    @text = text
    @name = name

    @aref                   = nil
    @aliases                = []
    @block_params           = nil
    @call_seq               = nil
    @dont_rename_initialize = false
    @is_alias_for           = nil
    @params                 = nil
    @parent_name            = nil
    @singleton              = nil
    @token_stream           = nil
    @visibility             = :public
  end

  ##
  # Order by #singleton then #name

  def <=>(other)
    [@singleton ? 0 : 1, @name] <=> [other.singleton ? 0 : 1, other.name]
  end

  ##
  # Adds +method+ as an alias for this method

  def add_alias(method)
    @aliases << method
  end

  ##
  # HTML fragment reference for this method

  def aref
    type = singleton ? 'c' : 'i'

    "method-#{type}-#{CGI.escape name}"
  end

  ##
  # The call_seq or the param_seq with method name, if there is no call_seq.
  #
  # Use this for displaying a method's argument lists.

  def arglists
    if @call_seq then
      @call_seq
    elsif @params then
      "#{name}#{param_seq}"
    end
  end

  ##
  # HTML id-friendly method name

  def html_name
    @name.gsub(/[^a-z]+/, '-')
  end

  def inspect # :nodoc:
    alias_for = @is_alias_for ? " (alias for #{@is_alias_for.name})" : nil
    "#<%s:0x%x %s (%s)%s>" % [
      self.class, object_id,
      full_name,
      visibility,
      alias_for,
    ]
  end

  ##
  # Full method name including namespace

  def full_name
    @full_name ||= "#{@parent ? @parent.full_name : '(unknown)'}#{pretty_name}"
  end

  ##
  # Dumps this AnyMethod for use by ri.  See also #marshal_load

  def marshal_dump
    aliases = @aliases.map do |a|
      [a.full_name, parse(a.comment)]
    end

    [ MARSHAL_VERSION,
      @name,
      full_name,
      @singleton,
      @visibility,
      parse(@comment),
      @call_seq,
      @block_params,
      aliases,
      @params,
    ]
  end

  ##
  # Loads this AnyMethod from +array+.  For a loaded AnyMethod the following
  # methods will return cached values:
  #
  # * #full_name
  # * #parent_name

  def marshal_load(array)
    @dont_rename_initialize = nil
    @is_alias_for           = nil
    @token_stream           = nil

    @name         = array[1]
    @full_name    = array[2]
    @singleton    = array[3]
    @visibility   = array[4]
    @comment      = array[5]
    @call_seq     = array[6]
    @block_params = array[7]
    @aliases      = array[8]
    @params       = array[9]

    @parent_name = if @full_name =~ /#/ then
                     $`
                   else
                     name = @full_name.split('::')
                     name.pop
                     name.join '::'
                   end

    array[8].each do |old_name, new_name, comment|
      add_alias RDoc::Alias.new(nil, old_name, new_name, comment)
    end
  end

  ##
  # Method name

  def name
    return @name if @name

    @name = @call_seq[/^.*?\.(\w+)/, 1] || @call_seq if @call_seq
  end

  ##
  # Pretty parameter list for this method

  def param_seq
    params = @params.gsub(/\s*\#.*/, '')
    params = params.tr("\n", " ").squeeze(" ")
    params = "(#{params})" unless params[0] == ?(

    if @block_params then
      # If this method has explicit block parameters, remove any explicit
      # &block
      params.sub!(/,?\s*&\w+/, '')

      block = @block_params.gsub(/\s*\#.*/, '')
      block = block.tr("\n", " ").squeeze(" ")
      if block[0] == ?(
        block.sub!(/^\(/, '').sub!(/\)/, '')
      end
      params << " { |#{block}| ... }"
    end

    params
  end

  ##
  # Name of our parent with special handling for un-marshaled methods

  def parent_name
    @parent_name || super
  end

  ##
  # Path to this method

  def path
    "#{@parent.path}##{aref}"
  end

  ##
  # Method name with class/instance indicator

  def pretty_name
    "#{singleton ? '::' : '#'}#{@name}"
  end

  def pretty_print q # :nodoc:
    alias_for = @is_alias_for ? "alias for #{@is_alias_for.name}" : nil

    q.group 2, "[#{self.class.name} #{full_name} #{visibility}", "]" do
      if alias_for then
        q.breakable
        q.text alias_for
      end

      if text then
        q.breakable
        q.text "text:"
        q.breakable
        q.pp @text
      end

      unless comment.empty? then
        q.breakable
        q.text "comment:"
        q.breakable
        q.pp @comment
      end
    end
  end

  def to_s # :nodoc:
    "#{self.class.name}: #{full_name} (#{@text})\n#{@comment}"
  end

  ##
  # Type of method (class or instance)

  def type
    singleton ? 'class' : 'instance'
  end

end

