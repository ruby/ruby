# frozen_string_literal: true

require "rbconfig"

if /mswin|mingw|cygwin/ =~ RbConfig::CONFIG['host_os']
  begin
    require 'win32/registry'
  rescue LoadError
  else
    require 'test/unit'
  end
end

if defined?(Win32::Registry)
  class TestWin32Registry < Test::Unit::TestCase
    COMPUTERNAME = 'SYSTEM\\CurrentControlSet\\Control\\ComputerName\\ComputerName'
    TEST_REGISTRY_PATH = 'Volatile Environment'
    TEST_REGISTRY_KEY = 'ruby-win32-registry-test-<RND>'

    # Create a new registry key per test in an atomic way, which is deleted on teardown.
    #
    # Fills the following instance variables:
    #
    #   @test_registry_key - A registry path which is not yet created,
    #                        but can be created without collisions even when running
    #                        multiple test processes.
    #   @test_registry_rnd - The part of the registry path with a random number.
    #   @createopts        - Required parameters (desired, opt) for create method in
    #                        the volatile environment of the registry.
    def setup
      @createopts = [Win32::Registry::KEY_ALL_ACCESS, Win32::Registry::REG_OPTION_VOLATILE]
      100.times do |i|
        k = TEST_REGISTRY_KEY.gsub("<RND>", i.to_s)
        next unless Win32::Registry::HKEY_CURRENT_USER.create(
          TEST_REGISTRY_PATH + "\\" + k,
          *@createopts
        ).created?
        @test_registry_key = TEST_REGISTRY_PATH + "\\" + k + "\\" + "test\\"
        @test_registry_rnd = k
        break
      end
      omit "Unused registry subkey not found in #{TEST_REGISTRY_KEY}" unless @test_registry_key
    end

    def teardown
      Win32::Registry::HKEY_CURRENT_USER.open(TEST_REGISTRY_PATH) do |reg|
        reg.delete_key @test_registry_rnd, true
      end
    end

    def test_predefined
      assert_predefined_key Win32::Registry::HKEY_CLASSES_ROOT
      assert_predefined_key Win32::Registry::HKEY_CURRENT_USER
      assert_predefined_key Win32::Registry::HKEY_LOCAL_MACHINE
      assert_predefined_key Win32::Registry::HKEY_USERS
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_DATA
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_TEXT
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_NLSTEXT
      assert_predefined_key Win32::Registry::HKEY_CURRENT_CONFIG
      assert_predefined_key Win32::Registry::HKEY_DYN_DATA
    end

    def test_open_no_block
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts).close

      reg = Win32::Registry::HKEY_CURRENT_USER.open(@test_registry_key, Win32::Registry::KEY_ALL_ACCESS)
      assert_kind_of Win32::Registry, reg
      assert_equal true, reg.open?
      assert_equal false, reg.created?
      reg["test"] = "abc"
      reg.close
      assert_raise(Win32::Registry::Error) do
        reg["test"] = "abc"
      end
    end

    def test_open_with_block
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts).close

      regs = []
      Win32::Registry::HKEY_CURRENT_USER.open(@test_registry_key, Win32::Registry::KEY_ALL_ACCESS) do |reg|
        regs << reg
        assert_equal true, reg.open?
        assert_equal false, reg.created?
        reg["test"] = "abc"
      end

      assert_equal 1, regs.size
      assert_kind_of Win32::Registry, regs[0]
      assert_raise(Win32::Registry::Error) do
        regs[0]["test"] = "abc"
      end
    end

    def test_class_open
      name1, keys1 = Win32::Registry.open(Win32::Registry::HKEY_LOCAL_MACHINE, "SYSTEM") do |reg|
        assert_predicate reg, :open?
        [reg.name, reg.keys]
      end
      name2, keys2 = Win32::Registry::HKEY_LOCAL_MACHINE.open("SYSTEM") do |reg|
        assert_predicate reg, :open?
        [reg.name, reg.keys]
      end
      assert_equal name1, name2
      assert_equal keys1, keys2
    end

    def test_read
      computername = ENV['COMPUTERNAME']
      Win32::Registry::HKEY_LOCAL_MACHINE.open(COMPUTERNAME) do |reg|
        assert_equal computername,  reg['ComputerName']
        assert_equal [Win32::Registry::REG_SZ, computername], reg.read('ComputerName')
        assert_raise(TypeError) {reg.read('ComputerName', Win32::Registry::REG_DWORD)}
      end
    end

    def test_create_no_block
      reg = Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts)
      assert_kind_of Win32::Registry, reg
      assert_equal true, reg.open?
      assert_equal true, reg.created?
      reg["test"] = "abc"
      reg.close
      assert_equal false, reg.open?
      assert_raise(Win32::Registry::Error) do
        reg["test"] = "abc"
      end
    end

    def test_create_with_block
      regs = []
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        regs << reg
        reg["test"] = "abc"
        assert_equal true, reg.open?
        assert_equal true, reg.created?
      end

      assert_equal 1, regs.size
      assert_kind_of Win32::Registry, regs[0]
      assert_equal false, regs[0].open?
      assert_raise(Win32::Registry::Error) do
        regs[0]["test"] = "abc"
      end
    end

    def test_write
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.write_s("key1", "data")
        assert_equal [Win32::Registry::REG_SZ, "data"], reg.read("key1")
        reg.write_i("key2", 0x5fe79027)
        assert_equal [Win32::Registry::REG_DWORD, 0x5fe79027], reg.read("key2")
      end
    end

    def test_accessors
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        assert_kind_of Integer, reg.hkey
        assert_kind_of Win32::Registry, reg.parent
        assert_equal "HKEY_CURRENT_USER", reg.parent.name
        assert_equal "Volatile Environment\\#{@test_registry_rnd}\\test\\", reg.keyname
        assert_equal Win32::Registry::REG_CREATED_NEW_KEY, reg.disposition
      end
    end

    def test_name
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        assert_equal "HKEY_CURRENT_USER\\Volatile Environment\\#{@test_registry_rnd}\\test\\", reg.name
      end
    end

    def test_keys
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        assert_equal ["key1"], reg.keys
      end
    end

    def test_each_key
      keys = []
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        reg.each_key { |*a| keys << a }
      end
      assert_equal [2], keys.map(&:size)
      assert_equal ["key1"], keys.map(&:first)
      assert_in_delta Win32::Registry.time2wtime(Time.now), keys[0][1], 10_000_000_000, "wtime should roughly match Time.now"
    end

    def test_each_key_enum
      keys = nil
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        reg.create("key2", *@createopts)
        reg.create("key3", *@createopts)
        reg["value1"] = "abcd"
        keys = reg.each_key.to_a
      end
      assert_equal 3, keys.size
      assert_equal [2, 2, 2], keys.map(&:size)
      assert_equal ["key1", "key2", "key3"], keys.map(&:first)
    end

    def test_values
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        reg["value1"] = "abcd"
        assert_equal ["abcd"], reg.values
      end
    end

    def test_each_value
      vals = []
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        reg["value1"] = "abcd"
        reg.each_value { |*a| vals << a }
      end
      assert_equal [["value1", Win32::Registry::REG_SZ, "abcd"]], vals
    end

    def test_each_value_enum
      vals = nil
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("key1", *@createopts)
        reg["value1"] = "abcd"
        reg["value2"] = 42
        vals = reg.each_value.to_a
      end
      assert_equal [["value1", Win32::Registry::REG_SZ, "abcd"],
                    ["value2", Win32::Registry::REG_DWORD, 42]], vals
    end

    def test_utf8_encoding
      keys = []
      Win32::Registry::HKEY_CURRENT_USER.create(@test_registry_key, *@createopts) do |reg|
        reg.create("abc EUR", *@createopts)
        reg.create("abc €", *@createopts)
        reg.each_key do |subkey|
          keys << subkey
        end
      end

      assert_equal [Encoding::UTF_8] * 2, keys.map(&:encoding)
      assert_equal ["abc EUR", "abc €"], keys
    end

    private

    def assert_predefined_key(key)
      assert_kind_of Win32::Registry, key
      assert_predicate key, :open?
      refute_predicate key, :created?
    end
  end
end
