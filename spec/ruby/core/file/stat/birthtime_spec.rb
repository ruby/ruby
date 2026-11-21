require_relative '../../../spec_helper'

platform_is(:windows, :darwin, :freebsd, :netbsd,
            *ruby_version_is("4.0") { :linux },
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
      st.birthtime.should.is_a?(Time)
      st.birthtime.should <= Time.now
      st.birthtime.should > Time.now - 24*60*60
    rescue NotImplementedError => e
      e.message.should.start_with?(*not_implemented_messages)
    end
  end
end
