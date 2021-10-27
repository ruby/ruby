# encoding: utf-8
require 'spec_helper'

RSpec.describe "Running mspec tag" do
  before :all do
    FileUtils.rm_rf 'spec/fixtures/tags'
  end

  after :all do
    FileUtils.rm_rf 'spec/fixtures/tags'
  end

  it "tags the failing specs" do
    fixtures = "spec/fixtures"
    out, ret = run_mspec("tag", "--add fails --fail #{fixtures}/tagging_spec.rb")
    expect(out).to eq <<EOS
RUBY_DESCRIPTION
.FF
TagAction: specs tagged with 'fails':

Tag#me errors
Tag#me érròrs in unicode


1)
Tag#me errors FAILED
Expected 1 == 2
to be truthy but was false
CWD/spec/fixtures/tagging_spec.rb:9:in `block (2 levels) in <top (required)>'
CWD/spec/fixtures/tagging_spec.rb:3:in `<top (required)>'

2)
Tag#me érròrs in unicode FAILED
Expected 1 == 2
to be truthy but was false
CWD/spec/fixtures/tagging_spec.rb:13:in `block (2 levels) in <top (required)>'
CWD/spec/fixtures/tagging_spec.rb:3:in `<top (required)>'

Finished in D.DDDDDD seconds

1 file, 3 examples, 3 expectations, 2 failures, 0 errors, 0 tagged
EOS
    expect(ret.success?).to eq(false)
  end

  it "does not run already tagged specs" do
    fixtures = "spec/fixtures"
    out, ret = run_mspec("run", "--excl-tag fails #{fixtures}/tagging_spec.rb")
    expect(out).to eq <<EOS
RUBY_DESCRIPTION
.

Finished in D.DDDDDD seconds

1 file, 3 examples, 1 expectation, 0 failures, 0 errors, 2 tagged
EOS
    expect(ret.success?).to eq(true)
  end
end
