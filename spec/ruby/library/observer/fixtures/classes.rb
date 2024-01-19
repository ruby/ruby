ruby_version_is ""..."3.4" do
  require 'observer'

  class ObserverCallbackSpecs
    attr_reader :value

    def initialize
      @value = nil
    end

    def update(value)
      @value = value
    end
  end

  class ObservableSpecs
    include Observable
  end
end
