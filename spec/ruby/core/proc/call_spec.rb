require_relative '../../spec_helper'
require_relative 'shared/call'
require_relative 'shared/call_arguments'

describe "Proc#call" do
  it_behaves_like :proc_call, :call
  it_behaves_like :proc_call_block_args, :call
end

describe "Proc#call on a Proc created with Proc.new" do
  it_behaves_like :proc_call_on_proc_new, :call
end

describe "Proc#call on a Proc created with Kernel#lambda or Kernel#proc" do
  it_behaves_like :proc_call_on_proc_or_lambda, :call
end
