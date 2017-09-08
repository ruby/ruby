require "bundler/vendor/thor/lib/thor/shell/basic"

class Bundler::Thor
  module Shell
    # Inherit from Bundler::Thor::Shell::Basic and add set_color behavior. Check
    # Bundler::Thor::Shell::Basic to see all available methods.
    #
    class Color < Basic
      # Embed in a String to clear all previous ANSI sequences.
      CLEAR      = "\e[0m"
      # The start of an ANSI bold sequence.
      BOLD       = "\e[1m"

      # Set the terminal's foreground ANSI color to black.
      BLACK      = "\e[30m"
      # Set the terminal's foreground ANSI color to red.
      RED        = "\e[31m"
      # Set the terminal's foreground ANSI color to green.
      GREEN      = "\e[32m"
      # Set the terminal's foreground ANSI color to yellow.
      YELLOW     = "\e[33m"
      # Set the terminal's foreground ANSI color to blue.
      BLUE       = "\e[34m"
      # Set the terminal's foreground ANSI color to magenta.
      MAGENTA    = "\e[35m"
      # Set the terminal's foreground ANSI color to cyan.
      CYAN       = "\e[36m"
      # Set the terminal's foreground ANSI color to white.
      WHITE      = "\e[37m"

      # Set the terminal's background ANSI color to black.
      ON_BLACK   = "\e[40m"
      # Set the terminal's background ANSI color to red.
      ON_RED     = "\e[41m"
      # Set the terminal's background ANSI color to green.
      ON_GREEN   = "\e[42m"
      # Set the terminal's background ANSI color to yellow.
      ON_YELLOW  = "\e[43m"
      # Set the terminal's background ANSI color to blue.
      ON_BLUE    = "\e[44m"
      # Set the terminal's background ANSI color to magenta.
      ON_MAGENTA = "\e[45m"
      # Set the terminal's background ANSI color to cyan.
      ON_CYAN    = "\e[46m"
      # Set the terminal's background ANSI color to white.
      ON_WHITE   = "\e[47m"

      # Set color by using a string or one of the defined constants. If a third
      # option is set to true, it also adds bold to the string. This is based
      # on Highline implementation and it automatically appends CLEAR to the end
      # of the returned String.
      #
      # Pass foreground, background and bold options to this method as
      # symbols.
      #
      # Example:
      #
      #   set_color "Hi!", :red, :on_white, :bold
      #
      # The available colors are:
      #
      #   :bold
      #   :black
      #   :red
      #   :green
      #   :yellow
      #   :blue
      #   :magenta
      #   :cyan
      #   :white
      #   :on_black
      #   :on_red
      #   :on_green
      #   :on_yellow
      #   :on_blue
      #   :on_magenta
      #   :on_cyan
      #   :on_white
      def set_color(string, *colors)
        if colors.compact.empty? || !can_display_colors?
          string
        elsif colors.all? { |color| color.is_a?(Symbol) || color.is_a?(String) }
          ansi_colors = colors.map { |color| lookup_color(color) }
          "#{ansi_colors.join}#{string}#{CLEAR}"
        else
          # The old API was `set_color(color, bold=boolean)`. We
          # continue to support the old API because you should never
          # break old APIs unnecessarily :P
          foreground, bold = colors
          foreground = self.class.const_get(foreground.to_s.upcase) if foreground.is_a?(Symbol)

          bold       = bold ? BOLD : ""
          "#{bold}#{foreground}#{string}#{CLEAR}"
        end
      end

    protected

      def can_display_colors?
        stdout.tty?
      end

      # Overwrite show_diff to show diff with colors if Diff::LCS is
      # available.
      #
      def show_diff(destination, content) #:nodoc:
        if diff_lcs_loaded? && ENV["THOR_DIFF"].nil? && ENV["RAILS_DIFF"].nil?
          actual  = File.binread(destination).to_s.split("\n")
          content = content.to_s.split("\n")

          Diff::LCS.sdiff(actual, content).each do |diff|
            output_diff_line(diff)
          end
        else
          super
        end
      end

      def output_diff_line(diff) #:nodoc:
        case diff.action
        when "-"
          say "- #{diff.old_element.chomp}", :red, true
        when "+"
          say "+ #{diff.new_element.chomp}", :green, true
        when "!"
          say "- #{diff.old_element.chomp}", :red, true
          say "+ #{diff.new_element.chomp}", :green, true
        else
          say "  #{diff.old_element.chomp}", nil, true
        end
      end

      # Check if Diff::LCS is loaded. If it is, use it to create pretty output
      # for diff.
      #
      def diff_lcs_loaded? #:nodoc:
        return true  if defined?(Diff::LCS)
        return @diff_lcs_loaded unless @diff_lcs_loaded.nil?

        @diff_lcs_loaded = begin
          require "diff/lcs"
          true
        rescue LoadError
          false
        end
      end
    end
  end
end
