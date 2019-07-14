require 'io/console'
require 'timeout'
require "forwardable"
require 'reline/version'
require 'reline/config'
require 'reline/key_actor'
require 'reline/key_stroke'
require 'reline/line_editor'

module Reline2
  FILENAME_COMPLETION_PROC = nil
  USERNAME_COMPLETION_PROC = nil

  class Core
    Key = Struct.new('Key', :char, :combined_char, :with_meta)
    if RUBY_PLATFORM =~ /mswin|mingw/
      IS_WINDOWS = true
    else
      IS_WINDOWS = false
    end

    CursorPos = Struct.new(:x, :y)

    ATTR_ACCESSOR_NAMES = %i(
      completion_append_character
      basic_word_break_characters
      completer_word_break_characters
      basic_quote_characters
      completer_quote_characters
      filename_quote_characters
      special_prefixes
      completion_case_fold
      completion_proc
      output_modifier_proc
      prompt_proc
      auto_indent_proc
      pre_input_hook
      dig_perfect_match_proc
    ).freeze
    ATTR_ACCESSOR_NAMES.each &method(:attr_accessor)

    def initialize
      @config = Reline::Config.new
      @line_editor = Reline::LineEditor.new(@config)
      @ambiguous_width = nil

      self.basic_word_break_characters = " \t\n`><=;|&{("
      self.completer_word_break_characters = " \t\n`><=;|&{("
      self.basic_quote_characters = '"\''
      self.completer_quote_characters = '"\''
      self.filename_quote_characters = ""
      self.special_prefixes = ""
    end

    def completion_append_character=(val)
      if val.nil?
        @completion_append_character = nil
      elsif val.size == 1
        @completion_append_character = val.encode(Encoding::default_external)
      elsif val.size > 1
        @completion_append_character = val[0].encode(Encoding::default_external)
      else
        @completion_append_character = nil
      end
    end

    def basic_word_break_characters=(v)
      @basic_word_break_characters = v.encode(Encoding::default_external)
    end

    def completer_word_break_characters=(v)
      @completer_word_break_characters = v.encode(Encoding::default_external)
    end

    def basic_quote_characters=(v)
      @basic_quote_characters = v.encode(Encoding::default_external)
    end

    def completer_quote_characters=(v)
      @completer_quote_characters = v.encode(Encoding::default_external)
    end

    def filename_quote_characters=(v)
      @filename_quote_characters = v.encode(Encoding::default_external)
    end

    def special_prefixes=(v)
      @special_prefixes = v.encode(Encoding::default_external)
    end

    def completion_proc=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @completion_proc = p
    end

    def output_modifier_proc=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @output_modifier_proc = p
    end

    def prompt_proc=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @prompt_proc = p
    end

    def auto_indent_proc=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @auto_indent_proc = p
    end

    def pre_input_hook=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @pre_input_hook = p
    end

    def dig_perfect_match_proc=(p)
      raise ArgumentError unless p.is_a?(Proc)
      @dig_perfect_match_proc = p
    end
  end

  extend SingleForwardable

  Core::ATTR_ACCESSOR_NAMES.each { |name|
    def_delegators :core, "#{name}", "#{name}="
  }

  private

  def self.core
    @core ||= Core.new
  end
end
