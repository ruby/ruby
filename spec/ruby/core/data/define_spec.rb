require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.2" do
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
  end
end
