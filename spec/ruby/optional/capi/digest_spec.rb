require_relative 'spec_helper'

require 'fiddle'

load_extension('digest')

describe "C-API Digest functions" do
  before :each do
    @s = CApiDigestSpecs.new
  end

  describe "rb_digest_make_metadata" do
    before :each do
      @metadata = @s.rb_digest_make_metadata
    end

    it "should store the block length" do
      @s.block_length(@metadata).should == 40
    end

    it "should store the digest length" do
      @s.digest_length(@metadata).should == 20
    end

    it "should store the context size" do
      @s.context_size(@metadata).should == 129
    end
  end

  describe "digest plugin" do
    before :each do
      @s = CApiDigestSpecs.new
      @digest = Digest::TestDigest.new

      # A pointer to the CTX type defined in the extension for this spec. Digest does not make the context directly
      # accessible as part of its API. However, to ensure we are properly loading the plugin, it's useful to have
      # direct access to the context pointer to verify its contents.
      @context = Fiddle::Pointer.new(@s.context(@digest))
    end

    it "should report the block length" do
      @digest.block_length.should == 40
    end

    it "should report the digest length" do
      @digest.digest_length.should == 20
    end

    it "should initialize the context" do
      # Our test plugin always writes the string "Initialized\n" when its init function is called.
      verify_context("Initialized\n")
    end

    it "should update the digest" do
      @digest.update("hello world")

      # Our test plugin always writes the string "Updated: <data>\n" when its update function is called.
      current = "Initialized\nUpdated: hello world"
      verify_context(current)

      @digest << "blah"

      current = "Initialized\nUpdated: hello worldUpdated: blah"
      verify_context(current)
    end

    it "should finalize the digest" do
      @digest.update("")

      finish_string = @digest.instance_eval { finish }

      # We expect the plugin to write out the last `@digest.digest_length` bytes, followed by the string "Finished\n".
      #
      finish_string.should == "d\nUpdated: Finished\n"
      finish_string.encoding.should == Encoding::ASCII_8BIT
    end

    it "should reset the context" do
      @digest.update("foo")
      verify_context("Initialized\nUpdated: foo")

      @digest.reset

      # The context will be recreated as a result of the `reset` so we must fetch the latest context pointer.
      @context = Fiddle::Pointer.new(@s.context(@digest))

      verify_context("Initialized\n")
    end

    def verify_context(current_body)
      # In the CTX type, the length of the current context contents is stored in the first byte.
      byte_count = @context[0]
      byte_count.should == current_body.bytesize

      # After the size byte follows a string.
      @context[1, byte_count].should == current_body
    end
  end
end
