require_relative '../../../spec_helper'

platform_is(:windows, :darwin, :freebsd, :netbsd,
            *ruby_version_is("3.5") { :linux },
           ) do
  not_implemented_messages = [
    "birthtime() function is unimplemented", # unsupported OS/version
    "birthtime is unimplemented",            # unsupported filesystem
  ]

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
      e.message.should.start_with?(*not_implemented_messages)
    end
  end
end
