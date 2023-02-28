require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.2" do
  describe "Data.define" do
    it "accepts no arguments" do
      empty_data = Data.define
      empty_data.members.should == []
    end

    it "accepts symbols" do
      movie_with_symbol = Data.define(:title, :year)
      movie_with_symbol.members.should == [:title, :year]
    end

    it "accepts strings" do
      movie_with_string = Data.define("title", "year")
      movie_with_string.members.should == [:title, :year]
    end

    it "accepts a mix of strings and symbols" do
      blockbuster_movie = Data.define("title", :year, "genre")
      blockbuster_movie.members.should == [:title, :year, :genre]
    end
  end
end
