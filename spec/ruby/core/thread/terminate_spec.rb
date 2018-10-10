require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exit'

describe "Thread#terminate" do
  # This spec randomly kills mspec worker like: https://ci.appveyor.com/project/ruby/ruby/builds/19390874/job/wv1bsm8skd4e1pxl
  # TODO: Investigate the cause or at least print helpful logs, and remove this `platform_is_not` guard.
  platform_is_not :mingw do
    it_behaves_like :thread_exit, :terminate
  end
end
