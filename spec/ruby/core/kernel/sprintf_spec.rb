require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/sprintf', __FILE__)
require File.expand_path('../shared/sprintf_encoding', __FILE__)

describe "Kernel#sprintf" do
  it_behaves_like :kernel_sprintf, -> (format, *args) {
    sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_encoding, -> (format, *args) {
    sprintf(format, *args)
  }
end

describe "Kernel.sprintf" do
  it_behaves_like :kernel_sprintf, -> (format, *args) {
    Kernel.sprintf(format, *args)
  }

  it_behaves_like :kernel_sprintf_encoding, -> (format, *args) {
    Kernel.sprintf(format, *args)
  }
end
