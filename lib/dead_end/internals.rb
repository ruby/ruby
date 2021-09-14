# frozen_string_literal: true
#
# This is the top level file, but is moved to `internals`
# so the top level file can instead enable the "automatic" behavior

require_relative "version"

require 'tmpdir'
require 'stringio'
require 'pathname'
require 'ripper'
require 'timeout'

module DeadEnd
  class Error < StandardError; end
  SEARCH_SOURCE_ON_ERROR_DEFAULT = true
  TIMEOUT_DEFAULT = ENV.fetch("DEAD_END_TIMEOUT", 5).to_i

  def self.handle_error(e, search_source_on_error: SEARCH_SOURCE_ON_ERROR_DEFAULT)
    raise e if !e.message.include?("end-of-input")

    filename = e.message.split(":").first

    $stderr.sync = true
    $stderr.puts "Run `$ dead_end #{filename}` for more options\n"

    if search_source_on_error
      self.call(
        source: Pathname(filename).read,
        filename: filename,
        terminal: true,
      )
    end

    $stderr.puts ""
    $stderr.puts ""
    raise e
  end

  def self.call(source: , filename: , terminal: false, record_dir: nil, timeout: TIMEOUT_DEFAULT, io: $stderr)
    search = nil
    Timeout.timeout(timeout) do
      record_dir ||= ENV["DEBUG"] ? "tmp" : nil
      search = CodeSearch.new(source, record_dir: record_dir).call
    end

    blocks = search.invalid_blocks
    DisplayInvalidBlocks.new(
      blocks: blocks,
      filename: filename,
      terminal: terminal,
      code_lines: search.code_lines,
      invalid_obj: invalid_type(source),
      io: io
    ).call
  rescue Timeout::Error => e
    io.puts "Search timed out DEAD_END_TIMEOUT=#{timeout}, run with DEBUG=1 for more info"
    io.puts e.backtrace.first(3).join($/)
  end

  # Used for counting spaces
  module SpaceCount
    def self.indent(string)
      string.split(/\S/).first&.length || 0
    end
  end

  # This will tell you if the `code_lines` would be valid
  # if you removed the `without_lines`. In short it's a
  # way to detect if we've found the lines with syntax errors
  # in our document yet.
  #
  #   code_lines = [
  #     CodeLine.new(line: "def foo\n",   index: 0)
  #     CodeLine.new(line: "  def bar\n", index: 1)
  #     CodeLine.new(line: "end\n",       index: 2)
  #   ]
  #
  #   DeadEnd.valid_without?(
  #     without_lines: code_lines[1],
  #     code_lines: code_lines
  #   )                                    # => true
  #
  #   DeadEnd.valid?(code_lines) # => false
  def self.valid_without?(without_lines: , code_lines:)
    lines = code_lines - Array(without_lines).flatten

    if lines.empty?
      return true
    else
      return valid?(lines)
    end
  end

  def self.invalid?(source)
    source = source.join if source.is_a?(Array)
    source = source.to_s

    Ripper.new(source).tap(&:parse).error?
  end

  # Returns truthy if a given input source is valid syntax
  #
  #   DeadEnd.valid?(<<~EOM) # => true
  #     def foo
  #     end
  #   EOM
  #
  #   DeadEnd.valid?(<<~EOM) # => false
  #     def foo
  #       def bar # Syntax error here
  #     end
  #   EOM
  #
  # You can also pass in an array of lines and they'll be
  # joined before evaluating
  #
  #   DeadEnd.valid?(
  #     [
  #       "def foo\n",
  #       "end\n"
  #     ]
  #   ) # => true
  #
  #   DeadEnd.valid?(
  #     [
  #       "def foo\n",
  #       "  def bar\n", # Syntax error here
  #       "end\n"
  #     ]
  #   ) # => false
  #
  # As an FYI the CodeLine class instances respond to `to_s`
  # so passing a CodeLine in as an object or as an array
  # will convert it to it's code representation.
  def self.valid?(source)
    !invalid?(source)
  end


  def self.invalid_type(source)
    WhoDisSyntaxError.new(source).call
  end
end

require_relative "code_line"
require_relative "code_block"
require_relative "code_frontier"
require_relative "display_invalid_blocks"
require_relative "around_block_scan"
require_relative "block_expand"
require_relative "parse_blocks_from_indent_line"

require_relative "code_search"
require_relative "who_dis_syntax_error"
require_relative "heredoc_block_parse"
require_relative "lex_all"
require_relative "trailing_slash_join"
