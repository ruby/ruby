require_relative '../../spec_helper'
require_relative 'fixtures/strings'
require 'yaml'

describe "YAML.load_stream" do
  it "calls the block on each successive document" do
    documents = []
    YAML.load_stream(YAMLSpecs::MULTIDOCUMENT) do |doc|
      documents << doc
    end
    documents.should == [["Mark McGwire", "Sammy Sosa", "Ken Griffey"],
                         ["Chicago Cubs", "St Louis Cardinals"]]
  end

  it "works on files" do
    test_parse_file = fixture __FILE__, "test_yaml.yml"
    File.open(test_parse_file, "r") do |file|
      YAML.load_stream(file) do |doc|
        doc.should == {"project"=>{"name"=>"RubySpec"}}
      end
    end
  end
end
