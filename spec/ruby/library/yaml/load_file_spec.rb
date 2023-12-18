require_relative '../../spec_helper'

require 'yaml'

describe "YAML.load_file" do
  before :each do
    @test_file = tmp("yaml_test_file")
  end

  after :each do
    rm_r @test_file
  end

  it "returns a hash" do
    File.open(@test_file,'w' ){|io| YAML.dump( {"bar"=>2, "car"=>1}, io ) }
    YAML.load_file(@test_file).should == {"bar"=>2, "car"=>1}
  end
end
