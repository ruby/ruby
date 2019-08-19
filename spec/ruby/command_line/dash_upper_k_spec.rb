require_relative '../spec_helper'

describe 'The -K command line option' do
  before :each do
    @test_string = "print [__ENCODING__&.name, Encoding.default_external&.name, Encoding.default_internal&.name].inspect"
  end

  describe 'sets __ENCODING__ and Encoding.default_external' do
    it "to Encoding::BINARY with -Ka" do
      ruby_exe(@test_string, options: '-Ka').should ==
        [Encoding::BINARY.name, Encoding::BINARY.name, nil].inspect
    end

    it "to Encoding::BINARY with -KA" do
      ruby_exe(@test_string, options: '-KA').should ==
        [Encoding::BINARY.name, Encoding::BINARY.name, nil].inspect
    end

    it "to Encoding::BINARY with -Kn" do
      ruby_exe(@test_string, options: '-Kn').should ==
        [Encoding::BINARY.name, Encoding::BINARY.name, nil].inspect
    end

    it "to Encoding::BINARY with -KN" do
      ruby_exe(@test_string, options: '-KN').should ==
        [Encoding::BINARY.name, Encoding::BINARY.name, nil].inspect
    end

    it "to Encoding::EUC_JP with -Ke" do
      ruby_exe(@test_string, options: '-Ke').should ==
        [Encoding::EUC_JP.name, Encoding::EUC_JP.name, nil].inspect
    end

    it "to Encoding::EUC_JP with -KE" do
      ruby_exe(@test_string, options: '-KE').should ==
        [Encoding::EUC_JP.name, Encoding::EUC_JP.name, nil].inspect
    end

    it "to Encoding::UTF_8 with -Ku" do
      ruby_exe(@test_string, options: '-Ku').should ==
        [Encoding::UTF_8.name, Encoding::UTF_8.name, nil].inspect
    end

    it "to Encoding::UTF_8 with -KU" do
      ruby_exe(@test_string, options: '-KU').should ==
        [Encoding::UTF_8.name, Encoding::UTF_8.name, nil].inspect
    end

    it "to Encoding::Windows_31J with -Ks" do
      ruby_exe(@test_string, options: '-Ks').should ==
        [Encoding::Windows_31J.name, Encoding::Windows_31J.name, nil].inspect
    end

    it "to Encoding::Windows_31J with -KS" do
      ruby_exe(@test_string, options: '-KS').should ==
        [Encoding::Windows_31J.name, Encoding::Windows_31J.name, nil].inspect
    end
  end

  it "ignores unknown codes" do
    locale = Encoding.find('locale')
    ruby_exe(@test_string, options: '-KZ').should ==
      [Encoding::UTF_8.name, locale.name, nil].inspect
  end
end
