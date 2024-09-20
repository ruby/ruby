require_relative '../../spec_helper'

describe "FrozenError.new" do
  it "should take optional receiver argument" do
    o = Object.new
    FrozenError.new("msg", receiver: o).receiver.should equal(o)
  end
end

describe "FrozenError#receiver" do
  it "should return frozen object that modification was attempted on" do
    o = Object.new.freeze
    begin
      def o.x; end
    rescue => e
      e.should be_kind_of(FrozenError)
      e.receiver.should equal(o)
    else
      raise
    end
  end
end

describe "Modifying a frozen object" do
  context "#inspect is redefined and modifies the object" do
    it "returns ... instead of String representation of object" do
      object = Object.new
      def object.inspect; @a = 1 end
      def object.modify; @a = 2 end

      object.freeze

      # CRuby's message contains multiple whitespaces before '...'.
      # So handle both multiple and single whitespace.
      -> { object.modify }.should raise_error(FrozenError, /can't modify frozen .*?: \s*.../)
    end
  end
end
