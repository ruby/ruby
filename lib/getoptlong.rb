#                                                         -*- Ruby -*-
# Copyright (C) 1998, 1999, 2000  Motoyuki Kasahara
#
# You may redistribute it and/or modify it under the same license
# terms as Ruby.
#

#
# Documents and latest version of `getoptlong.rb' are found at:
#    http://www.sra.co.jp/people/m-kasahr/ruby/getoptlong/
#

#
# Parse command line options just like GNU getopt_long().
#
class GetoptLong
  #
  # Orderings.
  #
  ORDERINGS = [REQUIRE_ORDER = 0, PERMUTE = 1, RETURN_IN_ORDER = 2]

  #
  # Argument flags.
  #
  ARGUMENT_FLAGS = [NO_ARGUMENT = 0, REQUIRED_ARGUMENT = 1,
    OPTIONAL_ARGUMENT = 2]

  #
  # Status codes.
  #
  STATUS_YET, STATUS_STARTED, STATUS_TERMINATED = 0, 1, 2

  #
  # Error types.
  #
  class Error  < StandardError; end
  class AmbigousOption   < Error; end
  class NeedlessArgument < Error; end
  class MissingArgument  < Error; end
  class InvalidOption    < Error; end

  #
  # Initializer.
  #
  def initialize(*arguments)
    #
    # Current ordering.
    #
    if ENV.include?('POSIXLY_CORRECT')
      @ordering = REQUIRE_ORDER
    else
      @ordering = PERMUTE
    end

    #
    # Hash table of option names.
    # Keyes of the table are option names, and their values are canonical
    # names of the options.
    #
    @canonical_names = Hash.new

    #
    # Hash table of argument flags.
    # Keyes of the table are option names, and their values are argument
    # flags of the options.
    #
    @argument_flags = Hash.new

    #
    # Whether error messages are output to stderr.
    #
    @quiet = FALSE

    #
    # Status code.
    #
    @status = STATUS_YET

    #
    # Error code.
    #
    @error = nil

    #
    # Error message.
    #
    @error_message = nil

    #
    # Rest of catinated short options.
    #
    @rest_singles = ''

    #
    # List of non-option-arguments.
    # Append them to ARGV when option processing is terminated.
    #
    @non_option_arguments = Array.new

    if 0 < arguments.length
      set_options(*arguments)
    end
  end

  #
  # Set ordering.
  #
  def ordering=(ordering)
    #
    # The method is failed if option processing has already started.
    #
    if @status != STATUS_YET
      set_error(ArgumentError, "argument error")
      raise RuntimeError,
	"invoke ordering=, but option processing has already started"
    end

    #
    # Check ordering.
    #
    if !ORDERINGS.include?(ordering)
      raise ArgumentError, "invalid ordering `#{ordering}'"
    end
    if ordering == PERMUTE && ENV.include?('POSIXLY_CORRECT')
      @ordering = REQUIRE_ORDER
    else
      @ordering = ordering
    end
  end

  #
  # Return ordering.
  #
  attr_reader :ordering

  #
  # Set options
  #
  def set_options(*arguments)
    #
    # The method is failed if option processing has already started.
    #
    if @status != STATUS_YET
      raise RuntimeError, 
	"invoke set_options, but option processing has already started"
    end

    #
    # Clear tables of option names and argument flags.
    #
    @canonical_names.clear
    @argument_flags.clear

    arguments.each do |arg|
      #
      # Each argument must be an Array.
      #
      if !arg.is_a?(Array)
	raise ArgumentError, "the option list contains non-Array argument"
      end

      #
      # Find an argument flag and it set to `argument_flag'.
      #
      argument_flag = nil
      arg.each do |i|
	if ARGUMENT_FLAGS.include?(i)
	  if argument_flag != nil
	    raise ArgumentError, "too many argument-flags"
	  end
	  argument_flag = i
	end
      end
      raise ArgumentError, "no argument-flag" if argument_flag == nil

      canonical_name = nil
      arg.each do |i|
	#
	# Check an option name.
	#
	next if i == argument_flag
	begin
	  if !i.is_a?(String) || i !~ /^-([^-]|-.+)$/
	    raise ArgumentError, "an invalid option `#{i}'"
	  end
	  if (@canonical_names.include?(i))
	    raise ArgumentError, "option redefined `#{i}'"
	  end
	rescue
	  @canonical_names.clear
	  @argument_flags.clear
	  raise
	end

	#
	# Register the option (`i') to the `@canonical_names' and 
	# `@canonical_names' Hashes.
	#
	if canonical_name == nil
	  canonical_name = i
	end
	@canonical_names[i] = canonical_name
	@argument_flags[i] = argument_flag
      end
      raise ArgumentError, "no option name" if canonical_name == nil
    end
    return self
  end

  #
  # Set/Unset `quit' mode.
  #
  attr_writer :quiet

  #
  # Return the flag of `quiet' mode.
  #
  attr_reader :quiet

  #
  # `quiet?' is an alias of `quiet'.
  #
  alias quiet? quiet

  #
  # Termintate option processing.
  #
  def terminate
    return nil if @status == STATUS_TERMINATED
    raise RuntimeError, "an error has occured" if @error != nil

    @status = STATUS_TERMINATED
    @non_option_arguments.reverse_each do |argument|
      ARGV.unshift(argument)
    end

    @canonical_names = nil
    @argument_flags = nil
    @rest_singles = nil
    @non_option_arguments = nil

    return self
  end

  #
  # Examine whether option processing is termintated or not.
  #
  def terminated?
    return @status == STATUS_TERMINATED
  end

  #
  # Set an error (protected).
  #
  def set_error(type, message)
    $stderr.print("#{$0}: #{message}\n") if !@quiet

    @error = type
    @error_message = message
    @canonical_names = nil
    @argument_flags = nil
    @rest_singles = nil
    @non_option_arguments = nil

    raise type, message
  end
  protected :set_error

  #
  # Examine whether an option processing is failed.
  #
  attr_reader :error

  #
  # `error?' is an alias of `error'.
  #
  alias error? error

  #
  # Return an error message.
  #
  def error_message
    return @error_message
  end

  #
  # Get next option name and its argument as an array.
  #
  def get
    option_name, option_argument = nil, ''

    #
    # Check status.
    #
    return nil if @error != nil
    case @status
    when STATUS_YET
      @status = STATUS_STARTED
    when STATUS_TERMINATED
      return nil
    end

    #
    # Get next option argument.
    #
    if 0 < @rest_singles.length
      argument = '-' + @rest_singles
    elsif (ARGV.length == 0)
      terminate
      return nil
    elsif @ordering == PERMUTE
      while 0 < ARGV.length && ARGV[0] !~ /^-./
	@non_option_arguments.push(ARGV.shift)
      end
      if ARGV.length == 0
	terminate
	return nil
      end
      argument = ARGV.shift
    elsif @ordering == REQUIRE_ORDER 
      if (ARGV[0] !~ /^-./)
	terminate
	return nil
      end
      argument = ARGV.shift
    else
      argument = ARGV.shift
    end

    #
    # Check the special argument `--'.
    # `--' indicates the end of the option list.
    #
    if argument == '--' && @rest_singles.length == 0
      terminate
      return nil
    end

    #
    # Check for long and short options.
    #
    if argument =~ /^(--[^=]+)/ && @rest_singles.length == 0
      #
      # This is a long style option, which start with `--'.
      #
      pattern = $1
      if @canonical_names.include?(pattern)
	option_name = pattern
      else
	#
	# The option `option_name' is not registered in `@canonical_names'.
	# It may be an abbreviated.
	#
	match_count = 0
	@canonical_names.each_key do |key|
	  if key.index(pattern) == 0
	    option_name = key
	    match_count += 1
	  end
	end
	if 2 <= match_count
	  set_error(AmbigousOption, "option `#{argument}' is ambiguous")
	elsif match_count == 0
	  set_error(InvalidOption, "unrecognized option `#{argument}'")
	end
      end

      #
      # Check an argument to the option.
      #
      if @argument_flags[option_name] == REQUIRED_ARGUMENT
	if argument =~ /=(.*)$/
	  option_argument = $1
	elsif 0 < ARGV.length
	  option_argument = ARGV.shift
	else
	  set_error(MissingArgument,
	            "option `#{argument}' requires an argument")
	end
      elsif @argument_flags[option_name] == OPTIONAL_ARGUMENT
	if argument =~ /=(.*)$/
	  option_argument = $1
	elsif 0 < ARGV.length && ARGV[0] !~ /^-./
	  option_argument = ARGV.shift
	else
	  option_argument = ''
	end
      elsif argument =~ /=(.*)$/
	set_error(NeedlessArgument,
		  "option `#{option_name}' doesn't allow an argument")
      end

    elsif argument =~ /^(-(.))(.*)/
      #
      # This is a short style option, which start with `-' (not `--').
      # Short options may be catinated (e.g. `-l -g' is equivalent to
      # `-lg').
      #
      option_name, ch, @rest_singles = $1, $2, $3

      if @canonical_names.include?(option_name)
	#
	# The option `option_name' is found in `@canonical_names'.
	# Check its argument.
	#
	if @argument_flags[option_name] == REQUIRED_ARGUMENT
	  if 0 < @rest_singles.length
	    option_argument = @rest_singles
	    @rest_singles = ''
	  elsif 0 < ARGV.length
	    option_argument = ARGV.shift
	  else
	    # 1003.2 specifies the format of this message.
	    set_error(MissingArgument, "option requires an argument -- #{ch}")
	  end
	elsif @argument_flags[option_name] == OPTIONAL_ARGUMENT
	  if 0 < @rest_singles.length
	    option_argument = @rest_singles
	    @rest_singles = ''
	  elsif 0 < ARGV.length && ARGV[0] !~ /^-./
	    option_argument = ARGV.shift
	  else
	    option_argument = ''
	  end
	end
      else
	#
	# This is an invalid option.
	# 1003.2 specifies the format of this message.
	#
	if ENV.include?('POSIXLY_CORRECT')
	  set_error(InvalidOption, "illegal option -- #{ch}")
	else
	  set_error(InvalidOption, "invalid option -- #{ch}")
	end
      end
    else
      #
      # This is a non-option argument.
      # Only RETURN_IN_ORDER falled into here.
      #
      return '', argument
    end

    return @canonical_names[option_name], option_argument
  end

  #
  # `get_option' is an alias of `get'.
  #
  alias get_option get

  #
  # Iterator version of `get'.
  #
  def each
    loop do
      option_name, option_argument = get_option
      break if option_name == nil
      yield option_name, option_argument
    end
  end

  #
  # `each_option' is an alias of `each'.
  #
  alias each_option each
end
