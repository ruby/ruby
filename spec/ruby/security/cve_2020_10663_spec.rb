require_relative '../spec_helper'
require 'json'

module JSONSpecs
  class MyClass
    def initialize(foo)
      @foo = foo
    end

    def self.json_create(hash)
      new(*hash['args'])
    end

    def to_json(*args)
      { 'json_class' => self.class.name, 'args' => [ @foo ] }.to_json(*args)
    end
  end
end

guard -> {
  ruby_version_is "2.5.8"..."2.6.0" or
  ruby_version_is "2.6.6" or
  JSON.const_defined?(:Pure) or
  version_is(JSON::VERSION, '2.3.0')
} do
  describe "CVE-2020-10663 is resisted by" do
    it "only creating custom objects if passed create_additions: true or using JSON.load" do
      obj = JSONSpecs::MyClass.new("bar")
      JSONSpecs::MyClass.should.json_creatable?
      json = JSON.dump(obj)

      JSON.parse(json, create_additions: true).class.should == JSONSpecs::MyClass
      JSON(json, create_additions: true).class.should == JSONSpecs::MyClass
      JSON.load(json).class.should == JSONSpecs::MyClass

      JSON.parse(json).class.should == Hash
      JSON.parse(json, nil).class.should == Hash
      JSON(json).class.should == Hash
    end
  end
end
