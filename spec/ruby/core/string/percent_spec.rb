require_relative '../../spec_helper'
require_relative '../kernel/shared/sprintf'
require_relative '../kernel/shared/sprintf_encoding'

describe "String#%" do
  it_behaves_like :kernel_sprintf, -> format, *args {
    format % args
  }

  it_behaves_like :kernel_sprintf_encoding, -> format, *args {
    format % args
  }
end
