# frozen_string_literal: true

module Spec
  module Options
    def opt_add(option, options)
      [option.strip, options].compact.reject(&:empty?).join(" ")
    end

    def opt_remove(option, options)
      return unless options

      options.split(" ").reject {|opt| opt.strip == option.strip }.join(" ")
    end
  end
end
