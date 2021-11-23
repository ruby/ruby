# frozen_string_literal: true
#
# This class implements a pretty printing algorithm. It finds line breaks and
# nice indentations for grouped structure.
#
# By default, the class assumes that primitive elements are strings and each
# byte in the strings is a single column in width. But it can be used for other
# situations by giving suitable arguments for some methods:
#
# * newline object and space generation block for PrettyPrint.new
# * optional width argument for PrettyPrint#text
# * PrettyPrint#breakable
#
# There are several candidate uses:
# * text formatting using proportional fonts
# * multibyte characters which has columns different to number of bytes
# * non-string formatting
#
# == Usage
#
# To use this module, you will need to generate a tree of print nodes that
# represent indentation and newline behavior before it gets sent to the printer.
# Each node has different semantics, depending on the desired output.
#
# The most basic node is a Text node. This represents plain text content that
# cannot be broken up even if it doesn't fit on one line. You would create one
# of those with the text method, as in:
#
#     PrettyPrint.format { |q| q.text('my content') }
#
# No matter what the desired output width is, the output for the snippet above
# will always be the same.
#
# If you want to allow the printer to break up the content on the space
# character when there isn't enough width for the full string on the same line,
# you can use the Breakable and Group nodes. For example:
#
#     PrettyPrint.format do |q|
#       q.group do
#         q.text('my')
#         q.breakable
#         q.text('content')
#       end
#     end
#
# Now, if everything fits on one line (depending on the maximum width specified)
# then it will be the same output as the first example. If, however, there is
# not enough room on the line, then you will get two lines of output, one for
# the first string and one for the second.
#
# There are other nodes for the print tree as well, described in the
# documentation below. They control alignment, indentation, conditional
# formatting, and more.
#
# == Bugs
# * Box based formatting?
#
# Report any bugs at http://bugs.ruby-lang.org
#
# == References
# Christian Lindig, Strictly Pretty, March 2000,
# https://lindig.github.io/papers/strictly-pretty-2000.pdf
#
# Philip Wadler, A prettier printer, March 1998,
# https://homepages.inf.ed.ac.uk/wadler/papers/prettier/prettier.pdf
#
# == Author
# Tanaka Akira <akr@fsij.org>
#
class PrettyPrint
  # A node in the print tree that represents aligning nested nodes to a certain
  # prefix width or string.
  class Align
    attr_reader :indent, :contents

    def initialize(indent:, contents: [])
      @indent = indent
      @contents = contents
    end

    def pretty_print(q)
      q.group(2, 'align([', '])') do
        q.seplist(contents) { |content| q.pp(content) }
      end
    end
  end

  # A node in the print tree that represents a place in the buffer that the
  # content can be broken onto multiple lines.
  class Breakable
    attr_reader :separator, :width

    def initialize(separator = ' ', width = separator.length, force: false, indent: true)
      @separator = separator
      @width = width
      @force = force
      @indent = indent
    end

    def force?
      @force
    end

    def indent?
      @indent
    end

    def pretty_print(q)
      q.text('breakable')

      attributes =
        [('force=true' if force?), ('indent=false' unless indent?)].compact

      if attributes.any?
        q.text('(')
        q.seplist(attributes, -> { q.text(', ') }) do |attribute|
          q.text(attribute)
        end
        q.text(')')
      end
    end
  end

  # A node in the print tree that forces the surrounding group to print out in
  # the "break" mode as opposed to the "flat" mode. Useful for when you need to
  # force a newline into a group.
  class BreakParent
    def pretty_print(q)
      q.text('break-parent')
    end
  end

  # A node in the print tree that represents a group of items which the printer
  # should try to fit onto one line. This is the basic command to tell the
  # printer when to break. Groups are usually nested, and the printer will try
  # to fit everything on one line, but if it doesn't fit it will break the
  # outermost group first and try again. It will continue breaking groups until
  # everything fits (or there are no more groups to break).
  class Group
    attr_reader :depth, :contents

    def initialize(depth, contents: [])
      @depth = depth
      @contents = contents
      @break = false
    end

    def break
      @break = true
    end

    def break?
      @break
    end

    def pretty_print(q)
      q.group(2, 'group([', '])') do
        q.seplist(contents) { |content| q.pp(content) }
      end
    end
  end

  # A node in the print tree that represents printing one thing if the
  # surrounding group node is broken and another thing if the surrounding group
  # node is flat.
  class IfBreak
    attr_reader :break_contents, :flat_contents

    def initialize(break_contents: [], flat_contents: [])
      @break_contents = break_contents
      @flat_contents = flat_contents
    end

    def pretty_print(q)
      q.group(2, 'if-break(', ')') do
        q.breakable('')
        q.group(2, '[', '],') do
          q.seplist(break_contents) { |content| q.pp(content) }
        end
        q.breakable
        q.group(2, '[', ']') do
          q.seplist(flat_contents) { |content| q.pp(content) }
        end
      end
    end
  end

  # A node in the print tree that is a variant of the Align node that indents
  # its contents by one level.
  class Indent
    attr_reader :contents

    def initialize(contents: [])
      @contents = contents
    end

    def pretty_print(q)
      q.group(2, 'indent([', '])') do
        q.seplist(contents) { |content| q.pp(content) }
      end
    end
  end

  # A node in the print tree that has its own special buffer for implementing
  # content that should flush before any newline.
  #
  # Useful for implementating trailing content, as it's not always practical to
  # constantly check where the line ends to avoid accidentally printing some
  # content after a line suffix node.
  class LineSuffix
    attr_reader :contents

    def initialize(contents: [])
      @contents = contents
    end

    def pretty_print(q)
      q.group(2, 'line-suffix([', '])') do
        q.seplist(contents) { |content| q.pp(content) }
      end
    end
  end

  # A node in the print tree that represents plain content that cannot be broken
  # up (by default this assumes strings, but it can really be anything).
  class Text
    attr_reader :objects, :width

    def initialize
      @objects = []
      @width = 0
    end

    def add(object: '', width: object.length)
      @objects << object
      @width += width
    end

    def pretty_print(q)
      q.group(2, 'text([', '])') do
        q.seplist(objects) { |object| q.pp(object) }
      end
    end
  end

  # A node in the print tree that represents trimming all of the indentation of
  # the current line, in the rare case that you need to ignore the indentation
  # that you've already created. This node should be placed after a Breakable.
  class Trim
    def pretty_print(q)
      q.text('trim')
    end
  end

  # When building up the contents in the output buffer, it's convenient to be
  # able to trim trailing whitespace before newlines. If the output object is a
  # string or array or strings, then we can do this with some gsub calls. If
  # not, then this effectively just wraps the output object and forwards on
  # calls to <<.
  module Buffer
    # This is the default output buffer that provides a base implementation of
    # trim! that does nothing. It's effectively a wrapper around whatever output
    # object was given to the format command.
    class DefaultBuffer
      attr_reader :output

      def initialize(output = [])
        @output = output
      end

      def <<(object)
        @output << object
      end

      def trim!
        0
      end
    end

    # This is an output buffer that wraps a string output object. It provides a
    # trim! method that trims off trailing whitespace from the string using
    # gsub!.
    class StringBuffer < DefaultBuffer
      def initialize(output = ''.dup)
        super(output)
      end

      def trim!
        length = output.length
        output.gsub!(/[\t ]*\z/, '')
        length - output.length
      end
    end

    # This is an output buffer that wraps an array output object. It provides a
    # trim! method that trims off trailing whitespace from the last element in
    # the array if it's an unfrozen string using the same method as the
    # StringBuffer.
    class ArrayBuffer < DefaultBuffer
      def initialize(output = [])
        super(output)
      end

      def trim!
        return 0 if output.empty?

        trimmed = 0

        while output.any? && output.last.is_a?(String) && output.last.match?(/\A[\t ]*\z/)
          trimmed += parts.pop.length
        end

        if output.any? && output.last.is_a?(String) && !output.last.frozen?
          length = output.last.length
          output.last.gsub!(/[\t ]*\z/, '')
          trimmed += length - output.last.length
        end

        trimmed
      end
    end

    # This is a switch for building the correct output buffer wrapper class for
    # the given output object.
    def self.for(output)
      case output
      when String
        StringBuffer.new(output)
      when Array
        ArrayBuffer.new(output)
      else
        DefaultBuffer.new(output)
      end
    end
  end

  # PrettyPrint::SingleLine is used by PrettyPrint.singleline_format
  #
  # It is passed to be similar to a PrettyPrint object itself, by responding to
  # all of the same print tree node builder methods, as well as the #flush
  # method.
  #
  # The significant difference here is that there are no line breaks in the
  # output. If an IfBreak node is used, only the flat contents are printed.
  # LineSuffix nodes are printed at the end of the buffer when #flush is called.
  class SingleLine
    # The output object. It stores rendered text and shoudl respond to <<.
    attr_reader :output

    # The current array of contents that the print tree builder methods should
    # append to.
    attr_reader :target

    # A buffer output that wraps any calls to line_suffix that will be flushed
    # at the end of printing.
    attr_reader :line_suffixes

    # Create a PrettyPrint::SingleLine object
    #
    # Arguments:
    # * +output+ - String (or similar) to store rendered text. Needs to respond
    #              to '<<'.
    # * +maxwidth+ - Argument position expected to be here for compatibility.
    #                This argument is a noop.
    # * +newline+ - Argument position expected to be here for compatibility.
    #               This argument is a noop.
    def initialize(output, maxwidth = nil, newline = nil)
      @output = Buffer.for(output)
      @target = @output
      @line_suffixes = Buffer::ArrayBuffer.new
    end

    # Flushes the line suffixes onto the output buffer.
    def flush
      line_suffixes.output.each { |doc| output << doc }
    end

    # --------------------------------------------------------------------------
    # Markers node builders
    # --------------------------------------------------------------------------

    # Appends +separator+ to the text to be output. By default +separator+ is
    # ' '
    #
    # The +width+, +indent+, and +force+ arguments are here for compatibility.
    # They are all noop arguments.
    def breakable(separator = ' ', width = separator.length, indent: nil, force: nil)
      target << separator
    end

    # Here for compatibility, does nothing.
    def break_parent
    end

    # Appends +separator+ to the output buffer. +width+ is a noop here for
    # compatibility.
    def fill_breakable(separator = ' ', width = separator.length)
      target << separator
    end

    # Immediately trims the output buffer.
    def trim
      target.trim!
    end

    # ----------------------------------------------------------------------------
    # Container node builders
    # ----------------------------------------------------------------------------

    # Opens a block for grouping objects to be pretty printed.
    #
    # Arguments:
    # * +indent+ - noop argument. Present for compatibility.
    # * +open_obj+ - text appended before the &block. Default is ''
    # * +close_obj+ - text appended after the &block. Default is ''
    # * +open_width+ - noop argument. Present for compatibility.
    # * +close_width+ - noop argument. Present for compatibility.
    def group(indent = nil, open_object = '', close_object = '', open_width = nil, close_width = nil)
      target << open_object
      yield
      target << close_object
    end

    # A class that wraps the ability to call #if_flat. The contents of the
    # #if_flat block are executed immediately, so effectively this class and the
    # #if_break method that triggers it are unnecessary, but they're here to
    # maintain compatibility.
    class IfBreakBuilder
      def if_flat
        yield
      end
    end

    # Effectively unnecessary, but here for compatibility.
    def if_break
      IfBreakBuilder.new
    end

    # A noop that immediately yields.
    def indent
      yield
    end

    # Changes the target output buffer to the line suffix output buffer which
    # will get flushed at the end of printing.
    def line_suffix
      previous_target, @target = @target, line_suffixes
      yield
      @target = previous_target
    end

    # Takes +indent+ arg, but does nothing with it.
    #
    # Yields to a block.
    def nest(indent)
      yield
    end

    # Add +object+ to the text to be output.
    #
    # +width+ argument is here for compatibility. It is a noop argument.
    def text(object = '', width = nil)
      target << object
    end
  end

  # This object represents the current level of indentation within the printer.
  # It has the ability to generate new levels of indentation through the #align
  # and #indent methods.
  class IndentLevel
    IndentPart = Object.new
    DedentPart = Object.new

    StringAlignPart = Struct.new(:n)
    NumberAlignPart = Struct.new(:n)

    attr_reader :genspace, :value, :length, :queue, :root

    def initialize(genspace:, value: genspace.call(0), length: 0, queue: [], root: nil)
      @genspace = genspace
      @value = value
      @length = length
      @queue = queue
      @root = root
    end

    # This can accept a whole lot of different kinds of objects, due to the
    # nature of the flexibility of the Align node.
    def align(n)
      case n
      when NilClass
        self
      when String
        indent(StringAlignPart.new(n))
      else
        indent(n < 0 ? DedentPart : NumberAlignPart.new(n))
      end
    end

    def indent(part = IndentPart)
      next_value = genspace.call(0)
      next_length = 0
      next_queue = (part == DedentPart ? queue[0...-1] : [*queue, part])

      last_spaces = 0

      add_spaces = ->(count) {
        next_value << genspace.call(count)
        next_length += count
      }

      flush_spaces = -> {
        add_spaces[last_spaces] if last_spaces > 0
        last_spaces = 0
      }

      next_queue.each do |part|
        case part
        when IndentPart
          flush_spaces.call
          add_spaces.call(2)
        when StringAlignPart
          flush_spaces.call
          next_value += part.n
          next_length += part.n.length
        when NumberAlignPart
          last_spaces += part.n
        end
      end

      flush_spaces.call

      IndentLevel.new(
        genspace: genspace,
        value: next_value,
        length: next_length,
        queue: next_queue,
        root: root
      )
    end
  end

  # This is a visitor that can be passed to PrettyPrint.visit that will
  # propagate BreakParent nodes all of the way up the tree. When a BreakParent
  # is encountered, it will break the surrounding group, and then that group
  # will break its parent, and so on.
  class PropagateBreaksVisitor
    attr_reader :groups, :visited

    def initialize
      @groups = []
      @visited = []
    end

    def on_enter(doc)
      case doc
      when BreakParent
        groups.last&.break
      when Group
        groups << doc
        return false if visited.include?(doc)

        visited << doc
      end

      true
    end

    def on_exit(doc)
      groups.last&.break if doc.is_a?(Group) && groups.pop.break?
    end
  end

  # When printing, you can optionally specify the value that should be used
  # whenever a group needs to be broken onto multiple lines. In this case the
  # default is \n.
  DEFAULT_NEWLINE = "\n"

  # When generating spaces after a newline for indentation, by default we
  # generate one space per character needed for indentation. You can change this
  # behavior (for instance to use tabs) by passing a different genspace
  # procedure.
  DEFAULT_GENSPACE = ->(n) { ' ' * n }

  # There are two modes in printing, break and flat. When we're in break mode,
  # any lines will use their newline, any if-breaks will use their break
  # contents, etc.
  MODE_BREAK = 1

  # This is another print mode much like MODE_BREAK. When we're in flat mode, we
  # attempt to print everything on one line until we either hit a broken group,
  # a forced line, or the maximum width.
  MODE_FLAT = 2

  # This is a convenience method which is same as follows:
  #
  #   begin
  #     q = PrettyPrint.new(output, maxwidth, newline, &genspace)
  #     ...
  #     q.flush
  #     output
  #   end
  #
  def self.format(output = ''.dup, maxwidth = 80, newline = DEFAULT_NEWLINE, genspace = DEFAULT_GENSPACE)
    q = new(output, maxwidth, newline, &genspace)
    yield q
    q.flush
    output
  end

  # This is similar to PrettyPrint::format but the result has no breaks.
  #
  # +maxwidth+, +newline+ and +genspace+ are ignored.
  #
  # The invocation of +breakable+ in the block doesn't break a line and is
  # treated as just an invocation of +text+.
  #
  def self.singleline_format(output = ''.dup, maxwidth = nil, newline = nil, genspace = nil)
    q = SingleLine.new(output)
    yield q
    output
  end

  # This method provides a way to walk through the print tree with a specified
  # +visitor+ object. +visitor+ should respond to both #on_enter(doc) and
  # #on_exit(doc).
  def self.visit(doc, visitor)
    marker = Object.new
    stack = [doc]

    while stack.any?
      doc = stack.pop

      if doc == marker
        visitor.on_exit(stack.pop)
        next
      end

      stack += [doc, marker]

      if visitor.on_enter(doc)
        case doc
        when Array
          doc.reverse_each { |part| stack << part }
        when IfBreak
          stack << doc.break_contents if doc.break_contents
          stack << doc.flat_contents if doc.flat_contents
        when Align, Indent, Group, LineSuffix
          stack << doc.contents
        end
      end
    end
  end

  # The output object. It represents the final destination of the contents of
  # the print tree. Its type is one of the classes in the Buffer module. Those
  # classes all wrap an object that should respond to <<.
  #
  # This defaults to Buffer::StringBuffer.new('')
  attr_reader :output

  # The maximum width of a line, before it is separated in to a newline
  #
  # This defaults to 80, and should be an Integer
  attr_reader :maxwidth

  # The value that is appended to +output+ to add a new line.
  #
  # This defaults to "\n", and should be String
  attr_reader :newline

  # An object that responds to call that takes one argument, of an Integer, and
  # returns the corresponding number of spaces.
  #
  # By default this is: ->(n) { ' ' * n }
  attr_reader :genspace

  # The stack of groups that are being printed.
  attr_reader :groups

  # The current array of contents that calls to methods that generate print tree
  # nodes will append to.
  attr_reader :target

  # Creates a buffer for pretty printing.
  #
  # +output+ is an output target. If it is not specified, '' is assumed. It
  # should have a << method which accepts the first argument +obj+ of
  # PrettyPrint#text, the first argument +separator+ of PrettyPrint#breakable,
  # the first argument +newline+ of PrettyPrint.new, and the result of a given
  # block for PrettyPrint.new.
  #
  # +maxwidth+ specifies maximum line length. If it is not specified, 80 is
  # assumed. However actual outputs may overflow +maxwidth+ if long
  # non-breakable texts are provided.
  #
  # +newline+ is used for line breaks. "\n" is used if it is not specified.
  #
  # The block is used to generate spaces. ->(n) { ' ' * n } is used if it is not
  # given.
  def initialize(output = ''.dup, maxwidth = 80, newline = DEFAULT_NEWLINE, &genspace)
    @output = Buffer.for(output)
    @maxwidth = maxwidth
    @newline = newline
    @genspace = genspace || DEFAULT_GENSPACE
    reset
  end

  # Returns the group most recently added to the stack.
  #
  # Contrived example:
  #   out = ""
  #   => ""
  #   q = PrettyPrint.new(out)
  #   => #<PrettyPrint:0x0>
  #   q.group {
  #     q.text q.current_group.inspect
  #     q.text q.newline
  #     q.group(q.current_group.depth + 1) {
  #       q.text q.current_group.inspect
  #       q.text q.newline
  #       q.group(q.current_group.depth + 1) {
  #         q.text q.current_group.inspect
  #         q.text q.newline
  #         q.group(q.current_group.depth + 1) {
  #           q.text q.current_group.inspect
  #           q.text q.newline
  #         }
  #       }
  #     }
  #   }
  #   => 284
  #    puts out
  #   #<PrettyPrint::Group:0x0 @depth=1>
  #   #<PrettyPrint::Group:0x0 @depth=2>
  #   #<PrettyPrint::Group:0x0 @depth=3>
  #   #<PrettyPrint::Group:0x0 @depth=4>
  def current_group
    groups.last
  end

  # Flushes all of the generated print tree onto the output buffer, then clears
  # the generated tree from memory.
  def flush
    # First, ensure that we've propagated all of the necessary break-parent
    # nodes throughout the tree.
    doc = groups.first
    PrettyPrint.visit(doc, PropagateBreaksVisitor.new)

    # This represents how far along the current line we are. It gets reset
    # back to 0 when we encounter a newline.
    position = 0

    # This is our command stack. A command consists of a triplet of an
    # indentation level, the mode (break or flat), and a doc node.
    commands = [[IndentLevel.new(genspace: genspace), MODE_BREAK, doc]]

    # This is a small optimization boolean. It keeps track of whether or not
    # when we hit a group node we should check if it fits on the same line.
    should_remeasure = false

    # This is a separate command stack that includes the same kind of triplets
    # as the commands variable. It is used to keep track of things that should
    # go at the end of printed lines once the other doc nodes are
    # accounted for. Typically this is used to implement comments.
    line_suffixes = []

    # This is a linear stack instead of a mutually recursive call defined on
    # the individual doc nodes for efficiency.
    while commands.any?
      indent, mode, doc = commands.pop

      case doc
      when Text
        doc.objects.each { |object| output << object }
        position += doc.width
      when Array
        doc.reverse_each { |part| commands << [indent, mode, part] }
      when Indent
        commands << [indent.indent, mode, doc.contents]
      when Align
        commands << [indent.align(doc.indent), mode, doc.contents]
      when Trim
        position -= output.trim!
      when Group
        if mode == MODE_FLAT && !should_remeasure
          commands << [indent, doc.break? ? MODE_BREAK : MODE_FLAT, doc.contents]
        else
          should_remeasure = false
          next_cmd = [indent, MODE_FLAT, doc.contents]

          if !doc.break? && fits?(next_cmd, commands, maxwidth - position)
            commands << next_cmd
          else
            commands << [indent, MODE_BREAK, doc.contents]
          end
        end
      when IfBreak
        if mode == MODE_BREAK
          commands << [indent, mode, doc.break_contents] if doc.break_contents
        elsif mode == MODE_FLAT
          commands << [indent, mode, doc.flat_contents] if doc.flat_contents
        end
      when LineSuffix
        line_suffixes << [indent, mode, doc.contents]
      when Breakable
        if mode == MODE_FLAT
          if doc.force?
            should_remeasure = true
          else
            output << doc.separator
            position += doc.width
            next
          end
        end

        if line_suffixes.any?
          commands << [indent, mode, doc]
          commands += line_suffixes.reverse
          line_suffixes = []
        elsif !doc.indent?
          output << newline

          if indent.root
            output << indent.root.value
            position = indent.root.length
          else
            position = 0
          end
        else
          position -= output.trim!
          output << newline
          output << indent.value
          position = indent.length
        end
      when BreakParent
        # do nothing
      else
        # Special case where the user has defined some way to get an extra doc
        # node that we don't explicitly support into the list. In this case
        # we're going to assume it's 0-width and just append it to the output
        # buffer.
        #
        # This is useful behavior for putting marker nodes into the list so that
        # you can know how things are getting mapped before they get printed.
        output << doc
      end

      if commands.empty? && line_suffixes.any?
        commands += line_suffixes.reverse
        line_suffixes = []
      end
    end

    # Reset the group stack and target array so that this pretty printer object
    # can continue to be used before calling flush again if desired.
    reset
  end

  # ----------------------------------------------------------------------------
  # Markers node builders
  # ----------------------------------------------------------------------------

  # This says "you can break a line here if necessary", and a +width+\-column
  # text +separator+ is inserted if a line is not broken at the point.
  #
  # If +separator+ is not specified, ' ' is used.
  #
  # If +width+ is not specified, +separator.length+ is used. You will have to
  # specify this when +separator+ is a multibyte character, for example.
  #
  # By default, if the surrounding group is broken and a newline is inserted,
  # the printer will indent the subsequent line up to the current level of
  # indentation. You can disable this behavior with the +indent+ argument if
  # that's not desired (rare).
  #
  # By default, when you insert a Breakable into the print tree, it only breaks
  # the surrounding group when the group's contents cannot fit onto the
  # remaining space of the current line. You can force it to break the
  # surrounding group instead if you always want the newline with the +force+
  # argument.
  def breakable(separator = ' ', width = separator.length, indent: true, force: false)
    doc = Breakable.new(separator, width, indent: indent, force: force)

    target << doc
    break_parent if force

    doc
  end

  # This inserts a BreakParent node into the print tree which forces the
  # surrounding and all parent group nodes to break.
  def break_parent
    doc = BreakParent.new
    target << doc

    doc
  end

  # This is similar to #breakable except the decision to break or not is
  # determined individually.
  #
  # Two #fill_breakable under a group may cause 4 results:
  # (break,break), (break,non-break), (non-break,break), (non-break,non-break).
  # This is different to #breakable because two #breakable under a group
  # may cause 2 results: (break,break), (non-break,non-break).
  #
  # The text +separator+ is inserted if a line is not broken at this point.
  #
  # If +separator+ is not specified, ' ' is used.
  #
  # If +width+ is not specified, +separator.length+ is used. You will have to
  # specify this when +separator+ is a multibyte character, for example.
  def fill_breakable(separator = ' ', width = separator.length)
    group { breakable(separator, width) }
  end

  # This inserts a Trim node into the print tree which, when printed, will clear
  # all whitespace at the end of the output buffer. This is useful for the rare
  # case where you need to delete printed indentation and force the next node
  # to start at the beginning of the line.
  def trim
    doc = Trim.new
    target << doc

    doc
  end

  # ----------------------------------------------------------------------------
  # Container node builders
  # ----------------------------------------------------------------------------

  # Groups line break hints added in the block. The line break hints are all to
  # be used or not.
  #
  # If +indent+ is specified, the method call is regarded as nested by
  # nest(indent) { ... }.
  #
  # If +open_object+ is specified, <tt>text(open_object, open_width)</tt> is
  # called before grouping. If +close_object+ is specified,
  # <tt>text(close_object, close_width)</tt> is called after grouping.
  def group(indent = 0, open_object = '', close_object = '', open_width = open_object.length, close_width = close_object.length)
    text(open_object, open_width) if open_object != ''

    doc = Group.new(groups.last.depth + 1)
    groups << doc
    target << doc

    with_target(doc.contents) do
      if indent != 0
        nest(indent) { yield }
      else
        yield
      end
    end

    groups.pop
    text(close_object, close_width) if close_object != ''
  end

  # A small DSL-like object used for specifying the alternative contents to be
  # printed if the surrounding group doesn't break for an IfBreak node.
  class IfBreakBuilder
    attr_reader :builder, :if_break

    def initialize(builder, if_break)
      @builder = builder
      @if_break = if_break
    end

    def if_flat(&block)
      builder.with_target(if_break.flat_contents, &block)
    end
  end

  # Inserts an IfBreak node with the contents of the block being added to its
  # list of nodes that should be printed if the surrounding node breaks. If it
  # doesn't, then you can specify the contents to be printed with the #if_flat
  # method used on the return object from this method. For example,
  #
  #     q.if_break { q.text('do') }.if_flat { q.text('{') }
  #
  # In the example above, if the surrounding group is broken it will print 'do'
  # and if it is not it will print '{'.
  def if_break
    doc = IfBreak.new
    target << doc

    with_target(doc.break_contents) { yield }
    IfBreakBuilder.new(self, doc)
  end

  # Very similar to the #nest method, this indents the nested content by one
  # level by inserting an Indent node into the print tree. The contents of the
  # node are determined by the block.
  def indent
    doc = Indent.new
    target << doc

    with_target(doc.contents) { yield }
    doc
  end

  # Inserts a LineSuffix node into the print tree. The contents of the node are
  # determined by the block.
  def line_suffix
    doc = LineSuffix.new
    target << doc

    with_target(doc.contents) { yield }
    doc
  end

  # Increases left margin after newline with +indent+ for line breaks added in
  # the block.
  def nest(indent)
    doc = Align.new(indent: indent)
    target << doc

    with_target(doc.contents) { yield }
    doc
  end

  # This adds +object+ as a text of +width+ columns in width.
  #
  # If +width+ is not specified, object.length is used.
  def text(object = '', width = object.length)
    doc = target.last

    unless Text === doc
      doc = Text.new
      target << doc
    end

    doc.add(object: object, width: width)
    doc
  end

  # ----------------------------------------------------------------------------
  # Internal APIs
  # ----------------------------------------------------------------------------

  # A convenience method used by a lot of the print tree node builders that
  # temporarily changes the target that the builders will append to.
  def with_target(target)
    previous_target, @target = @target, target
    yield
    @target = previous_target
  end

  private

  # This method returns a boolean as to whether or not the remaining commands
  # fit onto the remaining space on the current line. If we finish printing
  # all of the commands or if we hit a newline, then we return true. Otherwise
  # if we continue printing past the remaining space, we return false.
  def fits?(next_command, rest_commands, remaining)
    # This is the index in the remaining commands that we've handled so far.
    # We reverse through the commands and add them to the stack if we've run
    # out of nodes to handle.
    rest_index = rest_commands.length

    # This is our stack of commands, very similar to the commands list in the
    # print method.
    commands = [next_command]

    # This is our output buffer, really only necessary to keep track of
    # because we could encounter a Trim doc node that would actually add
    # remaining space.
    buffer = output.class.new

    while remaining >= 0
      if commands.empty?
        return true if rest_index == 0

        rest_index -= 1
        commands << rest_commands[rest_index]
        next
      end

      indent, mode, doc = commands.pop

      case doc
      when Text
        doc.objects.each { |object| buffer << object }
        remaining -= doc.width
      when Array
        doc.reverse_each { |part| commands << [indent, mode, part] }
      when Indent
        commands << [indent.indent, mode, doc.contents]
      when Align
        commands << [indent.align(doc.indent), mode, doc.contents]
      when Trim
        remaining += buffer.trim!
      when Group
        commands << [indent, doc.break? ? MODE_BREAK : mode, doc.contents]
      when IfBreak
        if mode == MODE_BREAK
          commands << [indent, mode, doc.break_contents] if doc.break_contents
        else
          commands << [indent, mode, doc.flat_contents] if doc.flat_contents
        end
      when Breakable
        if mode == MODE_FLAT
          if !doc.force?
            buffer << doc.separator
            remaining -= doc.width
            next
          end
        end

        return true
      end
    end

    false
  end

  # Resets the group stack and target array so that this pretty printer object
  # can continue to be used before calling flush again if desired.
  def reset
    @groups = [Group.new(0)]
    @target = @groups.last.contents
  end
end
