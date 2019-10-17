require_relative '../../spec_helper'

require 'base64'

describe "Base64#urlsafe_encode64" do
  it "uses '_' instead of '/'" do
    encoded = Base64.urlsafe_encode64('Where am I? Who am I? Am I? I?')
    encoded.should == "V2hlcmUgYW0gST8gV2hvIGFtIEk_IEFtIEk_IEk_"
  end

  it "uses '-' instead of '+'" do
    encoded = Base64.urlsafe_encode64('"Being disintegrated makes me ve-ry an-gry!" <huff, huff>')
    encoded.should == 'IkJlaW5nIGRpc2ludGVncmF0ZWQgbWFrZXMgbWUgdmUtcnkgYW4tZ3J5ISIgPGh1ZmYsIGh1ZmY-'
  end

  it "makes padding optional" do
    Base64.urlsafe_encode64("1", padding: false).should == "MQ"
    Base64.urlsafe_encode64("1").should == "MQ=="
  end
end
