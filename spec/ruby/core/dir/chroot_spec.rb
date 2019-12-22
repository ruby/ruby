require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/chroot'

platform_is_not :windows do
  as_superuser do
    describe "Dir.chroot as root" do
      it_behaves_like :dir_chroot_as_root, :chroot
    end
  end

  platform_is_not :cygwin, :android do
    as_user do
      describe "Dir.chroot as regular user" do
        before :all do
          DirSpecs.create_mock_dirs
        end

        after :all do
          DirSpecs.delete_mock_dirs
        end

        it "raises an Errno::EPERM exception if the directory exists" do
          -> { Dir.chroot('.') }.should raise_error(Errno::EPERM)
        end

        it "raises a SystemCallError if the directory doesn't exist" do
          -> { Dir.chroot('xgwhwhsjai2222jg') }.should raise_error(SystemCallError)
        end

        it "calls #to_path on non-String argument" do
          p = mock('path')
          p.should_receive(:to_path).and_return('.')
          -> { Dir.chroot(p) }.should raise_error(Errno::EPERM)
        end
      end
    end
  end

  platform_is :cygwin do
    as_user do
      describe "Dir.chroot as regular user" do
        it_behaves_like :dir_chroot_as_root, :chroot
      end
    end
  end
end
