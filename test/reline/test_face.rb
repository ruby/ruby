# frozen_string_literal: true

require_relative 'helper'

class Reline::Face::Test < Reline::TestCase
  RESET_SGR = "\e[0m"

  def setup
    @colorterm_backup = ENV['COLORTERM']
    ENV['COLORTERM'] = 'truecolor'
  end

  def teardown
    Reline::Face.reset_to_initial_configs
    ENV['COLORTERM'] = @colorterm_backup
  end

  class WithInsufficientSetupTest < self
    def setup
      super
      Reline::Face.config(:my_insufficient_config) do |face|
      end
      @face = Reline::Face[:my_insufficient_config]
    end

    def test_my_insufficient_config_line
      assert_equal RESET_SGR, @face[:default]
      assert_equal RESET_SGR, @face[:enhanced]
      assert_equal RESET_SGR, @face[:scrollbar]
    end

    def test_my_insufficient_configs
      my_configs = Reline::Face.configs[:my_insufficient_config]
      assert_equal(
        {
          default: { style: :reset, escape_sequence: RESET_SGR },
          enhanced: { style: :reset, escape_sequence: RESET_SGR },
          scrollbar: { style: :reset, escape_sequence: RESET_SGR }
        },
        my_configs
      )
    end
  end

  class WithSetupTest < self
    def setup
      super
      Reline::Face.config(:my_config) do |face|
        face.define :default, foreground: :blue
        face.define :enhanced, foreground: "#FF1020", background: :black, style: [:bold, :underlined]
      end
      Reline::Face.config(:another_config) do |face|
        face.define :another_label, foreground: :red
      end
      @face = Reline::Face[:my_config]
    end

    def test_now_there_are_four_configs
      assert_equal %i(default completion_dialog my_config another_config), Reline::Face.configs.keys
    end

    def test_resetting_config_discards_user_defined_configs
      Reline::Face.reset_to_initial_configs
      assert_equal %i(default completion_dialog), Reline::Face.configs.keys
    end

    def test_my_configs
      my_configs = Reline::Face.configs[:my_config]
      assert_equal(
        {
          default: {
            escape_sequence: "#{RESET_SGR}\e[34m", foreground: :blue
          },
          enhanced: {
            background: :black,
            foreground: "#FF1020",
            style: [:bold, :underlined],
            escape_sequence: "\e[0m\e[38;2;255;16;32;40;1;4m"
          },
          scrollbar: {
            style: :reset,
            escape_sequence: "\e[0m"
          }
        },
        my_configs
      )
    end

    def test_my_config_line
      assert_equal "#{RESET_SGR}\e[34m", @face[:default]
    end

    def test_my_config_enhanced
      assert_equal "#{RESET_SGR}\e[38;2;255;16;32;40;1;4m", @face[:enhanced]
    end

    def test_not_respond_to_another_label
      assert_equal false, @face.respond_to?(:another_label)
    end
  end

  class WithoutSetupTest < self
    def test_my_config_default
      Reline::Face.config(:my_config) do |face|
        # do nothing
      end
      face = Reline::Face[:my_config]
      assert_equal RESET_SGR, face[:default]
    end

    def test_style_does_not_exist
      face = Reline::Face[:default]
      assert_raise ArgumentError do
        face[:style_does_not_exist]
      end
    end

    def test_invalid_keyword
      assert_raise ArgumentError do
        Reline::Face.config(:invalid_config) do |face|
          face.define :default, invalid_keyword: :red
        end
      end
    end

    def test_invalid_foreground_name
      assert_raise ArgumentError do
        Reline::Face.config(:invalid_config) do |face|
          face.define :default, foreground: :invalid_name
        end
      end
    end

    def test_invalid_background_name
      assert_raise ArgumentError do
        Reline::Face.config(:invalid_config) do |face|
          face.define :default, background: :invalid_name
        end
      end
    end

    def test_invalid_style_name
      assert_raise ArgumentError do
        Reline::Face.config(:invalid_config) do |face|
          face.define :default, style: :invalid_name
        end
      end
    end

    def test_private_constants
      [:SGR_PARAMETER, :Config, :CONFIGS].each do |name|
        assert_equal false, Reline::Face.constants.include?(name)
      end
    end
  end

  class ConfigTest < self
    def setup
      super
      @config = Reline::Face.const_get(:Config).new(:my_config) { }
    end

    def teardown
      super
      Reline::Face.instance_variable_set(:@force_truecolor, nil)
    end

    def test_rgb?
      assert_equal true, @config.send(:rgb_expression?, "#FFFFFF")
    end

    def test_invalid_rgb?
      assert_equal false, @config.send(:rgb_expression?, "FFFFFF")
      assert_equal false, @config.send(:rgb_expression?, "#FFFFF")
    end

    def test_format_to_sgr_preserves_order
      assert_equal(
        "#{RESET_SGR}\e[37;41;1;3m",
        @config.send(:format_to_sgr, foreground: :white, background: :red, style: [:bold, :italicized])
      )

      assert_equal(
        "#{RESET_SGR}\e[37;1;3;41m",
        @config.send(:format_to_sgr, foreground: :white, style: [:bold, :italicized], background: :red)
      )
    end

    def test_format_to_sgr_with_reset
      assert_equal(
        RESET_SGR,
        @config.send(:format_to_sgr, style: :reset)
      )
      assert_equal(
        "#{RESET_SGR}\e[37;0;41m",
        @config.send(:format_to_sgr, foreground: :white, style: :reset, background: :red)
      )
    end

    def test_format_to_sgr_with_single_style
      assert_equal(
        "#{RESET_SGR}\e[37;41;1m",
        @config.send(:format_to_sgr, foreground: :white, background: :red, style: :bold)
      )
    end

    def test_truecolor
      ENV['COLORTERM'] = 'truecolor'
      assert_equal true, Reline::Face.truecolor?
      ENV['COLORTERM'] = '24bit'
      assert_equal true, Reline::Face.truecolor?
      ENV['COLORTERM'] = nil
      assert_equal false, Reline::Face.truecolor?
      Reline::Face.force_truecolor
      assert_equal true, Reline::Face.truecolor?
    end

    def test_sgr_rgb_truecolor
      ENV['COLORTERM'] = 'truecolor'
      assert_equal "38;2;255;255;255", @config.send(:sgr_rgb, :foreground, "#ffffff")
      assert_equal "48;2;18;52;86", @config.send(:sgr_rgb, :background, "#123456")
    end

    def test_sgr_rgb_256color
      ENV['COLORTERM'] = nil
      assert_equal '38;5;231', @config.send(:sgr_rgb, :foreground, '#ffffff')
      assert_equal '48;5;16', @config.send(:sgr_rgb, :background, '#000000')
      # Color steps are [0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff]
      assert_equal '38;5;24', @config.send(:sgr_rgb, :foreground, '#005f87')
      assert_equal '38;5;67', @config.send(:sgr_rgb, :foreground, '#5f87af')
      assert_equal '48;5;110', @config.send(:sgr_rgb, :background, '#87afd7')
      assert_equal '48;5;153', @config.send(:sgr_rgb, :background, '#afd7ff')
      # Boundary values are [0x30, 0x73, 0x9b, 0xc3, 0xeb]
      assert_equal '38;5;24', @config.send(:sgr_rgb, :foreground, '#2f729a')
      assert_equal '38;5;67', @config.send(:sgr_rgb, :foreground, '#30739b')
      assert_equal '48;5;110', @config.send(:sgr_rgb, :background, '#9ac2ea')
      assert_equal '48;5;153', @config.send(:sgr_rgb, :background, '#9bc3eb')
    end

    def test_force_truecolor_reconfigure
      ENV['COLORTERM'] = nil

      Reline::Face.config(:my_config) do |face|
        face.define :default, foreground: '#005f87'
        face.define :enhanced, background: '#afd7ff'
      end

      assert_equal "\e[0m\e[38;5;24m", Reline::Face[:my_config][:default]
      assert_equal "\e[0m\e[48;5;153m", Reline::Face[:my_config][:enhanced]

      Reline::Face.force_truecolor

      assert_equal "\e[0m\e[38;2;0;95;135m", Reline::Face[:my_config][:default]
      assert_equal "\e[0m\e[48;2;175;215;255m", Reline::Face[:my_config][:enhanced]
    end
  end
end
