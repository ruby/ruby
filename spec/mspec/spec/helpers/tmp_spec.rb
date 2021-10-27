require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#tmp" do
  before :all do
    @dir = SPEC_TEMP_DIR
  end

  it "returns a name relative to the current working directory" do
    expect(tmp("test.txt")).to eq("#{@dir}/#{SPEC_TEMP_UNIQUIFIER}-test.txt")
  end

  it "returns a 'unique' name on repeated calls" do
    a = tmp("text.txt")
    b = tmp("text.txt")
    expect(a).not_to eq(b)
  end

  it "does not 'uniquify' the name if requested not to" do
    expect(tmp("test.txt", false)).to eq("#{@dir}/test.txt")
  end

  it "returns the name of the temporary directory when passed an empty string" do
    expect(tmp("")).to eq("#{@dir}/")
  end
end
