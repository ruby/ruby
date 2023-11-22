# -*- encoding: utf-8 -*-
require_relative '../../../spec_helper'

describe :byte_index_common, shared: true do
  describe "raises on type errors" do
    it "raises a TypeError if passed nil" do
      -> { "abc".send(@method, nil) }.should raise_error(TypeError, "no implicit conversion of nil into String")
    end

    it "raises a TypeError if passed a boolean" do
      -> { "abc".send(@method, true) }.should raise_error(TypeError, "no implicit conversion of true into String")
    end

    it "raises a TypeError if passed a Symbol" do
      not_supported_on :opal do
        -> { "abc".send(@method, :a) }.should raise_error(TypeError, "no implicit conversion of Symbol into String")
      end
    end

    it "raises a TypeError if passed a Symbol" do
      obj = mock('x')
      obj.should_not_receive(:to_int)
      -> { "hello".send(@method, obj) }.should raise_error(TypeError, "no implicit conversion of MockObject into String")
    end

    it "raises a TypeError if passed an Integer" do
      -> { "abc".send(@method, 97) }.should raise_error(TypeError, "no implicit conversion of Integer into String")
    end
  end

  describe "with multibyte codepoints" do
    it "raises an IndexError when byte offset lands in the middle of a multibyte character" do
      -> { "わ".send(@method, "", 1) }.should raise_error(IndexError, "offset 1 does not land on character boundary")
      -> { "わ".send(@method, "", 2) }.should raise_error(IndexError, "offset 2 does not land on character boundary")
      -> { "わ".send(@method, "", -1) }.should raise_error(IndexError, "offset 2 does not land on character boundary")
      -> { "わ".send(@method, "", -2) }.should raise_error(IndexError, "offset 1 does not land on character boundary")
    end

    it "raises an Encoding::CompatibilityError if the encodings are incompatible" do
      re = Regexp.new "れ".encode(Encoding::EUC_JP)
      -> do
        "あれ".send(@method, re)
      end.should raise_error(Encoding::CompatibilityError, "incompatible encoding regexp match (EUC-JP regexp with UTF-8 string)")
    end
  end

  describe "with global variables" do
    it "doesn't set $~ for non regex search" do
      $~ = nil

      'hello.'.send(@method, 'll')
      $~.should == nil
    end

    it "sets $~ to MatchData of match and nil when there's none" do
      'hello.'.send(@method, /.e./)
      $~[0].should == 'hel'

      'hello.'.send(@method, /not/)
      $~.should == nil
    end
  end
end
