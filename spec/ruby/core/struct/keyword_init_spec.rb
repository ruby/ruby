require_relative '../../spec_helper'

ruby_version_is "3.1" do
  # See https://bugs.ruby-lang.org/issues/18008
  describe "StructClass#keyword_init?" do
    it "returns true for a struct that accepts keyword arguments to initialize" do
      struct = Struct.new(:arg, keyword_init: true)
      struct.keyword_init?.should be_true
    end

    it "returns false for a struct that does not accept keyword arguments to initialize" do
      struct = Struct.new(:arg, keyword_init: false)
      struct.keyword_init?.should be_false
    end

    it "returns nil for a struct that did not explicitly specify keyword_init" do
      struct = Struct.new(:arg)
      struct.keyword_init?.should be_nil
    end

    it "returns nil for a struct that does specify keyword_init to be nil" do
      struct = Struct.new(:arg, keyword_init: nil)
      struct.keyword_init?.should be_nil
    end

    it "returns true for any truthy value, not just for true" do
      struct = Struct.new(:arg, keyword_init: 1)
      struct.keyword_init?.should be_true

      struct = Struct.new(:arg, keyword_init: "")
      struct.keyword_init?.should be_true

      struct = Struct.new(:arg, keyword_init: [])
      struct.keyword_init?.should be_true

      struct = Struct.new(:arg, keyword_init: {})
      struct.keyword_init?.should be_true
    end
  end
end
