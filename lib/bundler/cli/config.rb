# frozen_string_literal: true
module Bundler
  class CLI::Config
    attr_reader :name, :options, :scope, :thor
    attr_accessor :args

    def initialize(options, args, thor)
      @options = options
      @args = args
      @thor = thor
      @name = peek = args.shift
      @scope = "global"
      return unless peek && peek.start_with?("--")
      @name = args.shift
      @scope = peek[2..-1]
    end

    def run
      unless name
        confirm_all
        return
      end

      unless valid_scope?(scope)
        Bundler.ui.error "Invalid scope --#{scope} given. Please use --local or --global."
        exit 1
      end

      if scope == "delete"
        Bundler.settings.set_local(name, nil)
        Bundler.settings.set_global(name, nil)
        return
      end

      if args.empty?
        if options[:parseable]
          if value = Bundler.settings[name]
            Bundler.ui.info("#{name}=#{value}")
          end
          return
        end

        confirm(name)
        return
      end

      Bundler.ui.info(message) if message
      Bundler.settings.send("set_#{scope}", name, new_value)
    end

  private

    def confirm_all
      if @options[:parseable]
        thor.with_padding do
          Bundler.settings.all.each do |setting|
            val = Bundler.settings[setting]
            Bundler.ui.info "#{setting}=#{val}"
          end
        end
      else
        Bundler.ui.confirm "Settings are listed in order of priority. The top value will be used.\n"
        Bundler.settings.all.each do |setting|
          Bundler.ui.confirm "#{setting}"
          show_pretty_values_for(setting)
          Bundler.ui.confirm ""
        end
      end
    end

    def confirm(name)
      Bundler.ui.confirm "Settings for `#{name}` in order of priority. The top value will be used"
      show_pretty_values_for(name)
    end

    def new_value
      pathname = Pathname.new(args.join(" "))
      if name.start_with?("local.") && pathname.directory?
        pathname.expand_path.to_s
      else
        args.join(" ")
      end
    end

    def message
      locations = Bundler.settings.locations(name)
      if @options[:parseable]
        "#{name}=#{new_value}" if new_value
      elsif scope == "global"
        if locations[:local]
          "Your application has set #{name} to #{locations[:local].inspect}. " \
            "This will override the global value you are currently setting"
        elsif locations[:env]
          "You have a bundler environment variable for #{name} set to " \
            "#{locations[:env].inspect}. This will take precedence over the global value you are setting"
        elsif locations[:global] && locations[:global] != args.join(" ")
          "You are replacing the current global value of #{name}, which is currently " \
            "#{locations[:global].inspect}"
        end
      elsif scope == "local" && locations[:local] != args.join(" ")
        "You are replacing the current local value of #{name}, which is currently " \
          "#{locations[:local].inspect}"
      end
    end

    def show_pretty_values_for(setting)
      thor.with_padding do
        Bundler.settings.pretty_values_for(setting).each do |line|
          Bundler.ui.info line
        end
      end
    end

    def valid_scope?(scope)
      %w(delete local global).include?(scope)
    end
  end
end
