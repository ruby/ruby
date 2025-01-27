# frozen_string_literal: true

module Bundler
  class CLI::Console
    attr_reader :options, :group
    def initialize(options, group)
      @options = options
      @group = group
    end

    def run
      group ? Bundler.require(:default, *group.split(" ").map!(&:to_sym)) : Bundler.require
      ARGV.clear

      console = get_console(Bundler.settings[:console] || "irb")
      console.start
    end

    def get_console(name)
      require name
      get_constant(name)
    rescue LoadError
      if name == "irb"
        Bundler.ui.error "#{name} is not available"
        exit 1
      else
        Bundler.ui.error "Couldn't load console #{name}, falling back to irb"
        name = "irb"
        retry
      end
    end

    def get_constant(name)
      const_name = {
        "pry" => :Pry,
        "ripl" => :Ripl,
        "irb" => :IRB,
      }[name]
      Object.const_get(const_name)
    end
  end
end
