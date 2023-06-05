# frozen_string_literal: true

require 'ripper'
require_relative 'syntax_tree/version'

class SyntaxTree < Ripper
  # Represents a line in the source. If this class is being used, it means that
  # every character in the string is 1 byte in length, so we can just return the
  # start of the line + the index.
  class SingleByteString
    def initialize(start)
      @start = start
    end

    def [](byteindex)
      @start + byteindex
    end
  end

  # Represents a line in the source. If this class is being used, it means that
  # there are characters in the string that are multi-byte, so we will build up
  # an array of indices, such that array[byteindex] will be equal to the index
  # of the character within the string.
  class MultiByteString
    def initialize(start, line)
      @indices = []

      line
        .each_char
        .with_index(start) do |char, index|
          char.bytesize.times { @indices << index }
        end
    end

    def [](byteindex)
      @indices[byteindex]
    end
  end

  # Represents the location of a node in the tree from the source code.
  class Location
    attr_reader :start_line, :start_char, :end_line, :end_char

    def initialize(start_line:, start_char:, end_line:, end_char:)
      @start_line = start_line
      @start_char = start_char
      @end_line = end_line
      @end_char = end_char
    end

    def ==(other)
      other.is_a?(Location) && start_line == other.start_line &&
        start_char == other.start_char && end_line == other.end_line &&
        end_char == other.end_char
    end

    def to(other)
      Location.new(
        start_line: start_line,
        start_char: start_char,
        end_line: other.end_line,
        end_char: other.end_char
      )
    end

    def to_json(*opts)
      [start_line, start_char, end_line, end_char].to_json(*opts)
    end

    def self.token(line:, char:, size:)
      new(
        start_line: line,
        start_char: char,
        end_line: line,
        end_char: char + size
      )
    end

    def self.fixed(line:, char:)
      new(start_line: line, start_char: char, end_line: line, end_char: char)
    end
  end

  # A special parser error so that we can get nice syntax displays on the error
  # message when prettier prints out the results.
  class ParseError < StandardError
    attr_reader :lineno, :column

    def initialize(error, lineno, column)
      super(error)
      @lineno = lineno
      @column = column
    end
  end

  attr_reader :source, :lines, :tokens

  # This is an attr_accessor so Stmts objects can grab comments out of this
  # array and attach them to themselves.
  attr_accessor :comments

  def initialize(source, *)
    super

    # We keep the source around so that we can refer back to it when we're
    # generating the AST. Sometimes it's easier to just reference the source
    # string when you want to check if it contains a certain character, for
    # example.
    @source = source

    # Similarly, we keep the lines of the source string around to be able to
    # check if certain lines contain certain characters. For example, we'll use
    # this to generate the content that goes after the __END__ keyword. Or we'll
    # use this to check if a comment has other content on its line.
    @lines = source.split("\n")

    # This is the full set of comments that have been found by the parser. It's
    # a running list. At the end of every block of statements, they will go in
    # and attempt to grab any comments that are on their own line and turn them
    # into regular statements. So at the end of parsing the only comments left
    # in here will be comments on lines that also contain code.
    @comments = []

    # This is the current embdoc (comments that start with =begin and end with
    # =end). Since they can't be nested, there's no need for a stack here, as
    # there can only be one active. These end up getting dumped into the
    # comments list before getting picked up by the statements that surround
    # them.
    @embdoc = nil

    # This is an optional node that can be present if the __END__ keyword is
    # used in the file. In that case, this will represent the content after that
    # keyword.
    @__end__ = nil

    # Heredocs can actually be nested together if you're using interpolation, so
    # this is a stack of heredoc nodes that are currently being created. When we
    # get to the token that finishes off a heredoc node, we pop the top
    # one off. If there are others surrounding it, then the body events will now
    # be added to the correct nodes.
    @heredocs = []

    # This is a running list of tokens that have fired. It's useful
    # mostly for maintaining location information. For example, if you're inside
    # the handle of a def event, then in order to determine where the AST node
    # started, you need to look backward in the tokens to find a def
    # keyword. Most of the time, when a parser event consumes one of these
    # events, it will be deleted from the list. So ideally, this list stays
    # pretty short over the course of parsing a source string.
    @tokens = []

    # Here we're going to build up a list of SingleByteString or MultiByteString
    # objects. They're each going to represent a string in the source. They are
    # used by the `char_pos` method to determine where we are in the source
    # string.
    @line_counts = []
    last_index = 0

    @source.lines.each do |line|
      if line.size == line.bytesize
        @line_counts << SingleByteString.new(last_index)
      else
        @line_counts << MultiByteString.new(last_index, line)
      end

      last_index += line.size
    end
  end

  def self.parse(source)
    parser = new(source)
    response = parser.parse
    response unless parser.error?
  end

  private

  # ----------------------------------------------------------------------------
  # :section: Helper methods
  # The following methods are used by the ripper event handlers to either
  # determine their bounds or query other nodes.
  # ----------------------------------------------------------------------------

  # This represents the current place in the source string that we've gotten to
  # so far. We have a memoized line_counts object that we can use to get the
  # number of characters that we've had to go through to get to the beginning of
  # this line, then we add the number of columns into this line that we've gone
  # through.
  def char_pos
    @line_counts[lineno - 1][column]
  end

  # As we build up a list of tokens, we'll periodically need to go backwards and
  # find the ones that we've already hit in order to determine the location
  # information for nodes that use them. For example, if you have a module node
  # then you'll look backward for a kw token to determine your start location.
  #
  # This works with nesting since we're deleting tokens from the list once
  # they've been used up. For example if you had nested module declarations then
  # the innermost declaration would grab the last kw node that matches "module"
  # (which would happen to be the innermost keyword). Then the outer one would
  # only be able to grab the first one. In this way all of the tokens act as
  # their own stack.
  def find_token(type, value = :any, consume: true)
    index =
      tokens.rindex do |token|
        token.is_a?(type) && (value == :any || (token.value == value))
      end

    if consume
      # If we're expecting to be able to find a token and consume it,
      # but can't actually find it, then we need to raise an error. This is
      # _usually_ caused by a syntax error in the source that we're printing. It
      # could also be caused by accidentally attempting to consume a token twice
      # by two different parser event handlers.
      unless index
        message = "Cannot find expected #{value == :any ? type : value}"
        raise ParseError.new(message, lineno, column)
      end

      tokens.delete_at(index)
    elsif index
      tokens[index]
    end
  end

  # A helper function to find a :: operator. We do special handling instead of
  # using find_token here because we don't pop off all of the ::
  # operators so you could end up getting the wrong information if you have for
  # instance ::X::Y::Z.
  def find_colon2_before(const)
    index =
      tokens.rindex do |token|
        token.is_a?(Op) && token.value == '::' &&
          token.location.start_char < const.location.start_char
      end

    tokens[index]
  end

  # Finds the next position in the source string that begins a statement. This
  # is used to bind statements lists and make sure they don't include a
  # preceding comment. For example, we want the following comment to be attached
  # to the class node and not the statement node:
  #
  #     class Foo # :nodoc:
  #       ...
  #     end
  #
  # By finding the next non-space character, we can make sure that the bounds of
  # the statement list are correct.
  def find_next_statement_start(position)
    remaining = source[position..-1]

    if remaining.sub(/\A +/, '')[0] == '#'
      return position + remaining.index("\n")
    end

    position
  end

  # ----------------------------------------------------------------------------
  # :section: Ripper event handlers
  # The following methods all handle a dispatched ripper event.
  # ----------------------------------------------------------------------------

  # BEGINBlock represents the use of the +BEGIN+ keyword, which hooks into the
  # lifecycle of the interpreter. Whatever is inside the block will get executed
  # when the program starts.
  #
  #     BEGIN {
  #     }
  #
  # Interestingly, the BEGIN keyword doesn't allow the do and end keywords for
  # the block. Only braces are permitted.
  class BEGINBlock
    # [LBrace] the left brace that is seen after the keyword
    attr_reader :lbrace

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(lbrace:, statements:, location:)
      @lbrace = lbrace
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('BEGIN')
        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :BEGIN,
        lbrace: lbrace,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_BEGIN: (Statements statements) -> BEGINBlock
  def on_BEGIN(statements)
    lbrace = find_token(LBrace)
    rbrace = find_token(RBrace)

    statements.bind(
      find_next_statement_start(lbrace.location.end_char),
      rbrace.location.start_char
    )

    keyword = find_token(Kw, 'BEGIN')

    BEGINBlock.new(
      lbrace: lbrace,
      statements: statements,
      location: keyword.location.to(rbrace.location)
    )
  end

  # CHAR irepresents a single codepoint in the script encoding.
  #
  #     ?a
  #
  # In the example above, the CHAR node represents the string literal "a". You
  # can use control characters with this as well, as in ?\C-a.
  class CHAR
    # [String] the value of the character literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('CHAR')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :CHAR, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_CHAR: (String value) -> CHAR
  def on_CHAR(value)
    node =
      CHAR.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # ENDBlock represents the use of the +END+ keyword, which hooks into the
  # lifecycle of the interpreter. Whatever is inside the block will get executed
  # when the program ends.
  #
  #     END {
  #     }
  #
  # Interestingly, the END keyword doesn't allow the do and end keywords for the
  # block. Only braces are permitted.
  class ENDBlock
    # [LBrace] the left brace that is seen after the keyword
    attr_reader :lbrace

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(lbrace:, statements:, location:)
      @lbrace = lbrace
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('END')
        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      { type: :END, lbrace: lbrace, stmts: statements, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_END: (Statements statements) -> ENDBlock
  def on_END(statements)
    lbrace = find_token(LBrace)
    rbrace = find_token(RBrace)

    statements.bind(
      find_next_statement_start(lbrace.location.end_char),
      rbrace.location.start_char
    )

    keyword = find_token(Kw, 'END')

    ENDBlock.new(
      lbrace: lbrace,
      statements: statements,
      location: keyword.location.to(rbrace.location)
    )
  end

  # EndContent represents the use of __END__ syntax, which allows individual
  # scripts to keep content after the main ruby code that can be read through
  # the DATA constant.
  #
  #     puts DATA.read
  #
  #     __END__
  #     some other content that is not executed by the program
  #
  class EndContent
    # [String] the content after the script
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('__end__')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :__end__, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on___end__: (String value) -> EndContent
  def on___end__(value)
    @__end__ =
      EndContent.new(
        value: lines[lineno..-1].join("\n"),
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )
  end

  # Alias represents the use of the +alias+ keyword with regular arguments (not
  # global variables). The +alias+ keyword is used to make a method respond to
  # another name as well as the current one.
  #
  #     alias aliased_name name
  #
  # For the example above, in the current context you can now call aliased_name
  # and it will execute the name method. When you're aliasing two methods, you
  # can either provide bare words (like the example above) or you can provide
  # symbols (note that this includes dynamic symbols like
  # :"left-#{middle}-right").
  class Alias
    # [DynaSymbol | SymbolLiteral] the new name of the method
    attr_reader :left

    # [DynaSymbol | SymbolLiteral] the old name of the method
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('alias')
        q.breakable
        q.pp(left)
        q.breakable
        q.pp(right)
      end
    end

    def to_json(*opts)
      { type: :alias, left: left, right: right, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_alias: (
  #     (DynaSymbol | SymbolLiteral) left,
  #     (DynaSymbol | SymbolLiteral) right
  #   ) -> Alias
  def on_alias(left, right)
    keyword = find_token(Kw, 'alias')

    Alias.new(
      left: left,
      right: right,
      location: keyword.location.to(right.location)
    )
  end

  # ARef represents when you're pulling a value out of a collection at a
  # specific index. Put another way, it's any time you're calling the method
  # #[].
  #
  #     collection[index]
  #
  # The nodes usually contains two children, the collection and the index. In
  # some cases, you don't necessarily have the second child node, because you
  # can call procs with a pretty esoteric syntax. In the following example, you
  # wouldn't have a second child node:
  #
  #     collection[]
  #
  class ARef
    # [untyped] the value being indexed
    attr_reader :collection

    # [nil | Args | ArgsAddBlock] the value being passed within the brackets
    attr_reader :index

    # [Location] the location of this node
    attr_reader :location

    def initialize(collection:, index:, location:)
      @collection = collection
      @index = index
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('aref')
        q.breakable
        q.pp(collection)
        q.breakable
        q.pp(index)
      end
    end

    def to_json(*opts)
      {
        type: :aref,
        collection: collection,
        index: index,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_aref: (untyped collection, (nil | Args | ArgsAddBlock) index) -> ARef
  def on_aref(collection, index)
    find_token(LBracket)
    rbracket = find_token(RBracket)

    ARef.new(
      collection: collection,
      index: index,
      location: collection.location.to(rbracket.location)
    )
  end

  # ARefField represents assigning values into collections at specific indices.
  # Put another way, it's any time you're calling the method #[]=. The
  # ARefField node itself is just the left side of the assignment, and they're
  # always wrapped in assign nodes.
  #
  #     collection[index] = value
  #
  class ARefField
    # [untyped] the value being indexed
    attr_reader :collection

    # [nil | ArgsAddBlock] the value being passed within the brackets
    attr_reader :index

    # [Location] the location of this node
    attr_reader :location

    def initialize(collection:, index:, location:)
      @collection = collection
      @index = index
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('aref_field')
        q.breakable
        q.pp(collection)
        q.breakable
        q.pp(index)
      end
    end

    def to_json(*opts)
      {
        type: :aref_field,
        collection: collection,
        index: index,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_aref_field: (
  #     untyped collection,
  #     (nil | ArgsAddBlock) index
  #   ) -> ARefField
  def on_aref_field(collection, index)
    find_token(LBracket)
    rbracket = find_token(RBracket)

    ARefField.new(
      collection: collection,
      index: index,
      location: collection.location.to(rbracket.location)
    )
  end

  # def on_arg_ambiguous(value)
  #   value
  # end

  # ArgParen represents wrapping arguments to a method inside a set of
  # parentheses.
  #
  #     method(argument)
  #
  # In the example above, there would be an ArgParen node around the
  # ArgsAddBlock node that represents the set of arguments being sent to the
  # method method. The argument child node can be +nil+ if no arguments were
  # passed, as in:
  #
  #     method()
  #
  class ArgParen
    # [nil | Args | ArgsAddBlock | ArgsForward] the arguments inside the
    # parentheses
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('arg_paren')
        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :arg_paren, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_arg_paren: (
  #     (nil | Args | ArgsAddBlock | ArgsForward) arguments
  #   ) -> ArgParen
  def on_arg_paren(arguments)
    lparen = find_token(LParen)
    rparen = find_token(RParen)

    # If the arguments exceed the ending of the parentheses, then we know we
    # have a heredoc in the arguments, and we need to use the bounds of the
    # arguments to determine how large the arg_paren is.
    ending =
      if arguments && arguments.location.end_line > rparen.location.end_line
        arguments
      else
        rparen
      end

    ArgParen.new(
      arguments: arguments,
      location: lparen.location.to(ending.location)
    )
  end

  # Args represents a list of arguments being passed to a method call or array
  # literal.
  #
  #     method(first, second, third)
  #
  class Args
    # [Array[ untyped ]] the arguments that this node wraps
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('args')
        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :args, parts: parts, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_args_add: (Args arguments, untyped argument) -> Args
  def on_args_add(arguments, argument)
    if arguments.parts.empty?
      # If this is the first argument being passed into the list of arguments,
      # then we're going to use the bounds of the argument to override the
      # parent node's location since this will be more accurate.
      Args.new(parts: [argument], location: argument.location)
    else
      # Otherwise we're going to update the existing list with the argument
      # being added as well as the new end bounds.
      Args.new(
        parts: arguments.parts << argument,
        location: arguments.location.to(argument.location)
      )
    end
  end

  # ArgsAddBlock represents a list of arguments and potentially a block
  # argument. ArgsAddBlock is commonly seen being passed to any method where you
  # use parentheses (wrapped in an ArgParen node). It’s also used to pass
  # arguments to the various control-flow keywords like +return+.
  #
  #     method(argument, &block)
  #
  class ArgsAddBlock
    # [Args] the arguments before the optional block
    attr_reader :arguments

    # [nil | untyped] the optional block argument
    attr_reader :block

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, block:, location:)
      @arguments = arguments
      @block = block
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('args_add_block')
        q.breakable
        q.pp(arguments)
        q.breakable
        q.pp(block)
      end
    end

    def to_json(*opts)
      {
        type: :args_add_block,
        args: arguments,
        block: block,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_args_add_block: (
  #     Args arguments,
  #     (false | untyped) block
  #   ) -> ArgsAddBlock
  def on_args_add_block(arguments, block)
    ending = block || arguments

    ArgsAddBlock.new(
      arguments: arguments,
      block: block || nil,
      location: arguments.location.to(ending.location)
    )
  end

  # Star represents using a splat operator on an expression.
  #
  #     method(*arguments)
  #
  class ArgStar
    # [untyped] the expression being splatted
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('arg_star')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :arg_star, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_args_add_star: (Args arguments, untyped star) -> Args
  def on_args_add_star(arguments, argument)
    beginning = find_token(Op, '*')
    ending = argument || beginning

    location =
      if arguments.parts.empty?
        ending.location
      else
        arguments.location.to(ending.location)
      end

    arg_star =
      ArgStar.new(
        value: argument,
        location: beginning.location.to(ending.location)
      )

    Args.new(parts: arguments.parts << arg_star, location: location)
  end

  # ArgsForward represents forwarding all kinds of arguments onto another method
  # call.
  #
  #     def request(method, path, **headers, &block); end
  #
  #     def get(...)
  #       request(:GET, ...)
  #     end
  #
  #     def post(...)
  #       request(:POST, ...)
  #     end
  #
  # In the example above, both the get and post methods are forwarding all of
  # their arguments (positional, keyword, and block) on to the request method.
  # The ArgsForward node appears in both the caller (the request method calls)
  # and the callee (the get and post definitions).
  class ArgsForward
    # [String] the value of the operator
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('args_forward')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :args_forward, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_args_forward: () -> ArgsForward
  def on_args_forward
    op = find_token(Op, '...')

    ArgsForward.new(value: op.value, location: op.location)
  end

  # :call-seq:
  #   on_args_new: () -> Args
  def on_args_new
    Args.new(parts: [], location: Location.fixed(line: lineno, char: char_pos))
  end

  # ArrayLiteral represents any form of an array literal, and contains myriad
  # child nodes because of the special array literal syntax like %w and %i.
  #
  #     []
  #     [one, two, three]
  #     [*one_two_three]
  #     %i[one two three]
  #     %w[one two three]
  #     %I[one two three]
  #     %W[one two three]
  #
  # Every line in the example above produces an ArrayLiteral node. In order, the
  # child contents node of this ArrayLiteral node would be nil, Args, QSymbols,
  # QWords, Symbols, and Words.
  class ArrayLiteral
    # [nil | Args | QSymbols | QWords | Symbols | Words] the
    # contents of the array
    attr_reader :contents

    # [Location] the location of this node
    attr_reader :location

    def initialize(contents:, location:)
      @contents = contents
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('array')
        q.breakable
        q.pp(contents)
      end
    end

    def to_json(*opts)
      { type: :array, cnts: contents, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_array: (
  #     (nil | Args | QSymbols | QWords | Symbols | Words) contents
  #   ) -> ArrayLiteral
  def on_array(contents)
    if !contents || contents.is_a?(Args)
      lbracket = find_token(LBracket)
      rbracket = find_token(RBracket)

      ArrayLiteral.new(
        contents: contents,
        location: lbracket.location.to(rbracket.location)
      )
    else
      tstring_end = find_token(TStringEnd)
      contents =
        contents.class.new(
          elements: contents.elements,
          location: contents.location.to(tstring_end.location)
        )

      ArrayLiteral.new(contents: contents, location: contents.location)
    end
  end

  # AryPtn represents matching against an array pattern using the Ruby 2.7+
  # pattern matching syntax. It’s one of the more complicated nodes, because
  # the four parameters that it accepts can almost all be nil.
  #
  #     case [1, 2, 3]
  #     in [Integer, Integer]
  #       "matched"
  #     in Container[Integer, Integer]
  #       "matched"
  #     in [Integer, *, Integer]
  #       "matched"
  #     end
  #
  # An AryPtn node is created with four parameters: an optional constant
  # wrapper, an array of positional matches, an optional splat with identifier,
  # and an optional array of positional matches that occur after the splat.
  # All of the in clauses above would create an AryPtn node.
  class AryPtn
    # [nil | VarRef] the optional constant wrapper
    attr_reader :constant

    # [Array[ untyped ]] the regular positional arguments that this array
    # pattern is matching against
    attr_reader :requireds

    # [nil | VarField] the optional starred identifier that grabs up a list of
    # positional arguments
    attr_reader :rest

    # [Array[ untyped ]] the list of positional arguments occurring after the
    # optional star if there is one
    attr_reader :posts

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, requireds:, rest:, posts:, location:)
      @constant = constant
      @requireds = requireds
      @rest = rest
      @posts = posts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('aryptn')

        if constant
          q.breakable
          q.pp(constant)
        end

        if requireds.any?
          q.breakable
          q.group(2, '(', ')') do
            q.seplist(requireds) { |required| q.pp(required) }
          end
        end

        if rest
          q.breakable
          q.pp(rest)
        end

        if posts.any?
          q.breakable
          q.group(2, '(', ')') { q.seplist(posts) { |post| q.pp(post) } }
        end
      end
    end

    def to_json(*opts)
      {
        type: :aryptn,
        constant: constant,
        reqs: requireds,
        rest: rest,
        posts: posts,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_aryptn: (
  #     (nil | VarRef) constant,
  #     (nil | Array[untyped]) requireds,
  #     (nil | VarField) rest,
  #     (nil | Array[untyped]) posts
  #   ) -> AryPtn
  def on_aryptn(constant, requireds, rest, posts)
    parts = [constant, *requireds, rest, *posts].compact

    AryPtn.new(
      constant: constant,
      requireds: requireds || [],
      rest: rest,
      posts: posts || [],
      location: parts[0].location.to(parts[-1].location)
    )
  end

  # Assign represents assigning something to a variable or constant. Generally,
  # the left side of the assignment is going to be any node that ends with the
  # name "Field".
  #
  #     variable = value
  #
  class Assign
    # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
    # to assign the result of the expression to
    attr_reader :target

    # [untyped] the expression to be assigned
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(target:, value:, location:)
      @target = target
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('assign')
        q.breakable
        q.pp(target)
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :assign, target: target, value: value, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_assign: (
  #     (ARefField | ConstPathField | Field | TopConstField | VarField) target,
  #     untyped value
  #   ) -> Assign
  def on_assign(target, value)
    Assign.new(
      target: target,
      value: value,
      location: target.location.to(value.location)
    )
  end

  # Assoc represents a key-value pair within a hash. It is a child node of
  # either an AssocListFromArgs or a BareAssocHash.
  #
  #     { key1: value1, key2: value2 }
  #
  # In the above example, the would be two AssocNew nodes.
  class Assoc
    # [untyped] the key of this pair
    attr_reader :key

    # [untyped] the value of this pair
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(key:, value:, location:)
      @key = key
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('assoc')
        q.breakable
        q.pp(key)
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :assoc, key: key, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_assoc_new: (untyped key, untyped value) -> Assoc
  def on_assoc_new(key, value)
    Assoc.new(
      key: key,
      value: value,
      location: key.location.to(value.location)
    )
  end

  # AssocSplat represents double-splatting a value into a hash (either a hash
  # literal or a bare hash in a method call).
  #
  #     { **pairs }
  #
  class AssocSplat
    # [untyped] the expression that is being splatted
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('assoc_splat')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :assoc_splat, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_assoc_splat: (untyped value) -> AssocSplat
  def on_assoc_splat(value)
    operator = find_token(Op, '**')

    AssocSplat.new(value: value, location: operator.location.to(value.location))
  end

  # AssocListFromArgs represents the key-value pairs of a hash literal. Its
  # parent node is always a hash.
  #
  #     { key1: value1, key2: value2 }
  #
  class AssocListFromArgs
    # [Array[ AssocNew | AssocSplat ]]
    attr_reader :assocs

    # [Location] the location of this node
    attr_reader :location

    def initialize(assocs:, location:)
      @assocs = assocs
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('assoclist_from_args')
        q.breakable
        q.group(2, '(', ')') { q.seplist(assocs) { |assoc| q.pp(assoc) } }
      end
    end

    def to_json(*opts)
      { type: :assoclist_from_args, assocs: assocs, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_assoclist_from_args: (
  #     Array[AssocNew | AssocSplat] assocs
  #   ) -> AssocListFromArgs
  def on_assoclist_from_args(assocs)
    AssocListFromArgs.new(
      assocs: assocs,
      location: assocs[0].location.to(assocs[-1].location)
    )
  end

  # Backref represents a global variable referencing a matched value. It comes
  # in the form of a $ followed by a positive integer.
  #
  #     $1
  #
  class Backref
    # [String] the name of the global backreference variable
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('backref')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :backref, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_backref: (String value) -> Backref
  def on_backref(value)
    node =
      Backref.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Backtick represents the use of the ` operator. It's usually found being used
  # for an XStringLiteral, but could also be found as the name of a method being
  # defined.
  class Backtick
    # [String] the backtick in the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('backtick')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :backtick, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_backtick: (String value) -> Backtick
  def on_backtick(value)
    node =
      Backtick.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # BareAssocHash represents a hash of contents being passed as a method
  # argument (and therefore has omitted braces). It's very similar to an
  # AssocListFromArgs node.
  #
  #     method(key1: value1, key2: value2)
  #
  class BareAssocHash
    # [Array[ AssocNew | AssocSplat ]]
    attr_reader :assocs

    # [Location] the location of this node
    attr_reader :location

    def initialize(assocs:, location:)
      @assocs = assocs
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('bare_assoc_hash')
        q.breakable
        q.group(2, '(', ')') { q.seplist(assocs) { |assoc| q.pp(assoc) } }
      end
    end

    def to_json(*opts)
      { type: :bare_assoc_hash, assocs: assocs, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_bare_assoc_hash: (Array[AssocNew | AssocSplat] assocs) -> BareAssocHash
  def on_bare_assoc_hash(assocs)
    BareAssocHash.new(
      assocs: assocs,
      location: assocs[0].location.to(assocs[-1].location)
    )
  end

  # Begin represents a begin..end chain.
  #
  #     begin
  #       value
  #     end
  #
  class Begin
    # [BodyStmt] the bodystmt that contains the contents of this begin block
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(bodystmt:, location:)
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('begin')
        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      { type: :begin, bodystmt: bodystmt, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_begin: (BodyStmt bodystmt) -> Begin
  def on_begin(bodystmt)
    keyword = find_token(Kw, 'begin')
    end_char =
      if bodystmt.rescue_clause || bodystmt.ensure_clause ||
           bodystmt.else_clause
        bodystmt.location.end_char
      else
        find_token(Kw, 'end').location.end_char
      end

    bodystmt.bind(keyword.location.end_char, end_char)

    Begin.new(
      bodystmt: bodystmt,
      location: keyword.location.to(bodystmt.location)
    )
  end

  # Binary represents any expression that involves two sub-expressions with an
  # operator in between. This can be something that looks like a mathematical
  # operation:
  #
  #     1 + 1
  #
  # but can also be something like pushing a value onto an array:
  #
  #     array << value
  #
  class Binary
    # [untyped] the left-hand side of the expression
    attr_reader :left

    # [String] the operator used between the two expressions
    attr_reader :operator

    # [untyped] the right-hand side of the expression
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, operator:, right:, location:)
      @left = left
      @operator = operator
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('binary')
        q.breakable
        q.pp(left)
        q.breakable
        q.text(operator)
        q.breakable
        q.pp(right)
      end
    end

    def to_json(*opts)
      {
        type: :binary,
        left: left,
        op: operator,
        right: right,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_binary: (untyped left, (Op | Symbol) operator, untyped right) -> Binary
  def on_binary(left, operator, right)
    # On most Ruby implementations, operator is a Symbol that represents that
    # operation being performed. For instance in the example `1 < 2`, the
    # `operator` object would be `:<`. However, on JRuby, it's an `@op` node,
    # so here we're going to explicitly convert it into the same normalized
    # form.
    operator = tokens.delete(operator).value unless operator.is_a?(Symbol)

    Binary.new(
      left: left,
      operator: operator,
      right: right,
      location: left.location.to(right.location)
    )
  end

  # BlockVar represents the parameters being declared for a block. Effectively
  # this node is everything contained within the pipes. This includes all of the
  # various parameter types, as well as block-local variable declarations.
  #
  #     method do |positional, optional = value, keyword:, &block; local|
  #     end
  #
  class BlockVar
    # [Params] the parameters being declared with the block
    attr_reader :params

    # [Array[ Ident ]] the list of block-local variable declarations
    attr_reader :locals

    # [Location] the location of this node
    attr_reader :location

    def initialize(params:, locals:, location:)
      @params = params
      @locals = locals
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('block_var')
        q.breakable
        q.pp(params)

        if locals.any?
          q.breakable
          q.group(2, '(', ')') { q.seplist(locals) { |local| q.pp(local) } }
        end
      end
    end

    def to_json(*opts)
      {
        type: :block_var,
        params: params,
        locals: locals,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_block_var: (Params params, (nil | Array[Ident]) locals) -> BlockVar
  def on_block_var(params, locals)
    index =
      tokens.rindex do |node|
        node.is_a?(Op) && %w[| ||].include?(node.value) &&
          node.location.start_char < params.location.start_char
      end

    beginning = tokens[index]
    ending = tokens[-1]

    BlockVar.new(
      params: params,
      locals: locals || [],
      location: beginning.location.to(ending.location)
    )
  end

  # BlockArg represents declaring a block parameter on a method definition.
  #
  #     def method(&block); end
  #
  class BlockArg
    # [Ident] the name of the block argument
    attr_reader :name

    # [Location] the location of this node
    attr_reader :location

    def initialize(name:, location:)
      @name = name
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('blockarg')
        q.breakable
        q.pp(name)
      end
    end

    def to_json(*opts)
      { type: :blockarg, name: name, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_blockarg: (Ident name) -> BlockArg
  def on_blockarg(name)
    operator = find_token(Op, '&')

    BlockArg.new(name: name, location: operator.location.to(name.location))
  end

  # bodystmt can't actually determine its bounds appropriately because it
  # doesn't necessarily know where it started. So the parent node needs to
  # report back down into this one where it goes.
  class BodyStmt
    # [Statements] the list of statements inside the begin clause
    attr_reader :statements

    # [nil | Rescue] the optional rescue chain attached to the begin clause
    attr_reader :rescue_clause

    # [nil | Statements] the optional set of statements inside the else clause
    attr_reader :else_clause

    # [nil | Ensure] the optional ensure clause
    attr_reader :ensure_clause

    # [Location] the location of this node
    attr_reader :location

    def initialize(
      statements:,
      rescue_clause:,
      else_clause:,
      ensure_clause:,
      location:
    )
      @statements = statements
      @rescue_clause = rescue_clause
      @else_clause = else_clause
      @ensure_clause = ensure_clause
      @location = location
    end

    def bind(start_char, end_char)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          end_line: location.end_line,
          end_char: end_char
        )

      parts = [rescue_clause, else_clause, ensure_clause]

      # Here we're going to determine the bounds for the statements
      consequent = parts.compact.first
      statements.bind(
        start_char,
        consequent ? consequent.location.start_char : end_char
      )

      # Next we're going to determine the rescue clause if there is one
      if rescue_clause
        consequent = parts.drop(1).compact.first
        rescue_clause.bind_end(
          consequent ? consequent.location.start_char : end_char
        )
      end
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('bodystmt')
        q.breakable
        q.pp(statements)

        if rescue_clause
          q.breakable
          q.pp(rescue_clause)
        end

        if else_clause
          q.breakable
          q.pp(else_clause)
        end

        if ensure_clause
          q.breakable
          q.pp(ensure_clause)
        end
      end
    end

    def to_json(*opts)
      {
        type: :bodystmt,
        stmts: statements,
        rsc: rescue_clause,
        els: else_clause,
        ens: ensure_clause,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_bodystmt: (
  #     Statements statements,
  #     (nil | Rescue) rescue_clause,
  #     (nil | Statements) else_clause,
  #     (nil | Ensure) ensure_clause
  #   ) -> BodyStmt
  def on_bodystmt(statements, rescue_clause, else_clause, ensure_clause)
    BodyStmt.new(
      statements: statements,
      rescue_clause: rescue_clause,
      else_clause: else_clause,
      ensure_clause: ensure_clause,
      location: Location.fixed(line: lineno, char: char_pos)
    )
  end

  # BraceBlock represents passing a block to a method call using the { }
  # operators.
  #
  #     method { |variable| variable + 1 }
  #
  class BraceBlock
    # [LBrace] the left brace that opens this block
    attr_reader :lbrace

    # [nil | BlockVar] the optional set of parameters to the block
    attr_reader :block_var

    # [Statements] the list of expressions to evaluate within the block
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(lbrace:, block_var:, statements:, location:)
      @lbrace = lbrace
      @block_var = block_var
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('brace_block')

        if block_var
          q.breakable
          q.pp(block_var)
        end

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :brace_block,
        lbrace: lbrace,
        block_var: block_var,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_brace_block: (
  #     (nil | BlockVar) block_var,
  #     Statements statements
  #   ) -> BraceBlock
  def on_brace_block(block_var, statements)
    lbrace = find_token(LBrace)
    rbrace = find_token(RBrace)

    statements.bind(
      find_next_statement_start((block_var || lbrace).location.end_char),
      rbrace.location.start_char
    )

    location =
      Location.new(
        start_line: lbrace.location.start_line,
        start_char: lbrace.location.start_char,
        end_line: [rbrace.location.end_line, statements.location.end_line].max,
        end_char: rbrace.location.end_char
      )

    BraceBlock.new(
      lbrace: lbrace,
      block_var: block_var,
      statements: statements,
      location: location
    )
  end

  # Break represents using the +break+ keyword.
  #
  #     break
  #
  # It can also optionally accept arguments, as in:
  #
  #     break 1
  #
  class Break
    # [Args | ArgsAddBlock] the arguments being sent to the keyword
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('break')
        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :break, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_break: ((Args | ArgsAddBlock) arguments) -> Break
  def on_break(arguments)
    keyword = find_token(Kw, 'break')

    location = keyword.location
    location = location.to(arguments.location) unless arguments.is_a?(Args)

    Break.new(arguments: arguments, location: location)
  end

  # Call represents a method call. This node doesn't contain the arguments being
  # passed (if arguments are passed, this node will get nested under a
  # MethodAddArg node).
  #
  #     receiver.message
  #
  class Call
    # [untyped] the receiver of the method call
    attr_reader :receiver

    # [:"::" | Op | Period] the operator being used to send the message
    attr_reader :operator

    # [:call | Backtick | Const | Ident | Op] the message being sent
    attr_reader :message

    # [Location] the location of this node
    attr_reader :location

    def initialize(receiver:, operator:, message:, location:)
      @receiver = receiver
      @operator = operator
      @message = message
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('call')
        q.breakable
        q.pp(receiver)
        q.breakable
        q.pp(operator)
        q.breakable
        q.pp(message)
      end
    end

    def to_json(*opts)
      {
        type: :call,
        receiver: receiver,
        op: operator,
        message: message,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_call: (
  #     untyped receiver,
  #     (:"::" | Op | Period) operator,
  #     (:call | Backtick | Const | Ident | Op) message
  #   ) -> Call
  def on_call(receiver, operator, message)
    ending = message
    ending = operator if message == :call

    Call.new(
      receiver: receiver,
      operator: operator,
      message: message,
      location:
        Location.new(
          start_line: receiver.location.start_line,
          start_char: receiver.location.start_char,
          end_line: [ending.location.end_line, receiver.location.end_line].max,
          end_char: ending.location.end_char
        )
    )
  end

  # Case represents the beginning of a case chain.
  #
  #     case value
  #     when 1
  #       "one"
  #     when 2
  #       "two"
  #     else
  #       "number"
  #     end
  #
  class Case
    # [nil | untyped] optional value being switched on
    attr_reader :value

    # [In | When] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, consequent:, location:)
      @value = value
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('case')

        if value
          q.breakable
          q.pp(value)
        end

        q.breakable
        q.pp(consequent)
      end
    end

    def to_json(*opts)
      { type: :case, value: value, cons: consequent, loc: location }.to_json(
        *opts
      )
    end
  end

  # RAssign represents a single-line pattern match.
  #
  #     value in pattern
  #     value => pattern
  #
  class RAssign
    # [untyped] the left-hand expression
    attr_reader :value

    # [Kw | Op] the operator being used to match against the pattern, which is
    # either => or in
    attr_reader :operator

    # [untyped] the pattern on the right-hand side of the expression
    attr_reader :pattern

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, operator:, pattern:, location:)
      @value = value
      @operator = operator
      @pattern = pattern
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rassign')

        q.breakable
        q.pp(value)

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(pattern)
      end
    end

    def to_json(*opts)
      {
        type: :rassign,
        value: value,
        op: operator,
        pattern: pattern,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_case: (untyped value, untyped consequent) -> Case | RAssign
  def on_case(value, consequent)
    if keyword = find_token(Kw, 'case', consume: false)
      tokens.delete(keyword)

      Case.new(
        value: value,
        consequent: consequent,
        location: keyword.location.to(consequent.location)
      )
    else
      operator = find_token(Kw, 'in', consume: false) || find_token(Op, '=>')

      RAssign.new(
        value: value,
        operator: operator,
        pattern: consequent,
        location: value.location.to(consequent.location)
      )
    end
  end

  # Class represents defining a class using the +class+ keyword.
  #
  #     class Container
  #     end
  #
  # Classes can have path names as their class name in case it's being nested
  # under a namespace, as in:
  #
  #     class Namespace::Container
  #     end
  #
  # Classes can also be defined as a top-level path, in the case that it's
  # already in a namespace but you want to define it at the top-level instead,
  # as in:
  #
  #     module OtherNamespace
  #       class ::Namespace::Container
  #       end
  #     end
  #
  # All of these declarations can also have an optional superclass reference, as
  # in:
  #
  #     class Child < Parent
  #     end
  #
  # That superclass can actually be any Ruby expression, it doesn't necessarily
  # need to be a constant, as in:
  #
  #     class Child < method
  #     end
  #
  class ClassDeclaration
    # [ConstPathRef | ConstRef | TopConstRef] the name of the class being
    # defined
    attr_reader :constant

    # [nil | untyped] the optional superclass declaration
    attr_reader :superclass

    # [BodyStmt] the expressions to execute within the context of the class
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, superclass:, bodystmt:, location:)
      @constant = constant
      @superclass = superclass
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('class')

        q.breakable
        q.pp(constant)

        if superclass
          q.breakable
          q.pp(superclass)
        end

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :class,
        constant: constant,
        superclass: superclass,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_class: (
  #     (ConstPathRef | ConstRef | TopConstRef) constant,
  #     untyped superclass,
  #     BodyStmt bodystmt
  #   ) -> ClassDeclaration
  def on_class(constant, superclass, bodystmt)
    beginning = find_token(Kw, 'class')
    ending = find_token(Kw, 'end')

    bodystmt.bind(
      find_next_statement_start((superclass || constant).location.end_char),
      ending.location.start_char
    )

    ClassDeclaration.new(
      constant: constant,
      superclass: superclass,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # Comma represents the use of the , operator.
  class Comma
    # [String] the comma in the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_comma: (String value) -> Comma
  def on_comma(value)
    node =
      Comma.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Command represents a method call with arguments and no parentheses. Note
  # that Command nodes only happen when there is no explicit receiver for this
  # method.
  #
  #     method argument
  #
  class Command
    # [Const | Ident] the message being sent to the implicit receiver
    attr_reader :message

    # [Args | ArgsAddBlock] the arguments being sent with the message
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(message:, arguments:, location:)
      @message = message
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('command')

        q.breakable
        q.pp(message)

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      {
        type: :command,
        message: message,
        args: arguments,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_command: (
  #     (Const | Ident) message,
  #     (Args | ArgsAddBlock) arguments
  #   ) -> Command
  def on_command(message, arguments)
    Command.new(
      message: message,
      arguments: arguments,
      location: message.location.to(arguments.location)
    )
  end

  # CommandCall represents a method call on an object with arguments and no
  # parentheses.
  #
  #     object.method argument
  #
  class CommandCall
    # [untyped] the receiver of the message
    attr_reader :receiver

    # [:"::" | Op | Period] the operator used to send the message
    attr_reader :operator

    # [Const | Ident | Op] the message being send
    attr_reader :message

    # [Args | ArgsAddBlock] the arguments going along with the message
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(receiver:, operator:, message:, arguments:, location:)
      @receiver = receiver
      @operator = operator
      @message = message
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('command_call')

        q.breakable
        q.pp(receiver)

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(message)

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      {
        type: :command_call,
        receiver: receiver,
        op: operator,
        message: message,
        args: arguments,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_command_call: (
  #     untyped receiver,
  #     (:"::" | Op | Period) operator,
  #     (Const | Ident | Op) message,
  #     (Args | ArgsAddBlock) arguments
  #   ) -> CommandCall
  def on_command_call(receiver, operator, message, arguments)
    ending = arguments || message

    CommandCall.new(
      receiver: receiver,
      operator: operator,
      message: message,
      arguments: arguments,
      location: receiver.location.to(ending.location)
    )
  end

  # Comment represents a comment in the source.
  #
  #     # comment
  #
  class Comment
    # [String] the contents of the comment
    attr_reader :value

    # [boolean] whether or not there is code on the same line as this comment.
    # If there is, then inline will be true.
    attr_reader :inline
    alias inline? inline

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, inline:, location:)
      @value = value
      @inline = inline
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('comment')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      {
        type: :comment,
        value: value.force_encoding('UTF-8'),
        inline: inline,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_comment: (String value) -> Comment
  def on_comment(value)
    line = lineno
    comment =
      Comment.new(
        value: value[1..-1].chomp,
        inline: value.strip != lines[line - 1],
        location:
          Location.token(line: line, char: char_pos, size: value.size - 1)
      )

    @comments << comment
    comment
  end

  # Const represents a literal value that _looks_ like a constant. This could
  # actually be a reference to a constant:
  #
  #     Constant
  #
  # It could also be something that looks like a constant in another context, as
  # in a method call to a capitalized method:
  #
  #     object.Constant
  #
  # or a symbol that starts with a capital letter:
  #
  #     :Constant
  #
  class Const
    # [String] the name of the constant
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('const')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :const, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_const: (String value) -> Const
  def on_const(value)
    node =
      Const.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # ConstPathField represents the child node of some kind of assignment. It
  # represents when you're assigning to a constant that is being referenced as
  # a child of another variable.
  #
  #     object::Const = value
  #
  class ConstPathField
    # [untyped] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Location] the location of this node
    attr_reader :location

    def initialize(parent:, constant:, location:)
      @parent = parent
      @constant = constant
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('const_path_field')

        q.breakable
        q.pp(parent)

        q.breakable
        q.pp(constant)
      end
    end

    def to_json(*opts)
      {
        type: :const_path_field,
        parent: parent,
        constant: constant,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_const_path_field: (untyped parent, Const constant) -> ConstPathField
  def on_const_path_field(parent, constant)
    ConstPathField.new(
      parent: parent,
      constant: constant,
      location: parent.location.to(constant.location)
    )
  end

  # ConstPathRef represents referencing a constant by a path.
  #
  #     object::Const
  #
  class ConstPathRef
    # [untyped] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Location] the location of this node
    attr_reader :location

    def initialize(parent:, constant:, location:)
      @parent = parent
      @constant = constant
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('const_path_ref')

        q.breakable
        q.pp(parent)

        q.breakable
        q.pp(constant)
      end
    end

    def to_json(*opts)
      {
        type: :const_path_ref,
        parent: parent,
        constant: constant,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_const_path_ref: (untyped parent, Const constant) -> ConstPathRef
  def on_const_path_ref(parent, constant)
    ConstPathRef.new(
      parent: parent,
      constant: constant,
      location: parent.location.to(constant.location)
    )
  end

  # ConstRef represents the name of the constant being used in a class or module
  # declaration.
  #
  #     class Container
  #     end
  #
  class ConstRef
    # [Const] the constant itself
    attr_reader :constant

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, location:)
      @constant = constant
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('const_ref')

        q.breakable
        q.pp(constant)
      end
    end

    def to_json(*opts)
      { type: :const_ref, constant: constant, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_const_ref: (Const constant) -> ConstRef
  def on_const_ref(constant)
    ConstRef.new(constant: constant, location: constant.location)
  end

  # CVar represents the use of a class variable.
  #
  #     @@variable
  #
  class CVar
    # [String] the name of the class variable
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('cvar')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :cvar, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_cvar: (String value) -> CVar
  def on_cvar(value)
    node =
      CVar.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Def represents defining a regular method on the current self object.
  #
  #     def method(param) result end
  #
  class Def
    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [Params | Paren] the parameter declaration for the method
    attr_reader :params

    # [BodyStmt] the expressions to be executed by the method
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(name:, params:, bodystmt:, location:)
      @name = name
      @params = params
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('def')

        q.breakable
        q.pp(name)

        q.breakable
        q.pp(params)

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :def,
        name: name,
        params: params,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # DefEndless represents defining a single-line method since Ruby 3.0+.
  #
  #     def method = result
  #
  class DefEndless
    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [Paren] the parameter declaration for the method
    attr_reader :paren

    # [untyped] the expression to be executed by the method
    attr_reader :statement

    # [Location] the location of this node
    attr_reader :location

    def initialize(name:, paren:, statement:, location:)
      @name = name
      @paren = paren
      @statement = statement
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('def_endless')

        q.breakable
        q.pp(name)

        q.breakable
        q.pp(paren)

        q.breakable
        q.pp(statement)
      end
    end

    def to_json(*opts)
      {
        type: :def_endless,
        name: name,
        paren: paren,
        stmt: statement,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_def: (
  #     (Backtick | Const | Ident | Kw | Op) name,
  #     (Params | Paren) params,
  #     untyped bodystmt
  #   ) -> Def | DefEndless
  def on_def(name, params, bodystmt)
    # Make sure to delete this token in case you're defining something like def
    # class which would lead to this being a kw and causing all kinds of trouble
    tokens.delete(name)

    # Find the beginning of the method definition, which works for single-line
    # and normal method definitions.
    beginning = find_token(Kw, 'def')

    # If we don't have a bodystmt node, then we have a single-line method
    unless bodystmt.is_a?(BodyStmt)
      node =
        DefEndless.new(
          name: name,
          paren: params,
          statement: bodystmt,
          location: beginning.location.to(bodystmt.location)
        )

      return node
    end

    # If there aren't any params then we need to correct the params node
    # location information
    if params.is_a?(Params) && params.empty?
      end_char = name.location.end_char
      location =
        Location.new(
          start_line: params.location.start_line,
          start_char: end_char,
          end_line: params.location.end_line,
          end_char: end_char
        )

      params = Params.new(location: location)
    end

    ending = find_token(Kw, 'end')
    bodystmt.bind(
      find_next_statement_start(params.location.end_char),
      ending.location.start_char
    )

    Def.new(
      name: name,
      params: params,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # Defined represents the use of the +defined?+ operator. It can be used with
  # and without parentheses.
  #
  #     defined?(variable)
  #
  class Defined
    # [untyped] the value being sent to the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('defined')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :defined, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_defined: (untyped value) -> Defined
  def on_defined(value)
    beginning = find_token(Kw, 'defined?')
    ending = value

    range = beginning.location.end_char...value.location.start_char
    if source[range].include?('(')
      find_token(LParen)
      ending = find_token(RParen)
    end

    Defined.new(value: value, location: beginning.location.to(ending.location))
  end

  # Defs represents defining a singleton method on an object.
  #
  #     def object.method(param) result end
  #
  class Defs
    # [untyped] the target where the method is being defined
    attr_reader :target

    # [Op | Period] the operator being used to declare the method
    attr_reader :operator

    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [Params | Paren] the parameter declaration for the method
    attr_reader :params

    # [BodyStmt] the expressions to be executed by the method
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(target:, operator:, name:, params:, bodystmt:, location:)
      @target = target
      @operator = operator
      @name = name
      @params = params
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('defs')

        q.breakable
        q.pp(target)

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(name)

        q.breakable
        q.pp(params)

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :defs,
        target: target,
        op: operator,
        name: name,
        params: params,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_defs: (
  #     untyped target,
  #     (Op | Period) operator,
  #     (Backtick | Const | Ident | Kw | Op) name,
  #     (Params | Paren) params,
  #     BodyStmt bodystmt
  #   ) -> Defs
  def on_defs(target, operator, name, params, bodystmt)
    # Make sure to delete this token in case you're defining something
    # like def class which would lead to this being a kw and causing all kinds
    # of trouble
    tokens.delete(name)

    # If there aren't any params then we need to correct the params node
    # location information
    if params.is_a?(Params) && params.empty?
      end_char = name.location.end_char
      location =
        Location.new(
          start_line: params.location.start_line,
          start_char: end_char,
          end_line: params.location.end_line,
          end_char: end_char
        )

      params = Params.new(location: location)
    end

    beginning = find_token(Kw, 'def')
    ending = find_token(Kw, 'end')

    bodystmt.bind(
      find_next_statement_start(params.location.end_char),
      ending.location.start_char
    )

    Defs.new(
      target: target,
      operator: operator,
      name: name,
      params: params,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # DoBlock represents passing a block to a method call using the +do+ and +end+
  # keywords.
  #
  #     method do |value|
  #     end
  #
  class DoBlock
    # [Kw] the do keyword that opens this block
    attr_reader :keyword

    # [nil | BlockVar] the optional variable declaration within this block
    attr_reader :block_var

    # [BodyStmt] the expressions to be executed within this block
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(keyword:, block_var:, bodystmt:, location:)
      @keyword = keyword
      @block_var = block_var
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('do_block')

        if block_var
          q.breakable
          q.pp(block_var)
        end

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :do_block,
        keyword: keyword,
        block_var: block_var,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_do_block: (BlockVar block_var, BodyStmt bodystmt) -> DoBlock
  def on_do_block(block_var, bodystmt)
    beginning = find_token(Kw, 'do')
    ending = find_token(Kw, 'end')

    bodystmt.bind(
      find_next_statement_start((block_var || beginning).location.end_char),
      ending.location.start_char
    )

    DoBlock.new(
      keyword: beginning,
      block_var: block_var,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # Dot2 represents using the .. operator between two expressions. Usually this
  # is to create a range object.
  #
  #     1..2
  #
  # Sometimes this operator is used to create a flip-flop.
  #
  #     if value == 5 .. value == 10
  #     end
  #
  # One of the sides of the expression may be nil, but not both.
  class Dot2
    # [nil | untyped] the left side of the expression
    attr_reader :left

    # [nil | untyped] the right side of the expression
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('dot2')

        if left
          q.breakable
          q.pp(left)
        end

        if right
          q.breakable
          q.pp(right)
        end
      end
    end

    def to_json(*opts)
      { type: :dot2, left: left, right: right, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_dot2: ((nil | untyped) left, (nil | untyped) right) -> Dot2
  def on_dot2(left, right)
    operator = find_token(Op, '..')

    beginning = left || operator
    ending = right || operator

    Dot2.new(
      left: left,
      right: right,
      location: beginning.location.to(ending.location)
    )
  end

  # Dot3 represents using the ... operator between two expressions. Usually this
  # is to create a range object. It's effectively the same event as the Dot2
  # node but with this operator you're asking Ruby to omit the final value.
  #
  #     1...2
  #
  # Like Dot2 it can also be used to create a flip-flop.
  #
  #     if value == 5 ... value == 10
  #     end
  #
  # One of the sides of the expression may be nil, but not both.
  class Dot3
    # [nil | untyped] the left side of the expression
    attr_reader :left

    # [nil | untyped] the right side of the expression
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('dot3')

        if left
          q.breakable
          q.pp(left)
        end

        if right
          q.breakable
          q.pp(right)
        end
      end
    end

    def to_json(*opts)
      { type: :dot3, left: left, right: right, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_dot3: ((nil | untyped) left, (nil | untyped) right) -> Dot3
  def on_dot3(left, right)
    operator = find_token(Op, '...')

    beginning = left || operator
    ending = right || operator

    Dot3.new(
      left: left,
      right: right,
      location: beginning.location.to(ending.location)
    )
  end

  # DynaSymbol represents a symbol literal that uses quotes to dynamically
  # define its value.
  #
  #     :"#{variable}"
  #
  # They can also be used as a special kind of dynamic hash key, as in:
  #
  #     { "#{key}": value }
  #
  class DynaSymbol
    # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
    # dynamic symbol
    attr_reader :parts

    # [String] the quote used to delimit the dynamic symbol
    attr_reader :quote

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, quote:, location:)
      @parts = parts
      @quote = quote
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('dyna_symbol')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :dyna_symbol, parts: parts, quote: quote, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_dyna_symbol: (StringContent string_content) -> DynaSymbol
  def on_dyna_symbol(string_content)
    if find_token(SymBeg, consume: false)
      # A normal dynamic symbol
      symbeg = find_token(SymBeg)
      tstring_end = find_token(TStringEnd)

      DynaSymbol.new(
        quote: symbeg.value,
        parts: string_content.parts,
        location: symbeg.location.to(tstring_end.location)
      )
    else
      # A dynamic symbol as a hash key
      tstring_beg = find_token(TStringBeg)
      label_end = find_token(LabelEnd)

      DynaSymbol.new(
        parts: string_content.parts,
        quote: label_end.value[0],
        location: tstring_beg.location.to(label_end.location)
      )
    end
  end

  # Else represents the end of an +if+, +unless+, or +case+ chain.
  #
  #     if variable
  #     else
  #     end
  #
  class Else
    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(statements:, location:)
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('else')

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      { type: :else, stmts: statements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_else: (Statements statements) -> Else
  def on_else(statements)
    beginning = find_token(Kw, 'else')

    # else can either end with an end keyword (in which case we'll want to
    # consume that event) or it can end with an ensure keyword (in which case
    # we'll leave that to the ensure to handle).
    index =
      tokens.rindex do |token|
        token.is_a?(Kw) && %w[end ensure].include?(token.value)
      end

    node = tokens[index]
    ending = node.value == 'end' ? tokens.delete_at(index) : node

    statements.bind(beginning.location.end_char, ending.location.start_char)

    Else.new(
      statements: statements,
      location: beginning.location.to(ending.location)
    )
  end

  # Elsif represents another clause in an +if+ or +unless+ chain.
  #
  #     if variable
  #     elsif other_variable
  #     end
  #
  class Elsif
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Elsif | Else] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('elsif')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :elsif,
        pred: predicate,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_elsif: (
  #     untyped predicate,
  #     Statements statements,
  #     (nil | Elsif | Else) consequent
  #   ) -> Elsif
  def on_elsif(predicate, statements, consequent)
    beginning = find_token(Kw, 'elsif')
    ending = consequent || find_token(Kw, 'end')

    statements.bind(predicate.location.end_char, ending.location.start_char)

    Elsif.new(
      predicate: predicate,
      statements: statements,
      consequent: consequent,
      location: beginning.location.to(ending.location)
    )
  end

  # EmbDoc represents a multi-line comment.
  #
  #     =begin
  #     first line
  #     second line
  #     =end
  #
  class EmbDoc
    # [String] the contents of the comment
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def inline?
      false
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('embdoc')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :embdoc, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_embdoc: (String value) -> EmbDoc
  def on_embdoc(value)
    @embdoc.value << value
    @embdoc
  end

  # :call-seq:
  #   on_embdoc_beg: (String value) -> EmbDoc
  def on_embdoc_beg(value)
    @embdoc =
      EmbDoc.new(
        value: value,
        location: Location.fixed(line: lineno, char: char_pos)
      )
  end

  # :call-seq:
  #   on_embdoc_end: (String value) -> EmbDoc
  def on_embdoc_end(value)
    location = @embdoc.location
    embdoc =
      EmbDoc.new(
        value: @embdoc.value << value.chomp,
        location:
          Location.new(
            start_line: location.start_line,
            start_char: location.start_char,
            end_line: lineno,
            end_char: char_pos + value.length - 1
          )
      )

    @comments << embdoc
    @embdoc = nil

    embdoc
  end

  # EmbExprBeg represents the beginning token for using interpolation inside of
  # a parent node that accepts string content (like a string or regular
  # expression).
  #
  #     "Hello, #{person}!"
  #
  class EmbExprBeg
    # [String] the #{ used in the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_embexpr_beg: (String value) -> EmbExprBeg
  def on_embexpr_beg(value)
    node =
      EmbExprBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # EmbExprEnd represents the ending token for using interpolation inside of a
  # parent node that accepts string content (like a string or regular
  # expression).
  #
  #     "Hello, #{person}!"
  #
  class EmbExprEnd
    # [String] the } used in the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_embexpr_end: (String value) -> EmbExprEnd
  def on_embexpr_end(value)
    node =
      EmbExprEnd.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # EmbVar represents the use of shorthand interpolation for an instance, class,
  # or global variable into a parent node that accepts string content (like a
  # string or regular expression).
  #
  #     "#@variable"
  #
  # In the example above, an EmbVar node represents the # because it forces
  # @variable to be interpolated.
  class EmbVar
    # [String] the # used in the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_embvar: (String value) -> EmbVar
  def on_embvar(value)
    node =
      EmbVar.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Ensure represents the use of the +ensure+ keyword and its subsequent
  # statements.
  #
  #     begin
  #     ensure
  #     end
  #
  class Ensure
    # [Kw] the ensure keyword that began this node
    attr_reader :keyword

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(keyword:, statements:, location:)
      @keyword = keyword
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('ensure')

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :ensure,
        keyword: keyword,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_ensure: (Statements statements) -> Ensure
  def on_ensure(statements)
    keyword = find_token(Kw, 'ensure')

    # We don't want to consume the :@kw event, because that would break
    # def..ensure..end chains.
    ending = find_token(Kw, 'end', consume: false)
    statements.bind(
      find_next_statement_start(keyword.location.end_char),
      ending.location.start_char
    )

    Ensure.new(
      keyword: keyword,
      statements: statements,
      location: keyword.location.to(ending.location)
    )
  end

  # ExcessedComma represents a trailing comma in a list of block parameters. It
  # changes the block parameters such that they will destructure.
  #
  #     [[1, 2, 3], [2, 3, 4]].each do |first, second,|
  #     end
  #
  # In the above example, an ExcessedComma node would appear in the third
  # position of the Params node that is used to declare that block. The third
  # position typically represents a rest-type parameter, but in this case is
  # used to indicate that a trailing comma was used.
  class ExcessedComma
    # [String] the comma
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('excessed_comma')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :excessed_comma, value: value, loc: location }.to_json(*opts)
    end
  end

  # The handler for this event accepts no parameters (though in previous
  # versions of Ruby it accepted a string literal with a value of ",").
  #
  # :call-seq:
  #   on_excessed_comma: () -> ExcessedComma
  def on_excessed_comma(*)
    comma = find_token(Comma)

    ExcessedComma.new(value: comma.value, location: comma.location)
  end

  # FCall represents the piece of a method call that comes before any arguments
  # (i.e., just the name of the method). It is used in places where the parser
  # is sure that it is a method call and not potentially a local variable.
  #
  #     method(argument)
  #
  # In the above example, it's referring to the +method+ segment.
  class FCall
    # [Const | Ident] the name of the method
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('fcall')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :fcall, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_fcall: ((Const | Ident) value) -> FCall
  def on_fcall(value)
    FCall.new(value: value, location: value.location)
  end

  # Field is always the child of an assignment. It represents assigning to a
  # “field” on an object.
  #
  #     object.variable = value
  #
  class Field
    # [untyped] the parent object that owns the field being assigned
    attr_reader :parent

    # [:"::" | Op | Period] the operator being used for the assignment
    attr_reader :operator

    # [Const | Ident] the name of the field being assigned
    attr_reader :name

    # [Location] the location of this node
    attr_reader :location

    def initialize(parent:, operator:, name:, location:)
      @parent = parent
      @operator = operator
      @name = name
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('field')

        q.breakable
        q.pp(parent)

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(name)
      end
    end

    def to_json(*opts)
      {
        type: :field,
        parent: parent,
        op: operator,
        name: name,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_field: (
  #     untyped parent,
  #     (:"::" | Op | Period) operator
  #     (Const | Ident) name
  #   ) -> Field
  def on_field(parent, operator, name)
    Field.new(
      parent: parent,
      operator: operator,
      name: name,
      location: parent.location.to(name.location)
    )
  end

  # FloatLiteral represents a floating point number literal.
  #
  #     1.0
  #
  class FloatLiteral
    # [String] the value of the floating point number literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('float')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :float, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_float: (String value) -> FloatLiteral
  def on_float(value)
    node =
      FloatLiteral.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # FndPtn represents matching against a pattern where you find a pattern in an
  # array using the Ruby 3.0+ pattern matching syntax.
  #
  #     case value
  #     in [*, 7, *]
  #     end
  #
  class FndPtn
    # [nil | untyped] the optional constant wrapper
    attr_reader :constant

    # [VarField] the splat on the left-hand side
    attr_reader :left

    # [Array[ untyped ]] the list of positional expressions in the pattern that
    # are being matched
    attr_reader :values

    # [VarField] the splat on the right-hand side
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, left:, values:, right:, location:)
      @constant = constant
      @left = left
      @values = values
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('fndptn')

        if constant
          q.breakable
          q.pp(constant)
        end

        q.breakable
        q.pp(left)

        q.breakable
        q.group(2, '(', ')') { q.seplist(values) { |value| q.pp(value) } }

        q.breakable
        q.pp(right)
      end
    end

    def to_json(*opts)
      {
        type: :fndptn,
        constant: constant,
        left: left,
        values: values,
        right: right,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_fndptn: (
  #     (nil | untyped) constant,
  #     VarField left,
  #     Array[untyped] values,
  #     VarField right
  #   ) -> FndPtn
  def on_fndptn(constant, left, values, right)
    beginning = constant || find_token(LBracket)
    ending = find_token(RBracket)

    FndPtn.new(
      constant: constant,
      left: left,
      values: values,
      right: right,
      location: beginning.location.to(ending.location)
    )
  end

  # For represents using a +for+ loop.
  #
  #     for value in list do
  #     end
  #
  class For
    # [MLHS | MLHSAddStar | VarField] the variable declaration being used to
    # pull values out of the object being enumerated
    attr_reader :index

    # [untyped] the object being enumerated in the loop
    attr_reader :collection

    # [Statements] the statements to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(index:, collection:, statements:, location:)
      @index = index
      @collection = collection
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('for')

        q.breakable
        q.pp(index)

        q.breakable
        q.pp(collection)

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :for,
        index: index,
        collection: collection,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_for: (
  #     (MLHS | MLHSAddStar | VarField) value,
  #     untyped collection,
  #     Statements statements
  #   ) -> For
  def on_for(index, collection, statements)
    beginning = find_token(Kw, 'for')
    ending = find_token(Kw, 'end')

    # Consume the do keyword if it exists so that it doesn't get confused for
    # some other block
    keyword = find_token(Kw, 'do', consume: false)
    if keyword && keyword.location.start_char > collection.location.end_char &&
         keyword.location.end_char < ending.location.start_char
      tokens.delete(keyword)
    end

    statements.bind(
      (keyword || collection).location.end_char,
      ending.location.start_char
    )

    For.new(
      index: index,
      collection: collection,
      statements: statements,
      location: beginning.location.to(ending.location)
    )
  end

  # GVar represents a global variable literal.
  #
  #     $variable
  #
  class GVar
    # [String] the name of the global variable
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('gvar')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :gvar, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_gvar: (String value) -> GVar
  def on_gvar(value)
    node =
      GVar.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # HashLiteral represents a hash literal.
  #
  #     { key => value }
  #
  class HashLiteral
    # [nil | AssocListFromArgs] the contents of the hash
    attr_reader :contents

    # [Location] the location of this node
    attr_reader :location

    def initialize(contents:, location:)
      @contents = contents
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('hash')

        q.breakable
        q.pp(contents)
      end
    end

    def to_json(*opts)
      { type: :hash, cnts: contents, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_hash: ((nil | AssocListFromArgs) contents) -> HashLiteral
  def on_hash(contents)
    lbrace = find_token(LBrace)
    rbrace = find_token(RBrace)

    if contents
      # Here we're going to expand out the location information for the contents
      # node so that it can grab up any remaining comments inside the hash.
      location =
        Location.new(
          start_line: contents.location.start_line,
          start_char: lbrace.location.end_char,
          end_line: contents.location.end_line,
          end_char: rbrace.location.start_char
        )

      contents = contents.class.new(assocs: contents.assocs, location: location)
    end

    HashLiteral.new(
      contents: contents,
      location: lbrace.location.to(rbrace.location)
    )
  end

  # Heredoc represents a heredoc string literal.
  #
  #     <<~DOC
  #       contents
  #     DOC
  #
  class Heredoc
    # [HeredocBeg] the opening of the heredoc
    attr_reader :beginning

    # [String] the ending of the heredoc
    attr_reader :ending

    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # heredoc string literal
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(beginning:, ending: nil, parts: [], location:)
      @beginning = beginning
      @ending = ending
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('heredoc')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      {
        type: :heredoc,
        beging: beginning,
        ending: ending,
        parts: parts,
        loc: location
      }.to_json(*opts)
    end
  end

  # HeredocBeg represents the beginning declaration of a heredoc.
  #
  #     <<~DOC
  #       contents
  #     DOC
  #
  # In the example above the HeredocBeg node represents <<~DOC.
  class HeredocBeg
    # [String] the opening declaration of the heredoc
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('heredoc_beg')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :heredoc_beg, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_heredoc_beg: (String value) -> HeredocBeg
  def on_heredoc_beg(value)
    location =
      Location.token(line: lineno, char: char_pos, size: value.size + 1)

    # Here we're going to artificially create an extra node type so that if
    # there are comments after the declaration of a heredoc, they get printed.
    beginning = HeredocBeg.new(value: value, location: location)
    @heredocs << Heredoc.new(beginning: beginning, location: location)

    beginning
  end

  # :call-seq:
  #   on_heredoc_dedent: (StringContent string, Integer width) -> Heredoc
  def on_heredoc_dedent(string, width)
    heredoc = @heredocs[-1]

    @heredocs[-1] =
      Heredoc.new(
        beginning: heredoc.beginning,
        ending: heredoc.ending,
        parts: string.parts,
        location: heredoc.location
      )
  end

  # :call-seq:
  #   on_heredoc_end: (String value) -> Heredoc
  def on_heredoc_end(value)
    heredoc = @heredocs[-1]

    @heredocs[-1] =
      Heredoc.new(
        beginning: heredoc.beginning,
        ending: value.chomp,
        parts: heredoc.parts,
        location:
          Location.new(
            start_line: heredoc.location.start_line,
            start_char: heredoc.location.start_char,
            end_line: lineno,
            end_char: char_pos
          )
      )
  end

  # HshPtn represents matching against a hash pattern using the Ruby 2.7+
  # pattern matching syntax.
  #
  #     case value
  #     in { key: }
  #     end
  #
  class HshPtn
    # [nil | untyped] the optional constant wrapper
    attr_reader :constant

    # [Array[ [Label, untyped] ]] the set of tuples representing the keywords
    # that should be matched against in the pattern
    attr_reader :keywords

    # [nil | VarField] an optional parameter to gather up all remaining keywords
    attr_reader :keyword_rest

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, keywords:, keyword_rest:, location:)
      @constant = constant
      @keywords = keywords
      @keyword_rest = keyword_rest
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('hshptn')

        if constant
          q.breakable
          q.pp(constant)
        end

        if keywords.any?
          q.breakable
          q.group(2, '(', ')') do
            q.seplist(keywords) { |keyword| q.pp(keyword) }
          end
        end

        if keyword_rest
          q.breakable
          q.pp(keyword_rest)
        end
      end
    end

    def to_json(*opts)
      {
        type: :hshptn,
        constant: constant,
        keywords: keywords,
        kwrest: keyword_rest,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_hshptn: (
  #     (nil | untyped) constant,
  #     Array[[Label, untyped]] keywords,
  #     (nil | VarField) keyword_rest
  #   ) -> HshPtn
  def on_hshptn(constant, keywords, keyword_rest)
    parts = [constant, keywords, keyword_rest].flatten(2).compact

    HshPtn.new(
      constant: constant,
      keywords: keywords,
      keyword_rest: keyword_rest,
      location: parts[0].location.to(parts[-1].location)
    )
  end

  # Ident represents an identifier anywhere in code. It can represent a very
  # large number of things, depending on where it is in the syntax tree.
  #
  #     value
  #
  class Ident
    # [String] the value of the identifier
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('ident')
        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      {
        type: :ident,
        value: value.force_encoding('UTF-8'),
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_ident: (String value) -> Ident
  def on_ident(value)
    node =
      Ident.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # If represents the first clause in an +if+ chain.
  #
  #     if predicate
  #     end
  #
  class If
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil, Elsif, Else] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('if')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :if,
        pred: predicate,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_if: (
  #     untyped predicate,
  #     Statements statements,
  #     (nil | Elsif | Else) consequent
  #   ) -> If
  def on_if(predicate, statements, consequent)
    beginning = find_token(Kw, 'if')
    ending = consequent || find_token(Kw, 'end')

    statements.bind(predicate.location.end_char, ending.location.start_char)

    If.new(
      predicate: predicate,
      statements: statements,
      consequent: consequent,
      location: beginning.location.to(ending.location)
    )
  end

  # IfOp represents a ternary clause.
  #
  #     predicate ? truthy : falsy
  #
  class IfOp
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [untyped] the expression to be executed if the predicate is truthy
    attr_reader :truthy

    # [untyped] the expression to be executed if the predicate is falsy
    attr_reader :falsy

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, truthy:, falsy:, location:)
      @predicate = predicate
      @truthy = truthy
      @falsy = falsy
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('ifop')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(truthy)

        q.breakable
        q.pp(falsy)
      end
    end

    def to_json(*opts)
      {
        type: :ifop,
        pred: predicate,
        tthy: truthy,
        flsy: falsy,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_ifop: (untyped predicate, untyped truthy, untyped falsy) -> IfOp
  def on_ifop(predicate, truthy, falsy)
    IfOp.new(
      predicate: predicate,
      truthy: truthy,
      falsy: falsy,
      location: predicate.location.to(falsy.location)
    )
  end

  # IfMod represents the modifier form of an +if+ statement.
  #
  #     expression if predicate
  #
  class IfMod
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, predicate:, location:)
      @statement = statement
      @predicate = predicate
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('if_mod')

        q.breakable
        q.pp(statement)

        q.breakable
        q.pp(predicate)
      end
    end

    def to_json(*opts)
      {
        type: :if_mod,
        stmt: statement,
        pred: predicate,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_if_mod: (untyped predicate, untyped statement) -> IfMod
  def on_if_mod(predicate, statement)
    find_token(Kw, 'if')

    IfMod.new(
      statement: statement,
      predicate: predicate,
      location: statement.location.to(predicate.location)
    )
  end

  # def on_ignored_nl(value)
  #   value
  # end

  # def on_ignored_sp(value)
  #   value
  # end

  # Imaginary represents an imaginary number literal.
  #
  #     1i
  #
  class Imaginary
    # [String] the value of the imaginary number literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('imaginary')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :imaginary, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_imaginary: (String value) -> Imaginary
  def on_imaginary(value)
    node =
      Imaginary.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # In represents using the +in+ keyword within the Ruby 2.7+ pattern matching
  # syntax.
  #
  #     case value
  #     in pattern
  #     end
  #
  class In
    # [untyped] the pattern to check against
    attr_reader :pattern

    # [Statements] the expressions to execute if the pattern matched
    attr_reader :statements

    # [nil | In | Else] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(pattern:, statements:, consequent:, location:)
      @pattern = pattern
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('in')

        q.breakable
        q.pp(pattern)

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :in,
        pattern: pattern,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_in: (RAssign pattern, nil statements, nil consequent) -> RAssign
  #        | (
  #            untyped pattern,
  #            Statements statements,
  #            (nil | In | Else) consequent
  #          ) -> In
  def on_in(pattern, statements, consequent)
    # Here we have a rightward assignment
    return pattern unless statements

    beginning = find_token(Kw, 'in')
    ending = consequent || find_token(Kw, 'end')

    statements.bind(beginning.location.end_char, ending.location.start_char)

    In.new(
      pattern: pattern,
      statements: statements,
      consequent: consequent,
      location: beginning.location.to(ending.location)
    )
  end

  # Int represents an integer number literal.
  #
  #     1
  #
  class Int
    # [String] the value of the integer
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('int')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :int, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_int: (String value) -> Int
  def on_int(value)
    node =
      Int.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # IVar represents an instance variable literal.
  #
  #     @variable
  #
  class IVar
    # [String] the name of the instance variable
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('ivar')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :ivar, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_ivar: (String value) -> IVar
  def on_ivar(value)
    node =
      IVar.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Kw represents the use of a keyword. It can be almost anywhere in the syntax
  # tree, so you end up seeing it quite a lot.
  #
  #     if value
  #     end
  #
  # In the above example, there would be two Kw nodes: one for the if and one
  # for the end. Note that anything that matches the list of keywords in Ruby
  # will use a Kw, so if you use a keyword in a symbol literal for instance:
  #
  #     :if
  #
  # then the contents of the symbol node will contain a Kw node.
  class Kw
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('kw')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :kw, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_kw: (String value) -> Kw
  def on_kw(value)
    node =
      Kw.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # KwRestParam represents defining a parameter in a method definition that
  # accepts all remaining keyword parameters.
  #
  #     def method(**kwargs) end
  #
  class KwRestParam
    # [nil | Ident] the name of the parameter
    attr_reader :name

    # [Location] the location of this node
    attr_reader :location

    def initialize(name:, location:)
      @name = name
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('kwrest_param')

        q.breakable
        q.pp(name)
      end
    end

    def to_json(*opts)
      { type: :kwrest_param, name: name, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_kwrest_param: ((nil | Ident) name) -> KwRestParam
  def on_kwrest_param(name)
    location = find_token(Op, '**').location
    location = location.to(name.location) if name

    KwRestParam.new(name: name, location: location)
  end

  # Label represents the use of an identifier to associate with an object. You
  # can find it in a hash key, as in:
  #
  #     { key: value }
  #
  # In this case "key:" would be the body of the label. You can also find it in
  # pattern matching, as in:
  #
  #     case value
  #     in key:
  #     end
  #
  # In this case "key:" would be the body of the label.
  class Label
    # [String] the value of the label
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('label')

        q.breakable
        q.text(':')
        q.text(value[0...-1])
      end
    end

    def to_json(*opts)
      { type: :label, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_label: (String value) -> Label
  def on_label(value)
    node =
      Label.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # LabelEnd represents the end of a dynamic symbol.
  #
  #     { "key": value }
  #
  # In the example above, LabelEnd represents the "\":" token at the end of the
  # hash key. This node is important for determining the type of quote being
  # used by the label.
  class LabelEnd
    # [String] the end of the label
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_label_end: (String value) -> LabelEnd
  def on_label_end(value)
    node =
      LabelEnd.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Lambda represents using a lambda literal (not the lambda method call).
  #
  #     ->(value) { value * 2 }
  #
  class Lambda
    # [Params | Paren] the parameter declaration for this lambda
    attr_reader :params

    # [BodyStmt | Statements] the expressions to be executed in this lambda
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(params:, statements:, location:)
      @params = params
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('lambda')

        q.breakable
        q.pp(params)

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :lambda,
        params: params,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_lambda: (
  #     (Params | Paren) params,
  #     (BodyStmt | Statements) statements
  #   ) -> Lambda
  def on_lambda(params, statements)
    beginning = find_token(TLambda)

    if token = find_token(TLamBeg, consume: false)
      opening = tokens.delete(token)
      closing = find_token(RBrace)
    else
      opening = find_token(Kw, 'do')
      closing = find_token(Kw, 'end')
    end

    statements.bind(opening.location.end_char, closing.location.start_char)

    Lambda.new(
      params: params,
      statements: statements,
      location: beginning.location.to(closing.location)
    )
  end

  # LBrace represents the use of a left brace, i.e., {.
  class LBrace
    # [String] the left brace
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('lbrace')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :lbrace, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_lbrace: (String value) -> LBrace
  def on_lbrace(value)
    node =
      LBrace.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # LBracket represents the use of a left bracket, i.e., [.
  class LBracket
    # [String] the left bracket
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_lbracket: (String value) -> LBracket
  def on_lbracket(value)
    node =
      LBracket.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # LParen represents the use of a left parenthesis, i.e., (.
  class LParen
    # [String] the left parenthesis
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('lparen')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :lparen, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_lparen: (String value) -> LParen
  def on_lparen(value)
    node =
      LParen.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # def on_magic_comment(key, value)
  #   [key, value]
  # end

  # MAssign is a parent node of any kind of multiple assignment. This includes
  # splitting out variables on the left like:
  #
  #     first, second, third = value
  #
  # as well as splitting out variables on the right, as in:
  #
  #     value = first, second, third
  #
  # Both sides support splats, as well as variables following them. There's also
  # destructuring behavior that you can achieve with the following:
  #
  #     first, = value
  #
  class MAssign
    # [Mlhs | MlhsAddPost | MlhsAddStar | MlhsParen] the target of the multiple
    # assignment
    attr_reader :target

    # [untyped] the value being assigned
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(target:, value:, location:)
      @target = target
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('massign')

        q.breakable
        q.pp(target)

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :massign, target: target, value: value, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_massign: (
  #     (Mlhs | MlhsAddPost | MlhsAddStar | MlhsParen) target,
  #     untyped value
  #   ) -> MAssign
  def on_massign(target, value)
    comma_range = target.location.end_char...value.location.start_char
    target.comma = true if source[comma_range].strip.start_with?(',')

    MAssign.new(
      target: target,
      value: value,
      location: target.location.to(value.location)
    )
  end

  # MethodAddArg represents a method call with arguments and parentheses.
  #
  #     method(argument)
  #
  # MethodAddArg can also represent with a method on an object, as in:
  #
  #     object.method(argument)
  #
  # Finally, MethodAddArg can represent calling a method with no receiver that
  # ends in a ?. In this case, the parser knows it's a method call and not a
  # local variable, so it uses a MethodAddArg node as opposed to a VCall node,
  # as in:
  #
  #     method?
  #
  class MethodAddArg
    # [Call | FCall] the method call
    attr_reader :call

    # [ArgParen | Args | ArgsAddBlock] the arguments to the method call
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(call:, arguments:, location:)
      @call = call
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('method_add_arg')

        q.breakable
        q.pp(call)

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      {
        type: :method_add_arg,
        call: call,
        args: arguments,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_method_add_arg: (
  #     (Call | FCall) call,
  #     (ArgParen | Args | ArgsAddBlock) arguments
  #   ) -> MethodAddArg
  def on_method_add_arg(call, arguments)
    location = call.location

    location = location.to(arguments.location) unless arguments.is_a?(Args)

    MethodAddArg.new(call: call, arguments: arguments, location: location)
  end

  # MethodAddBlock represents a method call with a block argument.
  #
  #     method {}
  #
  class MethodAddBlock
    # [Call | Command | CommandCall | FCall | MethodAddArg] the method call
    attr_reader :call

    # [BraceBlock | DoBlock] the block being sent with the method call
    attr_reader :block

    # [Location] the location of this node
    attr_reader :location

    def initialize(call:, block:, location:)
      @call = call
      @block = block
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('method_add_block')

        q.breakable
        q.pp(call)

        q.breakable
        q.pp(block)
      end
    end

    def to_json(*opts)
      {
        type: :method_add_block,
        call: call,
        block: block,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_method_add_block: (
  #     (Call | Command | CommandCall | FCall | MethodAddArg) call,
  #     (BraceBlock | DoBlock) block
  #   ) -> MethodAddBlock
  def on_method_add_block(call, block)
    MethodAddBlock.new(
      call: call,
      block: block,
      location: call.location.to(block.location)
    )
  end

  # MLHS represents a list of values being destructured on the left-hand side
  # of a multiple assignment.
  #
  #     first, second, third = value
  #
  class MLHS
    # Array[ARefField | Field | Ident | MlhsParen | VarField] the parts of
    # the left-hand side of a multiple assignment
    attr_reader :parts

    # [boolean] whether or not there is a trailing comma at the end of this
    # list, which impacts destructuring. It's an attr_accessor so that while
    # the syntax tree is being built it can be set by its parent node
    attr_accessor :comma

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, comma: false, location:)
      @parts = parts
      @comma = comma
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mlhs')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :mlhs, parts: parts, comma: comma, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_mlhs_add: (
  #     MLHS mlhs,
  #     (ARefField | Field | Ident | MlhsParen | VarField) part
  #   ) -> MLHS
  def on_mlhs_add(mlhs, part)
    if mlhs.parts.empty?
      MLHS.new(parts: [part], location: part.location)
    else
      MLHS.new(
        parts: mlhs.parts << part,
        location: mlhs.location.to(part.location)
      )
    end
  end

  # MLHSAddPost represents adding another set of variables onto a list of
  # assignments after a splat variable within a multiple assignment.
  #
  #     left, *middle, right = values
  #
  class MLHSAddPost
    # [MlhsAddStar] the value being starred
    attr_reader :star

    # [Mlhs] the values after the star
    attr_reader :mlhs

    # [Location] the location of this node
    attr_reader :location

    def initialize(star:, mlhs:, location:)
      @star = star
      @mlhs = mlhs
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mlhs_add_post')

        q.breakable
        q.pp(star)

        q.breakable
        q.pp(mlhs)
      end
    end

    def to_json(*opts)
      { type: :mlhs_add_post, star: star, mlhs: mlhs, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_mlhs_add_post: (MLHSAddStar star, MLHS mlhs) -> MLHSAddPost
  def on_mlhs_add_post(star, mlhs)
    MLHSAddPost.new(
      star: star,
      mlhs: mlhs,
      location: star.location.to(mlhs.location)
    )
  end

  # MLHSAddStar represents a splatted variable inside of a multiple assignment
  # on the left hand side.
  #
  #     first, *rest = values
  #
  class MLHSAddStar
    # [MLHS] the values before the starred expression
    attr_reader :mlhs

    # [nil | ARefField | Field | Ident | VarField] the expression being
    # splatted
    attr_reader :star

    # [Location] the location of this node
    attr_reader :location

    def initialize(mlhs:, star:, location:)
      @mlhs = mlhs
      @star = star
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mlhs_add_star')

        q.breakable
        q.pp(mlhs)

        q.breakable
        q.pp(star)
      end
    end

    def to_json(*opts)
      { type: :mlhs_add_star, mlhs: mlhs, star: star, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_mlhs_add_star: (
  #     MLHS mlhs,
  #     (nil | ARefField | Field | Ident | VarField) part
  #   ) -> MLHSAddStar
  def on_mlhs_add_star(mlhs, part)
    beginning = find_token(Op, '*')
    ending = part || beginning

    MLHSAddStar.new(
      mlhs: mlhs,
      star: part,
      location: beginning.location.to(ending.location)
    )
  end

  # :call-seq:
  #   on_mlhs_new: () -> MLHS
  def on_mlhs_new
    MLHS.new(parts: [], location: Location.fixed(line: lineno, char: char_pos))
  end

  # MLHSParen represents parentheses being used to destruct values in a multiple
  # assignment on the left hand side.
  #
  #     (left, right) = value
  #
  class MLHSParen
    # [Mlhs | MlhsAddPost | MlhsAddStar | MlhsParen] the contents inside of the
    # parentheses
    attr_reader :contents

    # [Location] the location of this node
    attr_reader :location

    def initialize(contents:, location:)
      @contents = contents
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mlhs_paren')

        q.breakable
        q.pp(contents)
      end
    end

    def to_json(*opts)
      { type: :mlhs_paren, cnts: contents, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_mlhs_paren: (
  #     (Mlhs | MlhsAddPost | MlhsAddStar | MlhsParen) contents
  #   ) -> MLHSParen
  def on_mlhs_paren(contents)
    lparen = find_token(LParen)
    rparen = find_token(RParen)

    comma_range = lparen.location.end_char...rparen.location.start_char
    contents.comma = true if source[comma_range].strip.end_with?(',')

    MLHSParen.new(
      contents: contents,
      location: lparen.location.to(rparen.location)
    )
  end

  # ModuleDeclaration represents defining a module using the +module+ keyword.
  #
  #     module Namespace
  #     end
  #
  class ModuleDeclaration
    # [ConstPathRef | ConstRef | TopConstRef] the name of the module
    attr_reader :constant

    # [BodyStmt] the expressions to be executed in the context of the module
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, bodystmt:, location:)
      @constant = constant
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('module')

        q.breakable
        q.pp(constant)

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :module,
        constant: constant,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_module: (
  #     (ConstPathRef | ConstRef | TopConstRef) constant,
  #     BodyStmt bodystmt
  #   ) -> ModuleDeclaration
  def on_module(constant, bodystmt)
    beginning = find_token(Kw, 'module')
    ending = find_token(Kw, 'end')

    bodystmt.bind(
      find_next_statement_start(constant.location.end_char),
      ending.location.start_char
    )

    ModuleDeclaration.new(
      constant: constant,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # MRHS represents the values that are being assigned on the right-hand side of
  # a multiple assignment.
  #
  #     values = first, second, third
  #
  class MRHS
    # Array[untyped] the parts that are being assigned
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mrhs')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :mrhs, parts: parts, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_mrhs_new: () -> MRHS
  def on_mrhs_new
    MRHS.new(parts: [], location: Location.fixed(line: lineno, char: char_pos))
  end

  # :call-seq:
  #   on_mrhs_add: (MRHS mrhs, untyped part) -> MRHS
  def on_mrhs_add(mrhs, part)
    if mrhs.is_a?(MRHSNewFromArgs)
      MRHS.new(
        parts: [*mrhs.arguments.parts, part],
        location: mrhs.location.to(part.location)
      )
    elsif mrhs.parts.empty?
      MRHS.new(parts: [part], location: mrhs.location)
    else
      MRHS.new(parts: mrhs.parts << part, loc: mrhs.location.to(part.location))
    end
  end

  # MRHSAddStar represents using the splat operator to expand out a value on the
  # right hand side of a multiple assignment.
  #
  #     values = first, *rest
  #
  class MRHSAddStar
    # [MRHS | MRHSNewFromArgs] the values before the splatted expression
    attr_reader :mrhs

    # [untyped] the splatted expression
    attr_reader :star

    # [Location] the location of this node
    attr_reader :location

    def initialize(mrhs:, star:, location:)
      @mrhs = mrhs
      @star = star
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mrhs_add_star')

        q.breakable
        q.pp(mrhs)

        q.breakable
        q.pp(star)
      end
    end

    def to_json(*opts)
      { type: :mrhs_add_star, mrhs: mrhs, star: star, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_mrhs_add_star: (
  #     (MRHS | MRHSNewFromArgs) mrhs,
  #     untyped star
  #   ) -> MRHSAddStar
  def on_mrhs_add_star(mrhs, star)
    beginning = find_token(Op, '*')
    ending = star || beginning

    MRHSAddStar.new(
      mrhs: mrhs,
      star: star,
      location: beginning.location.to(ending.location)
    )
  end

  # MRHSNewFromArgs represents the shorthand of a multiple assignment that
  # allows you to assign values using just commas as opposed to assigning from
  # an array.
  #
  #     values = first, second, third
  #
  class MRHSNewFromArgs
    # [Args] the arguments being used in the assignment
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('mrhs_new_from_args')

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :mrhs_new_from_args, args: arguments, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_mrhs_new_from_args: (Args arguments) -> MRHSNewFromArgs
  def on_mrhs_new_from_args(arguments)
    MRHSNewFromArgs.new(arguments: arguments, location: arguments.location)
  end

  # Next represents using the +next+ keyword.
  #
  #     next
  #
  # The +next+ keyword can also optionally be called with an argument:
  #
  #     next value
  #
  # +next+ can even be called with multiple arguments, but only if parentheses
  # are omitted, as in:
  #
  #     next first, second, third
  #
  # If a single value is being given, parentheses can be used, as in:
  #
  #     next(value)
  #
  class Next
    # [Args | ArgsAddBlock] the arguments passed to the next keyword
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('next')

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :next, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_next: ((Args | ArgsAddBlock) arguments) -> Next
  def on_next(arguments)
    keyword = find_token(Kw, 'next')

    location = keyword.location
    location = location.to(arguments.location) unless arguments.is_a?(Args)

    Next.new(arguments: arguments, location: location)
  end

  # def on_nl(value)
  #   value
  # end

  # def on_nokw_param(value)
  #   value
  # end

  # Op represents an operator literal in the source.
  #
  #     1 + 2
  #
  # In the example above, the Op node represents the + operator.
  class Op
    # [String] the operator
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('op')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :op, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_op: (String value) -> Op
  def on_op(value)
    node =
      Op.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # OpAssign represents assigning a value to a variable or constant using an
  # operator like += or ||=.
  #
  #     variable += value
  #
  class OpAssign
    # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
    # to assign the result of the expression to
    attr_reader :target

    # [Op] the operator being used for the assignment
    attr_reader :operator

    # [untyped] the expression to be assigned
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(target:, operator:, value:, location:)
      @target = target
      @operator = operator
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('opassign')

        q.breakable
        q.pp(target)

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      {
        type: :opassign,
        target: target,
        op: operator,
        value: value,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_opassign: (
  #     (ARefField | ConstPathField | Field | TopConstField | VarField) target,
  #     Op operator,
  #     untyped value
  #   ) -> OpAssign
  def on_opassign(target, operator, value)
    OpAssign.new(
      target: target,
      operator: operator,
      value: value,
      location: target.location.to(value.location)
    )
  end

  # def on_operator_ambiguous(value)
  #   value
  # end

  # Params represents defining parameters on a method or lambda.
  #
  #     def method(param) end
  #
  class Params
    # [Array[ Ident ]] any required parameters
    attr_reader :requireds

    # [Array[ [ Ident, untyped ] ]] any optional parameters and their default
    # values
    attr_reader :optionals

    # [nil | ArgsForward | ExcessedComma | RestParam] the optional rest
    # parameter
    attr_reader :rest

    # [Array[ Ident ]] any positional parameters that exist after a rest
    # parameter
    attr_reader :posts

    # [Array[ [ Ident, nil | untyped ] ]] any keyword parameters and their
    # optional default values
    attr_reader :keywords

    # [nil | :nil | KwRestParam] the optional keyword rest parameter
    attr_reader :keyword_rest

    # [nil | BlockArg] the optional block parameter
    attr_reader :block

    # [Location] the location of this node
    attr_reader :location

    def initialize(
      requireds: [],
      optionals: [],
      rest: nil,
      posts: [],
      keywords: [],
      keyword_rest: nil,
      block: nil,
      location:
    )
      @requireds = requireds
      @optionals = optionals
      @rest = rest
      @posts = posts
      @keywords = keywords
      @keyword_rest = keyword_rest
      @block = block
      @location = location
    end

    # Params nodes are the most complicated in the tree. Occasionally you want
    # to know if they are "empty", which means not having any parameters
    # declared. This logic accesses every kind of parameter and determines if
    # it's missing.
    def empty?
      requireds.empty? && optionals.empty? && !rest && posts.empty? &&
        keywords.empty? && !keyword_rest && !block
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('params')

        if requireds.any?
          q.breakable
          q.group(2, '(', ')') { q.seplist(requireds) { |name| q.pp(name) } }
        end

        if optionals.any?
          q.breakable
          q.group(2, '(', ')') do
            q.seplist(optionals) do |(name, default)|
              q.pp(name)
              q.text('=')
              q.group(2) do
                q.breakable('')
                q.pp(default)
              end
            end
          end
        end

        if rest
          q.breakable
          q.pp(rest)
        end

        if posts.any?
          q.breakable
          q.group(2, '(', ')') { q.seplist(posts) { |value| q.pp(value) } }
        end

        if keywords.any?
          q.breakable
          q.group(2, '(', ')') do
            q.seplist(keywords) do |(name, default)|
              q.pp(name)

              if default
                q.text('=')
                q.group(2) do
                  q.breakable('')
                  q.pp(default)
                end
              end
            end
          end
        end

        if keyword_rest
          q.breakable
          q.pp(keyword_rest)
        end

        if block
          q.breakable
          q.pp(block)
        end
      end
    end

    def to_json(*opts)
      {
        type: :params,
        reqs: requireds,
        opts: optionals,
        rest: rest,
        posts: posts,
        keywords: keywords,
        kwrest: keyword_rest,
        block: block,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_params: (
  #     (nil | Array[Ident]) requireds,
  #     (nil | Array[[Ident, untyped]]) optionals,
  #     (nil | ArgsForward | ExcessedComma | RestParam) rest,
  #     (nil | Array[Ident]) posts,
  #     (nil | Array[[Ident, nil | untyped]]) keywords,
  #     (nil | :nil | KwRestParam) keyword_rest,
  #     (nil | BlockArg) block
  #   ) -> Params
  def on_params(
    requireds,
    optionals,
    rest,
    posts,
    keywords,
    keyword_rest,
    block
  )
    parts = [
      *requireds,
      *optionals&.flatten(1),
      rest,
      *posts,
      *keywords&.flat_map { |(key, value)| [key, value || nil] },
      (keyword_rest if keyword_rest != :nil),
      block
    ].compact

    location =
      if parts.any?
        parts[0].location.to(parts[-1].location)
      else
        Location.fixed(line: lineno, char: char_pos)
      end

    Params.new(
      requireds: requireds || [],
      optionals: optionals || [],
      rest: rest,
      posts: posts || [],
      keywords: keywords || [],
      keyword_rest: keyword_rest,
      block: block,
      location: location
    )
  end

  # Paren represents using balanced parentheses in a couple places in a Ruby
  # program. In general parentheses can be used anywhere a Ruby expression can
  # be used.
  #
  #     (1 + 2)
  #
  class Paren
    # [LParen] the left parenthesis that opened this statement
    attr_reader :lparen

    # [untyped] the expression inside the parentheses
    attr_reader :contents

    # [Location] the location of this node
    attr_reader :location

    def initialize(lparen:, contents:, location:)
      @lparen = lparen
      @contents = contents
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('paren')

        q.breakable
        q.pp(contents)
      end
    end

    def to_json(*opts)
      { type: :paren, lparen: lparen, cnts: contents, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_paren: (untyped contents) -> Paren
  def on_paren(contents)
    lparen = find_token(LParen)
    rparen = find_token(RParen)

    if contents && contents.is_a?(Params)
      location = contents.location
      location =
        Location.new(
          start_line: location.start_line,
          start_char: find_next_statement_start(lparen.location.end_char),
          end_line: location.end_line,
          end_char: rparen.location.start_char
        )

      contents =
        Params.new(
          requireds: contents.requireds,
          optionals: contents.optionals,
          rest: contents.rest,
          posts: contents.posts,
          keywords: contents.keywords,
          keyword_rest: contents.keyword_rest,
          block: contents.block,
          location: location
        )
    end

    Paren.new(
      lparen: lparen,
      contents: contents,
      location: lparen.location.to(rparen.location)
    )
  end

  # If we encounter a parse error, just immediately bail out so that our runner
  # can catch it.
  def on_parse_error(error, *)
    raise ParseError.new(error, lineno, column)
  end
  alias on_alias_error on_parse_error
  alias on_assign_error on_parse_error
  alias on_class_name_error on_parse_error
  alias on_param_error on_parse_error

  # Period represents the use of the +.+ operator. It is usually found in method
  # calls.
  class Period
    # [String] the period
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('period')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :period, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_period: (String value) -> Period
  def on_period(value)
    Period.new(
      value: value,
      location: Location.token(line: lineno, char: char_pos, size: value.size)
    )
  end

  # Program represents the overall syntax tree.
  class Program
    # [Statements] the top-level expressions of the program
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments inside the program
    attr_reader :comments

    # [Location] the location of this node
    attr_reader :location

    def initialize(statements:, comments:, location:)
      @statements = statements
      @comments = comments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('program')

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :program,
        stmts: statements,
        comments: comments,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_program: (Statements statements) -> Program
  def on_program(statements)
    location =
      Location.new(
        start_line: 1,
        start_char: 0,
        end_line: lines.length,
        end_char: source.length
      )

    statements.body << @__end__ if @__end__
    statements.bind(0, source.length)

    Program.new(statements: statements, comments: @comments, location: location)
  end

  # QSymbols represents a symbol literal array without interpolation.
  #
  #     %i[one two three]
  #
  class QSymbols
    # [Array[ TStringContent ]] the elements of the array
    attr_reader :elements

    # [Location] the location of this node
    attr_reader :location

    def initialize(elements:, location:)
      @elements = elements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('qsymbols')

        q.breakable
        q.group(2, '(', ')') { q.seplist(elements) { |element| q.pp(element) } }
      end
    end

    def to_json(*opts)
      { type: :qsymbols, elems: elements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_qsymbols_add: (QSymbols qsymbols, TStringContent element) -> QSymbols
  def on_qsymbols_add(qsymbols, element)
    QSymbols.new(
      elements: qsymbols.elements << element,
      location: qsymbols.location.to(element.location)
    )
  end

  # QSymbolsBeg represents the beginning of a symbol literal array.
  #
  #     %i[one two three]
  #
  # In the snippet above, QSymbolsBeg represents the "%i[" token. Note that
  # these kinds of arrays can start with a lot of different delimiter types
  # (e.g., %i| or %i<).
  class QSymbolsBeg
    # [String] the beginning of the array literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_qsymbols_beg: (String value) -> QSymbolsBeg
  def on_qsymbols_beg(value)
    node =
      QSymbolsBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # :call-seq:
  #   on_qsymbols_new: () -> QSymbols
  def on_qsymbols_new
    qsymbols_beg = find_token(QSymbolsBeg)

    QSymbols.new(elements: [], location: qsymbols_beg.location)
  end

  # QWords represents a string literal array without interpolation.
  #
  #     %w[one two three]
  #
  class QWords
    # [Array[ TStringContent ]] the elements of the array
    attr_reader :elements

    # [Location] the location of this node
    attr_reader :location

    def initialize(elements:, location:)
      @elements = elements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('qwords')

        q.breakable
        q.group(2, '(', ')') { q.seplist(elements) { |element| q.pp(element) } }
      end
    end

    def to_json(*opts)
      { type: :qwords, elems: elements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_qwords_add: (QWords qwords, TStringContent element) -> QWords
  def on_qwords_add(qwords, element)
    QWords.new(
      elements: qwords.elements << element,
      location: qwords.location.to(element.location)
    )
  end

  # QWordsBeg represents the beginning of a string literal array.
  #
  #     %w[one two three]
  #
  # In the snippet above, QWordsBeg represents the "%w[" token. Note that these
  # kinds of arrays can start with a lot of different delimiter types (e.g.,
  # %w| or %w<).
  class QWordsBeg
    # [String] the beginning of the array literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_qwords_beg: (String value) -> QWordsBeg
  def on_qwords_beg(value)
    node =
      QWordsBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # :call-seq:
  #   on_qwords_new: () -> QWords
  def on_qwords_new
    qwords_beg = find_token(QWordsBeg)

    QWords.new(elements: [], location: qwords_beg.location)
  end

  # RationalLiteral represents the use of a rational number literal.
  #
  #     1r
  #
  class RationalLiteral
    # [String] the rational number literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rational')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :rational, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_rational: (String value) -> RationalLiteral
  def on_rational(value)
    node =
      RationalLiteral.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # RBrace represents the use of a right brace, i.e., +++.
  class RBrace
    # [String] the right brace
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_rbrace: (String value) -> RBrace
  def on_rbrace(value)
    node =
      RBrace.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # RBracket represents the use of a right bracket, i.e., +]+.
  class RBracket
    # [String] the right bracket
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_rbracket: (String value) -> RBracket
  def on_rbracket(value)
    node =
      RBracket.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Redo represents the use of the +redo+ keyword.
  #
  #     redo
  #
  class Redo
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('redo')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :redo, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_redo: () -> Redo
  def on_redo
    keyword = find_token(Kw, 'redo')

    Redo.new(value: keyword.value, location: keyword.location)
  end

  # RegexpContent represents the body of a regular expression.
  #
  #     /.+ #{pattern} .+/
  #
  # In the example above, a RegexpContent node represents everything contained
  # within the forward slashes.
  class RegexpContent
    # [String] the opening of the regular expression
    attr_reader :beginning

    # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
    # regular expression
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(beginning:, parts:, location:)
      @beginning = beginning
      @parts = parts
      @location = location
    end
  end

  # :call-seq:
  #   on_regexp_add: (
  #     RegexpContent regexp_content,
  #     (StringDVar | StringEmbExpr | TStringContent) part
  #   ) -> RegexpContent
  def on_regexp_add(regexp_content, part)
    RegexpContent.new(
      beginning: regexp_content.beginning,
      parts: regexp_content.parts << part,
      location: regexp_content.location.to(part.location)
    )
  end

  # RegexpBeg represents the start of a regular expression literal.
  #
  #     /.+/
  #
  # In the example above, RegexpBeg represents the first / token. Regular
  # expression literals can also be declared using the %r syntax, as in:
  #
  #     %r{.+}
  #
  class RegexpBeg
    # [String] the beginning of the regular expression
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_regexp_beg: (String value) -> RegexpBeg
  def on_regexp_beg(value)
    node =
      RegexpBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # RegexpEnd represents the end of a regular expression literal.
  #
  #     /.+/m
  #
  # In the example above, the RegexpEnd event represents the /m at the end of
  # the regular expression literal. You can also declare regular expression
  # literals using %r, as in:
  #
  #     %r{.+}m
  #
  class RegexpEnd
    # [String] the end of the regular expression
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_regexp_end: (String value) -> RegexpEnd
  def on_regexp_end(value)
    RegexpEnd.new(
      value: value,
      location: Location.token(line: lineno, char: char_pos, size: value.size)
    )
  end

  # RegexpLiteral represents a regular expression literal.
  #
  #     /.+/
  #
  class RegexpLiteral
    # [String] the beginning of the regular expression literal
    attr_reader :beginning

    # [String] the ending of the regular expression literal
    attr_reader :ending

    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # regular expression literal
    attr_reader :parts

    # [Locatione] the location of this node
    attr_reader :location

    def initialize(beginning:, ending:, parts:, location:)
      @beginning = beginning
      @ending = ending
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('regexp_literal')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      {
        type: :regexp_literal,
        beging: beginning,
        ending: ending,
        parts: parts,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_regexp_literal: (
  #     RegexpContent regexp_content,
  #     RegexpEnd ending
  #   ) -> RegexpLiteral
  def on_regexp_literal(regexp_content, ending)
    RegexpLiteral.new(
      beginning: regexp_content.beginning,
      ending: ending.value,
      parts: regexp_content.parts,
      location: regexp_content.location.to(ending.location)
    )
  end

  # :call-seq:
  #   on_regexp_new: () -> RegexpContent
  def on_regexp_new
    regexp_beg = find_token(RegexpBeg)

    RegexpContent.new(
      beginning: regexp_beg.value,
      parts: [],
      location: regexp_beg.location
    )
  end

  # RescueEx represents the list of exceptions being rescued in a rescue clause.
  #
  #     begin
  #     rescue Exception => exception
  #     end
  #
  class RescueEx
    # [untyped] the list of exceptions being rescued
    attr_reader :exceptions

    # [nil | Field | VarField] the expression being used to capture the raised
    # exception
    attr_reader :variable

    # [Location] the location of this node
    attr_reader :location

    def initialize(exceptions:, variable:, location:)
      @exceptions = exceptions
      @variable = variable
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rescue_ex')

        q.breakable
        q.pp(exceptions)

        q.breakable
        q.pp(variable)
      end
    end

    def to_json(*opts)
      {
        type: :rescue_ex,
        extns: exceptions,
        var: variable,
        loc: location
      }.to_json(*opts)
    end
  end

  # Rescue represents the use of the rescue keyword inside of a BodyStmt node.
  #
  #     begin
  #     rescue
  #     end
  #
  class Rescue
    # [RescueEx] the exceptions being rescued
    attr_reader :exception

    # [Statements] the expressions to evaluate when an error is rescued
    attr_reader :statements

    # [nil | Rescue] the optional next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(exception:, statements:, consequent:, location:)
      @exception = exception
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def bind_end(end_char)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: location.start_char,
          end_line: location.end_line,
          end_char: end_char
        )

      if consequent
        consequent.bind_end(end_char)
        statements.bind_end(consequent.location.start_char)
      else
        statements.bind_end(end_char)
      end
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rescue')

        if exception
          q.breakable
          q.pp(exception)
        end

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :rescue,
        extn: exception,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_rescue: (
  #     (nil | [untyped] | MRHS | MRHSAddStar) exceptions,
  #     (nil | Field | VarField) variable,
  #     Statements statements,
  #     (nil | Rescue) consequent
  #   ) -> Rescue
  def on_rescue(exceptions, variable, statements, consequent)
    keyword = find_token(Kw, 'rescue')
    exceptions = exceptions[0] if exceptions.is_a?(Array)

    last_node = variable || exceptions || keyword
    statements.bind(
      find_next_statement_start(last_node.location.end_char),
      char_pos
    )

    # We add an additional inner node here that ripper doesn't provide so that
    # we have a nice place to attach inline comments. But we only need it if we
    # have an exception or a variable that we're rescuing.
    rescue_ex =
      if exceptions || variable
        RescueEx.new(
          exceptions: exceptions,
          variable: variable,
          location:
            Location.new(
              start_line: keyword.location.start_line,
              start_char: keyword.location.end_char + 1,
              end_line: last_node.location.end_line,
              end_char: last_node.location.end_char
            )
        )
      end

    Rescue.new(
      exception: rescue_ex,
      statements: statements,
      consequent: consequent,
      location:
        Location.new(
          start_line: keyword.location.start_line,
          start_char: keyword.location.start_char,
          end_line: lineno,
          end_char: char_pos
        )
    )
  end

  # RescueMod represents the use of the modifier form of a +rescue+ clause.
  #
  #     expression rescue value
  #
  class RescueMod
    # [untyped] the expression to execute
    attr_reader :statement

    # [untyped] the value to use if the executed expression raises an error
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, value:, location:)
      @statement = statement
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rescue_mod')

        q.breakable
        q.pp(statement)

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      {
        type: :rescue_mod,
        stmt: statement,
        value: value,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_rescue_mod: (untyped statement, untyped value) -> RescueMod
  def on_rescue_mod(statement, value)
    find_token(Kw, 'rescue')

    RescueMod.new(
      statement: statement,
      value: value,
      location: statement.location.to(value.location)
    )
  end

  # RestParam represents defining a parameter in a method definition that
  # accepts all remaining positional parameters.
  #
  #     def method(*rest) end
  #
  class RestParam
    # [nil | Ident] the name of the parameter
    attr_reader :name

    # [Location] the location of this node
    attr_reader :location

    def initialize(name:, location:)
      @name = name
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('rest_param')

        q.breakable
        q.pp(name)
      end
    end

    def to_json(*opts)
      { type: :rest_param, name: name, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_rest_param: ((nil | Ident) name) -> RestParam
  def on_rest_param(name)
    location = find_token(Op, '*').location
    location = location.to(name.location) if name

    RestParam.new(name: name, location: location)
  end

  # Retry represents the use of the +retry+ keyword.
  #
  #     retry
  #
  class Retry
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('retry')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :retry, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_retry: () -> Retry
  def on_retry
    keyword = find_token(Kw, 'retry')

    Retry.new(value: keyword.value, location: keyword.location)
  end

  # Return represents using the +return+ keyword with arguments.
  #
  #     return value
  #
  class Return
    # [Args | ArgsAddBlock] the arguments being passed to the keyword
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('return')

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :return, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_return: ((Args | ArgsAddBlock) arguments) -> Return
  def on_return(arguments)
    keyword = find_token(Kw, 'return')

    Return.new(
      arguments: arguments,
      location: keyword.location.to(arguments.location)
    )
  end

  # Return0 represents the bare +return+ keyword with no arguments.
  #
  #     return
  #
  class Return0
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('return0')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :return0, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_return0: () -> Return0
  def on_return0
    keyword = find_token(Kw, 'return')

    Return0.new(value: keyword.value, location: keyword.location)
  end

  # RParen represents the use of a right parenthesis, i.e., +)+.
  class RParen
    # [String] the parenthesis
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_rparen: (String value) -> RParen
  def on_rparen(value)
    node =
      RParen.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # SClass represents a block of statements that should be evaluated within the
  # context of the singleton class of an object. It's frequently used to define
  # singleton methods.
  #
  #     class << self
  #     end
  #
  class SClass
    # [untyped] the target of the singleton class to enter
    attr_reader :target

    # [BodyStmt] the expressions to be executed
    attr_reader :bodystmt

    # [Location] the location of this node
    attr_reader :location

    def initialize(target:, bodystmt:, location:)
      @target = target
      @bodystmt = bodystmt
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('sclass')

        q.breakable
        q.pp(target)

        q.breakable
        q.pp(bodystmt)
      end
    end

    def to_json(*opts)
      {
        type: :sclass,
        target: target,
        bodystmt: bodystmt,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_sclass: (untyped target, BodyStmt bodystmt) -> SClass
  def on_sclass(target, bodystmt)
    beginning = find_token(Kw, 'class')
    ending = find_token(Kw, 'end')

    bodystmt.bind(
      find_next_statement_start(target.location.end_char),
      ending.location.start_char
    )

    SClass.new(
      target: target,
      bodystmt: bodystmt,
      location: beginning.location.to(ending.location)
    )
  end

  # def on_semicolon(value)
  #   value
  # end

  # def on_sp(value)
  #   value
  # end

  # stmts_add is a parser event that represents a single statement inside a
  # list of statements within any lexical block. It accepts as arguments the
  # parent stmts node as well as an stmt which can be any expression in
  # Ruby.
  def on_stmts_add(statements, statement)
    statements << statement
  end

  # Everything that has a block of code inside of it has a list of statements.
  # Normally we would just track those as a node that has an array body, but we
  # have some special handling in order to handle empty statement lists. They
  # need to have the right location information, so all of the parent node of
  # stmts nodes will report back down the location information. We then
  # propagate that onto void_stmt nodes inside the stmts in order to make sure
  # all comments get printed appropriately.
  class Statements
    # [SyntaxTree] the parser that created this node
    attr_reader :parser

    # [Array[ untyped ]] the list of expressions contained within this node
    attr_reader :body

    # [Location] the location of this node
    attr_reader :location

    def initialize(parser:, body:, location:)
      @parser = parser
      @body = body
      @location = location
    end

    def bind(start_char, end_char)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          end_line: location.end_line,
          end_char: end_char
        )

      if body[0].is_a?(VoidStmt)
        location = body[0].location
        location =
          Location.new(
            start_line: location.start_line,
            start_char: start_char,
            end_line: location.end_line,
            end_char: start_char
          )

        body[0] = VoidStmt.new(location: location)
      end

      attach_comments(start_char, end_char)
    end

    def bind_end(end_char)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: location.start_char,
          end_line: location.end_line,
          end_char: end_char
        )
    end

    def <<(statement)
      @location =
        body.any? ? location.to(statement.location) : statement.location

      body << statement
      self
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('statements')

        q.breakable
        q.seplist(body) { |statement| q.pp(statement) }
      end
    end

    def to_json(*opts)
      { type: :statements, body: body, loc: location }.to_json(*opts)
    end

    private

    def attach_comments(start_char, end_char)
      attachable =
        parser.comments.select do |comment|
          !comment.inline? && start_char <= comment.location.start_char &&
            end_char >= comment.location.end_char &&
            !comment.value.include?('prettier-ignore')
        end

      return if attachable.empty?

      parser.comments -= attachable
      @body = (body + attachable).sort_by! { |node| node.location.start_char }
    end
  end

  # :call-seq:
  #   on_stmts_new: () -> Statements
  def on_stmts_new
    Statements.new(
      parser: self,
      body: [],
      location: Location.fixed(line: lineno, char: char_pos)
    )
  end

  # StringContent represents the contents of a string-like value.
  #
  #     "string"
  #
  class StringContent
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # string
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end
  end

  # :call-seq:
  #   on_string_add: (
  #     String string,
  #     (StringEmbExpr | StringDVar | TStringContent) part
  #   ) -> StringContent
  def on_string_add(string, part)
    location =
      string.parts.any? ? string.location.to(part.location) : part.location

    StringContent.new(parts: string.parts << part, location: location)
  end

  # StringConcat represents concatenating two strings together using a backward
  # slash.
  #
  #     "first" \
  #       "second"
  #
  class StringConcat
    # [StringConcat | StringLiteral] the left side of the concatenation
    attr_reader :left

    # [StringLiteral] the right side of the concatenation
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('string_concat')

        q.breakable
        q.pp(left)

        q.breakable
        q.pp(right)
      end
    end

    def to_json(*opts)
      { type: :string_concat, left: left, right: right, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_string_concat: (
  #     (StringConcat | StringLiteral) left,
  #     StringLiteral right
  #   ) -> StringConcat
  def on_string_concat(left, right)
    StringConcat.new(
      left: left,
      right: right,
      location: left.location.to(right.location)
    )
  end

  # :call-seq:
  #   on_string_content: () -> StringContent
  def on_string_content
    StringContent.new(
      parts: [],
      location: Location.fixed(line: lineno, char: char_pos)
    )
  end

  # StringDVar represents shorthand interpolation of a variable into a string.
  # It allows you to take an instance variable, class variable, or global
  # variable and omit the braces when interpolating.
  #
  #     "#@variable"
  #
  class StringDVar
    # [Backref | VarRef] the variable being interpolated
    attr_reader :variable

    # [Location] the location of this node
    attr_reader :location

    def initialize(variable:, location:)
      @variable = variable
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('string_dvar')

        q.breakable
        q.pp(variable)
      end
    end

    def to_json(*opts)
      { type: :string_dvar, var: variable, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_string_dvar: ((Backref | VarRef) variable) -> StringDVar
  def on_string_dvar(variable)
    embvar = find_token(EmbVar)

    StringDVar.new(
      variable: variable,
      location: embvar.location.to(variable.location)
    )
  end

  # StringEmbExpr represents interpolated content. It can be contained within a
  # couple of different parent nodes, including regular expressions, strings,
  # and dynamic symbols.
  #
  #     "string #{expression}"
  #
  class StringEmbExpr
    # [Statements] the expressions to be interpolated
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(statements:, location:)
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('string_embexpr')

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      { type: :string_embexpr, stmts: statements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_string_embexpr: (Statements statements) -> StringEmbExpr
  def on_string_embexpr(statements)
    embexpr_beg = find_token(EmbExprBeg)
    embexpr_end = find_token(EmbExprEnd)

    statements.bind(
      embexpr_beg.location.end_char,
      embexpr_end.location.start_char
    )

    StringEmbExpr.new(
      statements: statements,
      location: embexpr_beg.location.to(embexpr_end.location)
    )
  end

  # StringLiteral represents a string literal.
  #
  #     "string"
  #
  class StringLiteral
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # string literal
    attr_reader :parts

    # [String] which quote was used by the string literal
    attr_reader :quote

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, quote:, location:)
      @parts = parts
      @quote = quote
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('string_literal')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      {
        type: :string_literal,
        parts: parts,
        quote: quote,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_string_literal: (String string) -> Heredoc | StringLiteral
  def on_string_literal(string)
    heredoc = @heredocs[-1]

    if heredoc && heredoc.ending
      heredoc = @heredocs.pop

      Heredoc.new(
        beginning: heredoc.beginning,
        ending: heredoc.ending,
        parts: string.parts,
        location: heredoc.location
      )
    else
      tstring_beg = find_token(TStringBeg)
      tstring_end = find_token(TStringEnd)

      StringLiteral.new(
        parts: string.parts,
        quote: tstring_beg.value,
        location: tstring_beg.location.to(tstring_end.location)
      )
    end
  end

  # Super represents using the +super+ keyword with arguments. It can optionally
  # use parentheses.
  #
  #     super(value)
  #
  class Super
    # [ArgParen | Args | ArgsAddBlock] the arguments to the keyword
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('super')

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :super, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_super: ((ArgParen | Args | ArgsAddBlock) arguments) -> Super
  def on_super(arguments)
    keyword = find_token(Kw, 'super')

    Super.new(
      arguments: arguments,
      location: keyword.location.to(arguments.location)
    )
  end

  # SymBeg represents the beginning of a symbol literal.
  #
  #     :symbol
  #
  # SymBeg is also used for dynamic symbols, as in:
  #
  #     :"symbol"
  #
  # Finally, SymBeg is also used for symbols using the %s syntax, as in:
  #
  #     %s[symbol]
  #
  # The value of this node is a string. In most cases (as in the first example
  # above) it will contain just ":". In the case of dynamic symbols it will
  # contain ":'" or ":\"". In the case of %s symbols, it will contain the start
  # of the symbol including the %s and the delimiter.
  class SymBeg
    # [String] the beginning of the symbol
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # symbeg is a token that represents the beginning of a symbol literal.
  # In most cases it will contain just ":" as in the value, but if its a dynamic
  # symbol being defined it will contain ":'" or ":\"".
  def on_symbeg(value)
    node =
      SymBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # SymbolContent represents symbol contents and is always the child of a
  # SymbolLiteral node.
  #
  #     :symbol
  #
  class SymbolContent
    # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op] the value of the
    # symbol
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_symbol: (
  #     (Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op) value
  #   ) -> SymbolContent
  def on_symbol(value)
    tokens.pop

    SymbolContent.new(value: value, location: value.location)
  end

  # SymbolLiteral represents a symbol in the system with no interpolation
  # (as opposed to a DynaSymbol which has interpolation).
  #
  #     :symbol
  #
  class SymbolLiteral
    # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op] the value of the
    # symbol
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('symbol_literal')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :symbol_literal, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_symbol_literal: (
  #     (
  #       Backtick | Const | CVar | GVar | Ident |
  #       IVar | Kw | Op | SymbolContent
  #     ) value
  #   ) -> SymbolLiteral
  def on_symbol_literal(value)
    if tokens[-1] == value
      SymbolLiteral.new(value: tokens.pop, location: value.location)
    else
      symbeg = find_token(SymBeg)

      SymbolLiteral.new(
        value: value.value,
        location: symbeg.location.to(value.location)
      )
    end
  end

  # Symbols represents a symbol array literal with interpolation.
  #
  #     %I[one two three]
  #
  class Symbols
    # [Array[ Word ]] the words in the symbol array literal
    attr_reader :elements

    # [Location] the location of this node
    attr_reader :location

    def initialize(elements:, location:)
      @elements = elements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('symbols')

        q.breakable
        q.group(2, '(', ')') { q.seplist(elements) { |element| q.pp(element) } }
      end
    end

    def to_json(*opts)
      { type: :symbols, elems: elements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_symbols_add: (Symbols symbols, Word word) -> Symbols
  def on_symbols_add(symbols, word)
    Symbols.new(
      elements: symbols.elements << word,
      location: symbols.location.to(word.location)
    )
  end

  # SymbolsBeg represents the start of a symbol array literal with
  # interpolation.
  #
  #     %I[one two three]
  #
  # In the snippet above, SymbolsBeg represents the "%I[" token. Note that these
  # kinds of arrays can start with a lot of different delimiter types
  # (e.g., %I| or %I<).
  class SymbolsBeg
    # [String] the beginning of the symbol literal array
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_symbols_beg: (String value) -> SymbolsBeg
  def on_symbols_beg(value)
    node =
      SymbolsBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # :call-seq:
  #   on_symbols_new: () -> Symbols
  def on_symbols_new
    symbols_beg = find_token(SymbolsBeg)

    Symbols.new(elements: [], location: symbols_beg.location)
  end

  # TLambda represents the beginning of a lambda literal.
  #
  #     -> { value }
  #
  # In the example above the TLambda represents the +->+ operator.
  class TLambda
    # [String] the beginning of the lambda literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_tlambda: (String value) -> TLambda
  def on_tlambda(value)
    node =
      TLambda.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # TLamBeg represents the beginning of the body of a lambda literal using
  # braces.
  #
  #     -> { value }
  #
  # In the example above the TLamBeg represents the +{+ operator.
  class TLamBeg
    # [String] the beginning of the body of the lambda literal
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_tlambeg: (String value) -> TLamBeg
  def on_tlambeg(value)
    node =
      TLamBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # TopConstField is always the child node of some kind of assignment. It
  # represents when you're assigning to a constant that is being referenced at
  # the top level.
  #
  #     ::Constant = value
  #
  class TopConstField
    # [Const] the constant being assigned
    attr_reader :constant

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, location:)
      @constant = constant
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('top_const_field')

        q.breakable
        q.pp(constant)
      end
    end

    def to_json(*opts)
      { type: :top_const_field, constant: constant, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_top_const_field: (Const constant) -> TopConstRef
  def on_top_const_field(constant)
    operator = find_colon2_before(constant)

    TopConstField.new(
      constant: constant,
      location: operator.location.to(constant.location)
    )
  end

  # TopConstRef is very similar to TopConstField except that it is not involved
  # in an assignment.
  #
  #     ::Constant
  #
  class TopConstRef
    # [Const] the constant being referenced
    attr_reader :constant

    # [Location] the location of this node
    attr_reader :location

    def initialize(constant:, location:)
      @constant = constant
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('top_const_ref')

        q.breakable
        q.pp(constant)
      end
    end

    def to_json(*opts)
      { type: :top_const_ref, constant: constant, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_top_const_ref: (Const constant) -> TopConstRef
  def on_top_const_ref(constant)
    operator = find_colon2_before(constant)

    TopConstRef.new(
      constant: constant,
      location: operator.location.to(constant.location)
    )
  end

  # TStringBeg represents the beginning of a string literal.
  #
  #     "string"
  #
  # In the example above, TStringBeg represents the first set of quotes. Strings
  # can also use single quotes. They can also be declared using the +%q+ and
  # +%Q+ syntax, as in:
  #
  #     %q{string}
  #
  class TStringBeg
    # [String] the beginning of the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_tstring_beg: (String value) -> TStringBeg
  def on_tstring_beg(value)
    node =
      TStringBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # TStringContent represents plain characters inside of an entity that accepts
  # string content like a string, heredoc, command string, or regular
  # expression.
  #
  #     "string"
  #
  # In the example above, TStringContent represents the +string+ token contained
  # within the string.
  class TStringContent
    # [String] the content of the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('tstring_content')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      {
        type: :tstring_content,
        value: value.force_encoding('UTF-8'),
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_tstring_content: (String value) -> TStringContent
  def on_tstring_content(value)
    TStringContent.new(
      value: value,
      location: Location.token(line: lineno, char: char_pos, size: value.size)
    )
  end

  # TStringEnd represents the end of a string literal.
  #
  #     "string"
  #
  # In the example above, TStringEnd represents the second set of quotes.
  # Strings can also use single quotes. They can also be declared using the +%q+
  # and +%Q+ syntax, as in:
  #
  #     %q{string}
  #
  class TStringEnd
    # [String] the end of the string
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_tstring_end: (String value) -> TStringEnd
  def on_tstring_end(value)
    node =
      TStringEnd.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # Not represents the unary +not+ method being called on an expression.
  #
  #     not value
  #
  class Not
    # [untyped] the statement on which to operate
    attr_reader :statement

    # [boolean] whether or not parentheses were used
    attr_reader :parentheses

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, parentheses:, location:)
      @statement = statement
      @parentheses = parentheses
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('not')

        q.breakable
        q.pp(statement)
      end
    end

    def to_json(*opts)
      {
        type: :not,
        value: statement,
        paren: parentheses,
        loc: location
      }.to_json(*opts)
    end
  end

  # Unary represents a unary method being called on an expression, as in +!+ or
  # +~+.
  #
  #     !value
  #
  class Unary
    # [String] the operator being used
    attr_reader :operator

    # [untyped] the statement on which to operate
    attr_reader :statement

    # [Location] the location of this node
    attr_reader :location

    def initialize(operator:, statement:, location:)
      @operator = operator
      @statement = statement
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('unary')

        q.breakable
        q.pp(operator)

        q.breakable
        q.pp(statement)
      end
    end

    def to_json(*opts)
      { type: :unary, op: operator, value: statement, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_unary: (:not operator, untyped statement) -> Not
  #           | (Symbol operator, untyped statement) -> Unary
  def on_unary(operator, statement)
    if operator == :not
      # We have somewhat special handling of the not operator since if it has
      # parentheses they don't get reported as a paren node for some reason.

      beginning = find_token(Kw, 'not')
      ending = statement

      range = beginning.location.end_char...statement.location.start_char
      paren = source[range].include?('(')

      if paren
        find_token(LParen)
        ending = find_token(RParen)
      end

      Not.new(
        statement: statement,
        parentheses: paren,
        location: beginning.location.to(ending.location)
      )
    else
      # Special case instead of using find_token here. It turns out that
      # if you have a range that goes from a negative number to a negative
      # number then you can end up with a .. or a ... that's higher in the
      # stack. So we need to explicitly disallow those operators.
      index =
        tokens.rindex do |token|
          token.is_a?(Op) &&
            token.location.start_char < statement.location.start_char &&
            !%w[.. ...].include?(token.value)
        end

      beginning = tokens.delete_at(index)

      Unary.new(
        operator: operator[0], # :+@ -> "+"
        statement: statement,
        location: beginning.location.to(statement.location)
      )
    end
  end

  # Undef represents the use of the +undef+ keyword.
  #
  #     undef method
  #
  class Undef
    # [Array[ DynaSymbol | SymbolLiteral ]] the symbols to undefine
    attr_reader :symbols

    # [Location] the location of this node
    attr_reader :location

    def initialize(symbols:, location:)
      @symbols = symbols
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('undef')

        q.breakable
        q.group(2, '(', ')') { q.seplist(symbols) { |symbol| q.pp(symbol) } }
      end
    end

    def to_json(*opts)
      { type: :undef, syms: symbols, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_undef: (Array[DynaSymbol | SymbolLiteral] symbols) -> Undef
  def on_undef(symbols)
    keyword = find_token(Kw, 'undef')

    Undef.new(
      symbols: symbols,
      location: keyword.location.to(symbols.last.location)
    )
  end

  # Unless represents the first clause in an +unless+ chain.
  #
  #     unless predicate
  #     end
  #
  class Unless
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil, Elsif, Else] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('unless')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :unless,
        pred: predicate,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_unless: (
  #     untyped predicate,
  #     Statements statements,
  #     ((nil | Elsif | Else) consequent)
  #   ) -> Unless
  def on_unless(predicate, statements, consequent)
    beginning = find_token(Kw, 'unless')
    ending = consequent || find_token(Kw, 'end')

    statements.bind(predicate.location.end_char, ending.location.start_char)

    Unless.new(
      predicate: predicate,
      statements: statements,
      consequent: consequent,
      location: beginning.location.to(ending.location)
    )
  end

  # UnlessMod represents the modifier form of an +unless+ statement.
  #
  #     expression unless predicate
  #
  class UnlessMod
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, predicate:, location:)
      @statement = statement
      @predicate = predicate
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('unless_mod')

        q.breakable
        q.pp(statement)

        q.breakable
        q.pp(predicate)
      end
    end

    def to_json(*opts)
      {
        type: :unless_mod,
        stmt: statement,
        pred: predicate,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_unless_mod: (untyped predicate, untyped statement) -> UnlessMod
  def on_unless_mod(predicate, statement)
    find_token(Kw, 'unless')

    UnlessMod.new(
      statement: statement,
      predicate: predicate,
      location: statement.location.to(predicate.location)
    )
  end

  # Until represents an +until+ loop.
  #
  #     until predicate
  #     end
  #
  class Until
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, statements:, location:)
      @predicate = predicate
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('until')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :until,
        pred: predicate,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_until: (untyped predicate, Statements statements) -> Until
  def on_until(predicate, statements)
    beginning = find_token(Kw, 'until')
    ending = find_token(Kw, 'end')

    # Consume the do keyword if it exists so that it doesn't get confused for
    # some other block
    keyword = find_token(Kw, 'do', consume: false)
    if keyword && keyword.location.start_char > predicate.location.end_char &&
         keyword.location.end_char < ending.location.start_char
      tokens.delete(keyword)
    end

    # Update the Statements location information
    statements.bind(predicate.location.end_char, ending.location.start_char)

    Until.new(
      predicate: predicate,
      statements: statements,
      location: beginning.location.to(ending.location)
    )
  end

  # UntilMod represents the modifier form of a +until+ loop.
  #
  #     expression until predicate
  #
  class UntilMod
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, predicate:, location:)
      @statement = statement
      @predicate = predicate
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('until_mod')

        q.breakable
        q.pp(statement)

        q.breakable
        q.pp(predicate)
      end
    end

    def to_json(*opts)
      {
        type: :until_mod,
        stmt: statement,
        pred: predicate,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_until_mod: (untyped predicate, untyped statement) -> UntilMod
  def on_until_mod(predicate, statement)
    find_token(Kw, 'until')

    UntilMod.new(
      statement: statement,
      predicate: predicate,
      location: statement.location.to(predicate.location)
    )
  end

  # VarAlias represents when you're using the +alias+ keyword with global
  # variable arguments.
  #
  #     alias $new $old
  #
  class VarAlias
    # [GVar] the new alias of the variable
    attr_reader :left

    # [Backref | GVar] the current name of the variable to be aliased
    attr_reader :right

    # [Location] the location of this node
    attr_reader :location

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('var_alias')

        q.breakable
        q.pp(left)

        q.breakable
        q.pp(right)
      end
    end

    def to_json(*opts)
      { type: :var_alias, left: left, right: right, loc: location }.to_json(
        *opts
      )
    end
  end

  # :call-seq:
  #   on_var_alias: (GVar left, (Backref | GVar) right) -> VarAlias
  def on_var_alias(left, right)
    keyword = find_token(Kw, 'alias')

    VarAlias.new(
      left: left,
      right: right,
      location: keyword.location.to(right.location)
    )
  end

  # VarField represents a variable that is being assigned a value. As such, it
  # is always a child of an assignment type node.
  #
  #     variable = value
  #
  # In the example above, the VarField node represents the +variable+ token.
  class VarField
    # [nil | Const | CVar | GVar | Ident | IVar] the target of this node
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('var_field')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :var_field, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_var_field: (
  #     (nil | Const | CVar | GVar | Ident | IVar) value
  #   ) -> VarField
  def on_var_field(value)
    location =
      if value
        value.location
      else
        # You can hit this pattern if you're assigning to a splat using pattern
        # matching syntax in Ruby 2.7+
        Location.fixed(line: lineno, char: char_pos)
      end

    VarField.new(value: value, location: location)
  end

  # VarRef represents a variable reference.
  #
  #     true
  #
  # This can be a plain local variable like the example above. It can also be a
  # constant, a class variable, a global variable, an instance variable, a
  # keyword (like +self+, +nil+, +true+, or +false+), or a numbered block
  # variable.
  class VarRef
    # [Const | CVar | GVar | Ident | IVar | Kw] the value of this node
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('var_ref')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :var_ref, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_var_ref: ((Const | CVar | GVar | Ident | IVar | Kw) value) -> VarRef
  def on_var_ref(value)
    VarRef.new(value: value, location: value.location)
  end

  # AccessCtrl represents a call to a method visibility control, i.e., +public+,
  # +protected+, or +private+.
  #
  #     private
  #
  class AccessCtrl
    # [Ident] the value of this expression
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('access_ctrl')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :access_ctrl, value: value, loc: location }.to_json(*opts)
    end
  end

  # VCall represent any plain named object with Ruby that could be either a
  # local variable or a method call.
  #
  #     variable
  #
  class VCall
    # [Ident] the value of this expression
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('vcall')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :vcall, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_vcall: (Ident ident) -> AccessCtrl | VCall
  def on_vcall(ident)
    @controls ||= %w[private protected public].freeze

    if @controls.include?(ident.value) && ident.value == lines[lineno - 1].strip
      # Access controls like private, protected, and public are reported as
      # vcall nodes since they're technically method calls. We want to be able
      # add new lines around them as necessary, so here we're going to
      # explicitly track those as a different node type.
      AccessCtrl.new(value: ident, location: ident.location)
    else
      VCall.new(value: ident, location: ident.location)
    end
  end

  # VoidStmt represents an empty lexical block of code.
  #
  #     ;;
  #
  class VoidStmt
    # [Location] the location of this node
    attr_reader :location

    def initialize(location:)
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') { q.text('void_stmt') }
    end

    def to_json(*opts)
      { type: :void_stmt, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_void_stmt: () -> VoidStmt
  def on_void_stmt
    VoidStmt.new(location: Location.fixed(line: lineno, char: char_pos))
  end

  # When represents a +when+ clause in a +case+ chain.
  #
  #     case value
  #     when predicate
  #     end
  #
  class When
    # [untyped] the arguments to the when clause
    attr_reader :arguments

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Else | When] the next clause in the chain
    attr_reader :consequent

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, statements:, consequent:, location:)
      @arguments = arguments
      @statements = statements
      @consequent = consequent
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('when')

        q.breakable
        q.pp(arguments)

        q.breakable
        q.pp(statements)

        if consequent
          q.breakable
          q.pp(consequent)
        end
      end
    end

    def to_json(*opts)
      {
        type: :when,
        args: arguments,
        stmts: statements,
        cons: consequent,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_when: (
  #     untyped arguments,
  #     Statements statements,
  #     (nil | Else | When) consequent
  #   ) -> When
  def on_when(arguments, statements, consequent)
    beginning = find_token(Kw, 'when')
    ending = consequent || find_token(Kw, 'end')

    statements.bind(arguments.location.end_char, ending.location.start_char)

    When.new(
      arguments: arguments,
      statements: statements,
      consequent: consequent,
      location: beginning.location.to(ending.location)
    )
  end

  # While represents a +while+ loop.
  #
  #     while predicate
  #     end
  #
  class While
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Location] the location of this node
    attr_reader :location

    def initialize(predicate:, statements:, location:)
      @predicate = predicate
      @statements = statements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('while')

        q.breakable
        q.pp(predicate)

        q.breakable
        q.pp(statements)
      end
    end

    def to_json(*opts)
      {
        type: :while,
        pred: predicate,
        stmts: statements,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_while: (untyped predicate, Statements statements) -> While
  def on_while(predicate, statements)
    beginning = find_token(Kw, 'while')
    ending = find_token(Kw, 'end')

    # Consume the do keyword if it exists so that it doesn't get confused for
    # some other block
    keyword = find_token(Kw, 'do', consume: false)
    if keyword && keyword.location.start_char > predicate.location.end_char &&
         keyword.location.end_char < ending.location.start_char
      tokens.delete(keyword)
    end

    # Update the Statements location information
    statements.bind(predicate.location.end_char, ending.location.start_char)

    While.new(
      predicate: predicate,
      statements: statements,
      location: beginning.location.to(ending.location)
    )
  end

  # WhileMod represents the modifier form of a +while+ loop.
  #
  #     expression while predicate
  #
  class WhileMod
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Location] the location of this node
    attr_reader :location

    def initialize(statement:, predicate:, location:)
      @statement = statement
      @predicate = predicate
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('while_mod')

        q.breakable
        q.pp(statement)

        q.breakable
        q.pp(predicate)
      end
    end

    def to_json(*opts)
      {
        type: :while_mod,
        stmt: statement,
        pred: predicate,
        loc: location
      }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_while_mod: (untyped predicate, untyped statement) -> WhileMod
  def on_while_mod(predicate, statement)
    find_token(Kw, 'while')

    WhileMod.new(
      statement: statement,
      predicate: predicate,
      location: statement.location.to(predicate.location)
    )
  end

  # Word represents an element within a special array literal that accepts
  # interpolation.
  #
  #     %W[a#{b}c xyz]
  #
  # In the example above, there would be two Word nodes within a parent Words
  # node.
  class Word
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # word
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('word')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :word, parts: parts, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_word_add: (
  #     Word word,
  #     (StringEmbExpr | StringDVar | TStringContent) part
  #   ) -> Word
  def on_word_add(word, part)
    location =
      word.parts.empty? ? part.location : word.location.to(part.location)

    Word.new(parts: word.parts << part, location: location)
  end

  # :call-seq:
  #   on_word_new: () -> Word
  def on_word_new
    Word.new(parts: [], location: Location.fixed(line: lineno, char: char_pos))
  end

  # Words represents a string literal array with interpolation.
  #
  #     %W[one two three]
  #
  class Words
    # [Array[ Word ]] the elements of this array
    attr_reader :elements

    # [Location] the location of this node
    attr_reader :location

    def initialize(elements:, location:)
      @elements = elements
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('words')

        q.breakable
        q.group(2, '(', ')') { q.seplist(elements) { |element| q.pp(element) } }
      end
    end

    def to_json(*opts)
      { type: :words, elems: elements, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_words_add: (Words words, Word word) -> Words
  def on_words_add(words, word)
    Words.new(
      elements: words.elements << word,
      location: words.location.to(word.location)
    )
  end

  # WordsBeg represents the beginning of a string literal array with
  # interpolation.
  #
  #     %W[one two three]
  #
  # In the snippet above, a WordsBeg would be created with the value of "%W[".
  # Note that these kinds of arrays can start with a lot of different delimiter
  # types (e.g., %W| or %W<).
  class WordsBeg
    # [String] the start of the word literal array
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end
  end

  # :call-seq:
  #   on_words_beg: (String value) -> WordsBeg
  def on_words_beg(value)
    node =
      WordsBeg.new(
        value: value,
        location: Location.token(line: lineno, char: char_pos, size: value.size)
      )

    tokens << node
    node
  end

  # :call-seq:
  #   on_words_new: () -> Words
  def on_words_new
    words_beg = find_token(WordsBeg)

    Words.new(elements: [], location: words_beg.location)
  end

  # def on_words_sep(value)
  #   value
  # end

  # XString represents the contents of an XStringLiteral.
  #
  #     `ls`
  #
  class XString
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # xstring
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end
  end

  # :call-seq:
  #   on_xstring_add: (
  #     XString xstring,
  #     (StringEmbExpr | StringDVar | TStringContent) part
  #   ) -> XString
  def on_xstring_add(xstring, part)
    XString.new(
      parts: xstring.parts << part,
      location: xstring.location.to(part.location)
    )
  end

  # :call-seq:
  #   on_xstring_new: () -> XString
  def on_xstring_new
    heredoc = @heredocs[-1]

    location =
      if heredoc && heredoc.beginning.value.include?('`')
        heredoc.location
      else
        find_token(Backtick).location
      end

    XString.new(parts: [], location: location)
  end

  # XStringLiteral represents a string that gets executed.
  #
  #     `ls`
  #
  class XStringLiteral
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # xstring
    attr_reader :parts

    # [Location] the location of this node
    attr_reader :location

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('xstring_literal')

        q.breakable
        q.group(2, '(', ')') { q.seplist(parts) { |part| q.pp(part) } }
      end
    end

    def to_json(*opts)
      { type: :xstring_literal, parts: parts, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_xstring_literal: (XString xstring) -> Heredoc | XStringLiteral
  def on_xstring_literal(xstring)
    heredoc = @heredocs[-1]

    if heredoc && heredoc.beginning.value.include?('`')
      Heredoc.new(
        beginning: heredoc.beginning,
        ending: heredoc.ending,
        parts: xstring.parts,
        location: heredoc.location
      )
    else
      ending = find_token(TStringEnd)

      XStringLiteral.new(
        parts: xstring.parts,
        location: xstring.location.to(ending.location)
      )
    end
  end

  # Yield represents using the +yield+ keyword with arguments.
  #
  #     yield value
  #
  class Yield
    # [ArgsAddBlock | Paren] the arguments passed to the yield
    attr_reader :arguments

    # [Location] the location of this node
    attr_reader :location

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('yield')

        q.breakable
        q.pp(arguments)
      end
    end

    def to_json(*opts)
      { type: :yield, args: arguments, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_yield: ((ArgsAddBlock | Paren) arguments) -> Yield
  def on_yield(arguments)
    keyword = find_token(Kw, 'yield')

    Yield.new(
      arguments: arguments,
      location: keyword.location.to(arguments.location)
    )
  end

  # Yield0 represents the bare +yield+ keyword with no arguments.
  #
  #     yield
  #
  class Yield0
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of this node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('yield0')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :yield0, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_yield0: () -> Yield0
  def on_yield0
    keyword = find_token(Kw, 'yield')

    Yield0.new(value: keyword.value, location: keyword.location)
  end

  # ZSuper represents the bare +super+ keyword with no arguments.
  #
  #     super
  #
  class ZSuper
    # [String] the value of the keyword
    attr_reader :value

    # [Location] the location of the node
    attr_reader :location

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def pretty_print(q)
      q.group(2, '(', ')') do
        q.text('zsuper')

        q.breakable
        q.pp(value)
      end
    end

    def to_json(*opts)
      { type: :zsuper, value: value, loc: location }.to_json(*opts)
    end
  end

  # :call-seq:
  #   on_zsuper: () -> ZSuper
  def on_zsuper
    keyword = find_token(Kw, 'super')

    ZSuper.new(value: keyword.value, location: keyword.location)
  end
end
