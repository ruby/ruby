require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/sprintf'
require_relative 'shared/sprintf_encoding'

describe :kernel_sprintf_to_str, shared: true do
  it "calls #to_str to convert the format object to a String" do
    obj = mock('format string')
    obj.should_receive(:to_str).and_return("to_str: %i")
    @method.call(obj, 42).should == "to_str: 42"
  end
end

describe "Kernel#sprintf" do
  it_behaves_like :kernel_sprintf, -> format, *args {
    sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_encoding, -> format, *args {
    sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_to_str, -> format, *args {
    sprintf(format, *args)
  }
end

describe "Kernel.sprintf" do
  it_behaves_like :kernel_sprintf, -> format, *args {
    Kernel.sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_encoding, -> format, *args {
    Kernel.sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_to_str, -> format, *args {
    Kernel.sprintf(format, *args)
  }
end
