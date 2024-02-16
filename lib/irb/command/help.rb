# frozen_string_literal: true

require_relative "show_cmds"

module IRB
  module Command
    class Help < ShowCmds
      category "IRB"
      description "List all available commands and their description."
    end
  end
end
