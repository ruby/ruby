module IRB
  module HelperMethod
    class Base
      class << self
        def description(description = nil)
          @description = description if description
          @description
        end
      end
    end
  end
end
