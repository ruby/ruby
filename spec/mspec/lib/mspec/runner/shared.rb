require 'mspec/runner/mspec'

def it_behaves_like(desc, meth, obj = nil)
  before :all do
    @method = meth
    @object = obj
  end
  after :all do
    @method = nil
    @object = nil
  end

  it_should_behave_like desc.to_s
end
