require_relative '../../../spec_helper'

platform_is(:windows, :darwin, :freebsd, :netbsd,
            *ruby_version_is("3.5") { :linux },
           ) do
  describe "File::Stat#birthtime" do
    before :each do
      @file = tmp('i_exist')
      touch(@file) { |f| f.write "rubinius" }
    end

    after :each do
      rm_r @file
    end

    it "returns the birthtime of a File::Stat object" do
      st = File.stat(@file)
      st.birthtime.should be_kind_of(Time)
      st.birthtime.should <= Time.now
    rescue NotImplementedError => e
      skip e.message if e.message.start_with?("birthtime() function")
    end
  end
end
