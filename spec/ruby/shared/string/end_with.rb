describe :end_with, shared: true do
  # the @method should either be :to_s or :to_sym

  it "returns true only if ends match" do
    s = "hello".send(@method)
    s.should.end_with?('o')
    s.should.end_with?('llo')
  end

  it 'returns false if the end does not match' do
    s = 'hello'.send(@method)
    s.should_not.end_with?('ll')
  end

  it "returns true if the search string is empty" do
    "hello".send(@method).should.end_with?("")
    "".send(@method).should.end_with?("")
  end

  it "returns true only if any ending match" do
    "hello".send(@method).should.end_with?('x', 'y', 'llo', 'z')
  end

  it "converts its argument using :to_str" do
    s = "hello".send(@method)
    find = mock('o')
    find.should_receive(:to_str).and_return("o")
    s.should.end_with?(find)
  end

  it "ignores arguments not convertible to string" do
    "hello".send(@method).should_not.end_with?()
    -> { "hello".send(@method).end_with?(1) }.should raise_error(TypeError)
    -> { "hello".send(@method).end_with?(["o"]) }.should raise_error(TypeError)
    -> { "hello".send(@method).end_with?(1, nil, "o") }.should raise_error(TypeError)
  end

  it "uses only the needed arguments" do
    find = mock('h')
    find.should_not_receive(:to_str)
    "hello".send(@method).should.end_with?("o",find)
  end

  it "works for multibyte strings" do
    "céréale".send(@method).should.end_with?("réale")
  end

  it "raises an Encoding::CompatibilityError if the encodings are incompatible" do
    pat = "ア".encode Encoding::EUC_JP
    -> do
      "あれ".send(@method).end_with?(pat)
    end.should raise_error(Encoding::CompatibilityError)
  end
end
