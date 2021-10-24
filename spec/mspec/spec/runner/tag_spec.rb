require 'spec_helper'
require 'mspec/runner/tag'

RSpec.describe SpecTag do
  it "accepts an optional string to parse into fields" do
    tag = SpecTag.new "tag(comment):description"
    expect(tag.tag).to eq("tag")
    expect(tag.comment).to eq("comment")
    expect(tag.description).to eq("description")
  end
end

RSpec.describe SpecTag, "#parse" do
  before :each do
    @tag = SpecTag.new
  end

  it "accepts 'tag(comment):description'" do
    @tag.parse "tag(I'm real):Some#method returns a value"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq("I'm real")
    expect(@tag.description).to eq("Some#method returns a value")
  end

  it "accepts 'tag:description'" do
    @tag.parse "tag:Another#method"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq(nil)
    expect(@tag.description).to eq("Another#method")
  end

  it "accepts 'tag():description'" do
    @tag.parse "tag():Another#method"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq(nil)
    expect(@tag.description).to eq("Another#method")
  end

  it "accepts 'tag:'" do
    @tag.parse "tag:"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq(nil)
    expect(@tag.description).to eq("")
  end

  it "accepts 'tag(bug:555):Another#method'" do
    @tag.parse "tag(bug:555):Another#method"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq("bug:555")
    expect(@tag.description).to eq("Another#method")
  end

  it "accepts 'tag(http://someplace.com/neato):Another#method'" do
    @tag.parse "tag(http://someplace.com/neato):Another#method"
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq("http://someplace.com/neato")
    expect(@tag.description).to eq("Another#method")
  end

  it "accepts 'tag(comment):\"Multi-line\\ntext\"'" do
    @tag.parse 'tag(comment):"Multi-line\ntext"'
    expect(@tag.tag).to eq("tag")
    expect(@tag.comment).to eq("comment")
    expect(@tag.description).to eq("Multi-line\ntext")
  end

  it "ignores '#anything'" do
    @tag.parse "# this could be a comment"
    expect(@tag.tag).to eq(nil)
    expect(@tag.comment).to eq(nil)
    expect(@tag.description).to eq(nil)
  end
end

RSpec.describe SpecTag, "#to_s" do
  it "formats itself as 'tag(comment):description'" do
    txt = "tag(comment):description"
    tag = SpecTag.new txt
    expect(tag.tag).to eq("tag")
    expect(tag.comment).to eq("comment")
    expect(tag.description).to eq("description")
    expect(tag.to_s).to eq(txt)
  end

  it "formats itself as 'tag:description" do
    txt = "tag:description"
    tag = SpecTag.new txt
    expect(tag.tag).to eq("tag")
    expect(tag.comment).to eq(nil)
    expect(tag.description).to eq("description")
    expect(tag.to_s).to eq(txt)
  end

  it "formats itself as 'tag(comment):\"multi-line\\ntext\\ntag\"'" do
    txt = 'tag(comment):"multi-line\ntext\ntag"'
    tag = SpecTag.new txt
    expect(tag.tag).to eq("tag")
    expect(tag.comment).to eq("comment")
    expect(tag.description).to eq("multi-line\ntext\ntag")
    expect(tag.to_s).to eq(txt)
  end
end

RSpec.describe SpecTag, "#==" do
  it "returns true if the tags have the same fields" do
    one = SpecTag.new "tag(this):unicorn"
    two = SpecTag.new "tag(this):unicorn"
    expect(one.==(two)).to eq(true)
    expect([one].==([two])).to eq(true)
  end
end

RSpec.describe SpecTag, "#unescape" do
  it "replaces \\n by LF when the description is quoted" do
    tag = SpecTag.new 'tag:"desc with\nnew line"'
    expect(tag.description).to eq("desc with\nnew line")
  end

  it "does not replaces \\n by LF when the description is not quoted " do
    tag = SpecTag.new 'tag:desc with\nnew line'
    expect(tag.description).to eq("desc with\\nnew line")
  end
end
