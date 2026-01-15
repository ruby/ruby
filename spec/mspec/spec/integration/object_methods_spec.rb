require 'spec_helper'

expected_output = <<EOS
RUBY_DESCRIPTION
.

Finished in D.DDDDDD seconds

1 file, 1 example, 1 expectation, 0 failures, 0 errors, 0 tagged
EOS

RSpec.describe "MSpec" do
  it "does not define public methods on Object" do
    out, ret = run_mspec("run", "spec/fixtures/object_methods_spec.rb")
    expect(out).to eq(expected_output)
    expect(ret.success?).to eq(true)
  end
end
