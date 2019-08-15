require 'mspec/guards/version'

# This helper makes it easy to write version independent
# specs for frozen objects.
unless respond_to? :frozen_error_class, true
  ruby_version_is "2.5" do
    def frozen_error_class
      FrozenError
    end
  end

  ruby_version_is ""..."2.5" do
    def frozen_error_class
      RuntimeError
    end
  end
end
