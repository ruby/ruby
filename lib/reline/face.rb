# frozen_string_literal: true

class Reline::Face
  SGR_PARAMETERS = {
    foreground: {
      black: 30,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      white: 37,
      bright_black: 90,
      gray: 90,
      bright_red: 91,
      bright_green: 92,
      bright_yellow: 93,
      bright_blue: 94,
      bright_magenta: 95,
      bright_cyan: 96,
      bright_white: 97
    },
    background: {
      black: 40,
      red: 41,
      green: 42,
      yellow: 43,
      blue: 44,
      magenta: 45,
      cyan: 46,
      white: 47,
      bright_black: 100,
      gray: 100,
      bright_red: 101,
      bright_green: 102,
      bright_yellow: 103,
      bright_blue: 104,
      bright_magenta: 105,
      bright_cyan: 106,
      bright_white: 107,
    },
    style: {
      reset: 0,
      bold: 1,
      faint: 2,
      italicized: 3,
      underlined: 4,
      slowly_blinking: 5,
      blinking: 5,
      rapidly_blinking: 6,
      negative: 7,
      concealed: 8,
      crossed_out: 9
    }
  }.freeze

  class Config
    ESSENTIAL_DEFINE_NAMES = %i(default enhanced scrollbar).freeze
    RESET_SGR = "\e[0m".freeze

    def initialize(name, &block)
      @definition = {}
      block.call(self)
      ESSENTIAL_DEFINE_NAMES.each do |name|
        @definition[name] ||= { style: :reset, escape_sequence: RESET_SGR }
      end
    end

    attr_reader :definition

    def define(name, **values)
      values[:escape_sequence] = format_to_sgr(values.to_a).freeze
      @definition[name] = values
    end

    def [](name)
      @definition.dig(name, :escape_sequence) or raise ArgumentError, "unknown face: #{name}"
    end

    private

    def sgr_rgb(key, value)
      return nil unless rgb_expression?(value)
      case key
      when :foreground
        "38;2;"
      when :background
        "48;2;"
      end + value[1, 6].scan(/../).map(&:hex).join(";")
    end

    def format_to_sgr(ordered_values)
      sgr = "\e[" + ordered_values.map do |key_value|
        key, value = key_value
        case key
        when :foreground, :background
          case value
          when Symbol
            SGR_PARAMETERS[key][value]
          when String
            sgr_rgb(key, value)
          end
        when :style
          [ value ].flatten.map do |style_name|
            SGR_PARAMETERS[:style][style_name]
          end.then do |sgr_parameters|
            sgr_parameters.include?(nil) ? nil : sgr_parameters
          end
        end.then do |rendition_expression|
          unless rendition_expression
            raise ArgumentError, "invalid SGR parameter: #{value.inspect}"
          end
          rendition_expression
        end
      end.join(';') + "m"
      sgr == RESET_SGR ? RESET_SGR : RESET_SGR + sgr
    end

    def rgb_expression?(color)
      color.respond_to?(:match?) and color.match?(/\A#[0-9a-fA-F]{6}\z/)
    end
  end

  private_constant :SGR_PARAMETERS, :Config

  def self.[](name)
    @configs[name]
  end

  def self.config(name, &block)
    @configs ||= {}
    @configs[name] = Config.new(name, &block)
  end

  def self.configs
    @configs.transform_values(&:definition)
  end

  def self.load_initial_configs
    config(:default) do |conf|
      conf.define :default, style: :reset
      conf.define :enhanced, style: :reset
      conf.define :scrollbar, style: :reset
    end
    config(:completion_dialog) do |conf|
      conf.define :default, foreground: :white, background: :cyan
      conf.define :enhanced, foreground: :white, background: :magenta
      conf.define :scrollbar, foreground: :white, background: :cyan
    end
  end

  def self.reset_to_initial_configs
    @configs = {}
    load_initial_configs
  end
end
