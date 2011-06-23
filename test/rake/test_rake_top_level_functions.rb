require File.expand_path('../helper', __FILE__)

class TestRakeTopLevelFunctions < Rake::TestCase

  def setup
    super

    @app = Rake.application
    Rake.application = flexmock("app")
    Rake.application.should_receive(:deprecate).
      and_return { |old, new, call| @app.deprecate(old, new, call) }
  end

  def teardown
    Rake.application = @app

    super
  end

  def test_namespace
    Rake.application.should_receive(:in_namespace).with("xyz", any).once
    namespace "xyz" do end
  end

  def test_import
    Rake.application.should_receive(:add_import).with("x").once.ordered
    Rake.application.should_receive(:add_import).with("y").once.ordered
    Rake.application.should_receive(:add_import).with("z").once.ordered
    import('x', 'y', 'z')
  end

  def test_when_writing
    out, = capture_io do
      when_writing("NOTWRITING") do
        puts "WRITING"
      end
    end
    assert_equal "WRITING\n", out
  end

  def test_when_not_writing
    Rake::FileUtilsExt.nowrite_flag = true
    _, err = capture_io do
      when_writing("NOTWRITING") do
        puts "WRITING"
      end
    end
    assert_equal "DRYRUN: NOTWRITING\n", err
  ensure
    Rake::FileUtilsExt.nowrite_flag = false
  end

  def test_missing_constants_task
    Rake.application.should_receive(:const_warning).with(:Task).once
    Object.const_missing(:Task)
  end

  def test_missing_constants_file_task
    Rake.application.should_receive(:const_warning).with(:FileTask).once
    Object.const_missing(:FileTask)
  end

  def test_missing_constants_file_creation_task
    Rake.application.should_receive(:const_warning).with(:FileCreationTask).once
    Object.const_missing(:FileCreationTask)
  end

  def test_missing_constants_rake_app
    Rake.application.should_receive(:const_warning).with(:RakeApp).once
    Object.const_missing(:RakeApp)
  end

  def test_missing_other_constant
    assert_raises(NameError) do Object.const_missing(:Xyz) end
  end
end
