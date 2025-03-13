module CoreClassSpecs
  module Callbacks
    class Base
      def self.inherited(subclass)
        subclass.const_set(:INHERITED_NAME, subclass.name)
        ORDER << [:inherited, subclass, eval("defined?(#{subclass.name})")]
        super
      end
    end

    ORDER = []

    def self.const_added(const_name)
      ORDER << [:const_added, const_name, eval("defined?(#{const_name})")]
      super
    end

    class Child < Base
    end
  end
end
