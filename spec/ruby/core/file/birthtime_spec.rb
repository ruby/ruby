require_relative '../../spec_helper'

platform_is :windows, :darwin, :freebsd, :netbsd, :linux do
  describe "File.birthtime" do
    before :each do
      @file = __FILE__
    end

    after :each do
      @file = nil
    end

    it "returns the birth time for the named file as a Time object" do
      File.birthtime(@file)
      File.birthtime(@file).should be_kind_of(Time)
    rescue NotImplementedError => e
      skip e.message if e.message.start_with?("birthtime() function")
    end

    it "accepts an object that has a #to_path method" do
      File.birthtime(@file) # Avoid to failure of mock object with old Kernel and glibc
      File.birthtime(mock_to_path(@file))
    rescue NotImplementedError => e
      skip e.message if e.message.start_with?("birthtime() function")
    end

    it "raises an Errno::ENOENT exception if the file is not found" do
      -> { File.birthtime('bogus') }.should raise_error(Errno::ENOENT)
    rescue NotImplementedError => e
      skip e.message if e.message.start_with?("birthtime() function")
    end
  end

  describe "File#birthtime" do
    before :each do
      @file = File.open(__FILE__)
    end

    after :each do
      @file.close
      @file = nil
    end

    it "returns the birth time for self" do
      @file.birthtime
      @file.birthtime.should be_kind_of(Time)
    rescue NotImplementedError => e
      skip e.message if e.message.start_with?("birthtime() function")
    end
  end
end
