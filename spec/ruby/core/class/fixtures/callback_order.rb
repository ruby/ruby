module CoreClassSpecs
  module Callbacks
    class Base
      def self.inherited(subclass)
        subclass.const_set(:INHERITED_NAME, subclass.name)
        ORDER << [
          :inherited,
          subclass,
          eval("defined?(#{subclass.name})"),
          Object.const_source_location(subclass.name) ? :location : :unknown_location,
        ]
        super
      end
    end

    ORDER = []

    def self.const_added(const_name)
      ORDER << [
        :const_added,
        const_name,
        eval("defined?(#{const_name})"),
        const_source_location(const_name) ? :location : :unknown_location,
      ]
      super
    end

    class Child < Base
    end
  end
end
