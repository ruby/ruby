# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/select'

describe "Enumerator::Lazy#select" do
  it_behaves_like :enumerator_lazy_select, :select

  it "doesn't pre-evaluate the next element" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.next
    eval_count.should == 1
  end

  it "doesn't over-evaluate when peeked" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.peek
    enum.peek
    eval_count.should == 1
  end

  it "doesn't re-evaluate after peek" do
    eval_count = 0
    enum = %w[Text1 Text2 Text3].lazy.select do
      eval_count += 1
      true
    end

    eval_count.should == 0
    enum.peek
    eval_count.should == 1
    enum.next
    eval_count.should == 1
  end
end
