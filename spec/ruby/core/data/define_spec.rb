require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data.define" do
  it "accepts no arguments" do
    empty_data = Data.define
    empty_data.members.should == []
  end

  it "accepts symbols" do
    movie = Data.define(:title, :year)
    movie.members.should == [:title, :year]
  end

  it "accepts strings" do
    movie = Data.define("title", "year")
    movie.members.should == [:title, :year]
  end

  it "accepts a mix of strings and symbols" do
    movie = Data.define("title", :year, "genre")
    movie.members.should == [:title, :year, :genre]
  end

  it "accepts a block" do
    movie = Data.define(:title, :year) do
      def title_with_year
        "#{title} (#{year})"
      end
    end
    movie.members.should == [:title, :year]
    movie.new("Matrix", 1999).title_with_year.should == "Matrix (1999)"
  end

  describe "called on a subclass of Data" do
    it "produces data classes that can invoke class methods on that subclass" do
      data_sub = Class.new(Data)
      data_sub.define_singleton_method(:data_sub_class_method) { :ok }
      data_sub_defined = data_sub.define(:foo)
      data_sub_defined.data_sub_class_method.should == :ok
    end
  end
end
