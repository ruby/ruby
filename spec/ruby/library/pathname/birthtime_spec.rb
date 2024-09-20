require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#birthtime" do
  platform_is :windows, :darwin, :freebsd, :netbsd do
    it "returns the birth time for self" do
      Pathname.new(__FILE__).birthtime.should be_kind_of(Time)
    end
  end

  platform_is :openbsd do
    it "raises an NotImplementedError" do
      -> { Pathname.new(__FILE__).birthtime }.should raise_error(NotImplementedError)
    end
  end
end
