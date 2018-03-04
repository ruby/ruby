require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/sprintf'
require_relative 'shared/sprintf_encoding'

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
