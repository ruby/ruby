module DataSpecs
  if Data.respond_to?(:define)
    Measure = Data.define(:amount, :unit)

    class MeasureWithOverriddenName < Measure
      def self.name
        "A"
      end
    end

    class DataSubclass < Data; end

    MeasureSubclass = Class.new(Measure) do
      def initialize(amount:, unit:)
        super
      end
    end

    Empty = Data.define()

    DataWithOverriddenInitialize = Data.define(:amount, :unit) do
      def initialize(*rest, **kw)
        super
        ScratchPad.record [:initialize, rest, kw]
      end
    end

    Area = Data.define(:width, :height, :area) do
      def initialize(width:, height:)
        super(width: width, height: height, area: width * height)
      end
    end
  end
end
