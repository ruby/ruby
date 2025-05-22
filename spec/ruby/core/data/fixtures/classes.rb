module DataSpecs
  if Data.respond_to?(:define)
    Measure = Data.define(:amount, :unit)

    class MeasureWithOverriddenName < Measure
      def self.name
        "A"
      end
    end

    class DataSubclass < Data; end
  end
end
