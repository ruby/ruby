describe :extract_range_matched, shared: true do
  it "returns an instance of String when passed a String subclass" do
    cls = Class.new(String)
    sub = cls.new("abc")

    s = StringScanner.new(sub)
    s.scan(/\w{1}/)

    ch = s.send(@method)
    ch.should_not.is_a?(cls)
    ch.should.instance_of?(String)
  end
end
