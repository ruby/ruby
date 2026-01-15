require_relative '../../spec_helper'
require_relative 'fixtures/common'

has_dir_fileno = begin
  dir = Dir.new('.')
  dir.fileno
  true
rescue NotImplementedError
  false
rescue Exception
  true
ensure
  dir.close
end

describe "Dir#fileno" do
  before :each do
    @name = tmp("fileno")
    mkdir_p @name
    @dir = Dir.new(@name)
  end

  after :each do
    @dir.close
    rm_r @name
  end

  if has_dir_fileno
    it "returns the file descriptor of the dir" do
      @dir.fileno.should be_kind_of(Integer)
    end
  else
    it "raises an error when not implemented on the platform" do
      -> { @dir.fileno }.should raise_error(NotImplementedError)
    end
  end
end
