require 'bigdecimal'

describe :bigdecimal_clone, shared: true do
  before :each do
    @obj = BigDecimal("1.2345")
  end

  it "returns self" do
    copy = @obj.public_send(@method)

    copy.should equal(@obj)
  end
end
