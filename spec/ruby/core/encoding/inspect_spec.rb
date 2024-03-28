require_relative '../../spec_helper'

describe "Encoding#inspect" do
  it "returns a String" do
    Encoding::UTF_8.inspect.should be_an_instance_of(String)
  end

  ruby_version_is ""..."3.4" do
    it "returns #<Encoding:name> for a non-dummy encoding named 'name'" do
      Encoding.list.to_a.reject {|e| e.dummy? }.each do |enc|
        enc.inspect.should =~ /#<Encoding:#{enc.name}>/
      end
    end
  end

  ruby_version_is "3.4" do
    it "returns #<Encoding:name> for a non-dummy encoding named 'name'" do
      Encoding.list.to_a.reject {|e| e.dummy? }.each do |enc|
        if enc.name == "ASCII-8BIT"
          enc.inspect.should == "#<Encoding:BINARY (ASCII-8BIT)>"
        else
          enc.inspect.should =~ /#<Encoding:#{enc.name}>/
        end
      end
    end
  end

  it "returns #<Encoding:name (dummy)> for a dummy encoding named 'name'" do
    Encoding.list.to_a.select {|e| e.dummy? }.each do |enc|
      enc.inspect.should =~ /#<Encoding:#{enc.name} \(dummy\)>/
    end
  end
end
