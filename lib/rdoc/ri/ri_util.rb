######################################################################

class RiError < Exception; end
#
# Break argument into its constituent class or module names, an
# optional method type, and a method name

class NameDescriptor

  attr_reader :class_names
  attr_reader :method_name

  # true and false have the obvious meaning. nil means we don't care
  attr_reader :is_class_method

  # arg may be
  # 1. a class or module name (optionally qualified with other class
  #    or module names (Kernel, File::Stat etc)
  # 2. a method name
  # 3. a method name qualified by a optionally fully qualified class
  #    or module name
  #
  # We're fairly casual about delimiters: folks can say Kernel::puts,
  # Kernel.puts, or Kernel\#puts for example. There's one exception:
  # if you say IO::read, we look for a class method, but if you
  # say IO.read, we look for an instance method

  def initialize(arg)
    @class_names = []
    separator = nil

    tokens = arg.split(/(\.|::|#)/)

    # Skip leading '::', '#' or '.', but remember it might
    # be a method name qualifier
    separator = tokens.shift if tokens[0] =~ /^(\.|::|#)/

    # Skip leading '::', but remember we potentially have an inst

    # leading stuff must be class names

    while tokens[0] =~ /^[A-Z]/
      @class_names << tokens.shift
      unless tokens.empty?
        separator = tokens.shift
        break unless separator == "::"
      end
    end

    # Now must have a single token, the method name, or an empty
    # array
    unless tokens.empty?
      @method_name = tokens.shift
      # We may now have a trailing !, ?, or = to roll into
      # the method name
      if !tokens.empty? && tokens[0] =~ /^[!?=]$/
        @method_name << tokens.shift
      end

      if @method_name =~ /::|\.|#/ or !tokens.empty?
        raise RiError.new("Bad argument: #{arg}")
      end
      if separator && separator != '.'
        @is_class_method = separator == "::"
      end
    end
  end

  # Return the full class name (with '::' between the components)
  # or "" if there's no class name

  def full_class_name
    @class_names.join("::")
  end
end
