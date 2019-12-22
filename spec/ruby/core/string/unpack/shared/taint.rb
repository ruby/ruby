describe :string_unpack_taint, shared: true do
  ruby_version_is ''...'2.7' do
    it "does not taint returned arrays if given an untainted format string" do
      "".unpack(unpack_format(2)).tainted?.should be_false
    end

    it "does not taint returned arrays if given a tainted format string" do
      format_string = unpack_format(2).dup
      format_string.taint
      "".unpack(format_string).tainted?.should be_false
    end

    it "does not taint returned strings if given an untainted format string" do
      "".unpack(unpack_format(2)).any?(&:tainted?).should be_false
    end

    it "does not taint returned strings if given a tainted format string" do
      format_string = unpack_format(2).dup
      format_string.taint
      "".unpack(format_string).any?(&:tainted?).should be_false
    end

    it "does not taint returned arrays if given an untainted packed string" do
      "".unpack(unpack_format(2)).tainted?.should be_false
    end

    it "does not taint returned arrays if given a tainted packed string" do
      packed_string = ""
      packed_string.taint
      packed_string.unpack(unpack_format(2)).tainted?.should be_false
    end

    it "does not taint returned strings if given an untainted packed string" do
      "".unpack(unpack_format(2)).any?(&:tainted?).should be_false
    end

    it "taints returned strings if given a tainted packed string" do
      packed_string = ""
      packed_string.taint
      packed_string.unpack(unpack_format(2)).all?(&:tainted?).should be_true
    end

    it "does not untrust returned arrays if given an untrusted format string" do
      "".unpack(unpack_format(2)).untrusted?.should be_false
    end

    it "does not untrust returned arrays if given a untrusted format string" do
      format_string = unpack_format(2).dup
      format_string.untrust
      "".unpack(format_string).untrusted?.should be_false
    end

    it "does not untrust returned strings if given an untainted format string" do
      "".unpack(unpack_format(2)).any?(&:untrusted?).should be_false
    end

    it "does not untrust returned strings if given a untrusted format string" do
      format_string = unpack_format(2).dup
      format_string.untrust
      "".unpack(format_string).any?(&:untrusted?).should be_false
    end

    it "does not untrust returned arrays if given an trusted packed string" do
      "".unpack(unpack_format(2)).untrusted?.should be_false
    end

    it "does not untrust returned arrays if given a untrusted packed string" do
      packed_string = ""
      packed_string.untrust
      packed_string.unpack(unpack_format(2)).untrusted?.should be_false
    end

    it "does not untrust returned strings if given an trusted packed string" do
      "".unpack(unpack_format(2)).any?(&:untrusted?).should be_false
    end

    it "untrusts returned strings if given a untrusted packed string" do
      packed_string = ""
      packed_string.untrust
      packed_string.unpack(unpack_format(2)).all?(&:untrusted?).should be_true
    end
  end
end
