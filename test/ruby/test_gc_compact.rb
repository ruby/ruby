# frozen_string_literal: true
require 'test/unit'
require 'fiddle'

class TestGCCompact < Test::Unit::TestCase
  def memory_location(obj)
    (Fiddle.dlwrap(obj) >> 1)
  end

  def assert_object_ids(list)
    same_count = list.find_all { |obj|
      memory_location(obj) == obj.object_id
    }.count
    list.count - same_count
  end

  def big_list(level = 10)
    if level > 0
      big_list(level - 1)
    else
      1000.times.map {
        # try to make some empty slots by allocating an object and discarding
        Object.new
        Object.new
      } # likely next to each other
    end
  end

  # Find an object that's allocated in a slot that had a previous
  # tenant, and that tenant moved and is still alive
  def find_object_in_recycled_slot(addresses)
    new_object = nil

    100_000.times do
      new_object = Object.new
      if addresses.index memory_location(new_object)
        break
      end
    end

    new_object
  end

  def try_to_move_objects
    10.times do
      list_of_objects = big_list

      ids       = list_of_objects.map(&:object_id) # store id in map
      addresses = list_of_objects.map(&self.:memory_location)

      assert_equal ids, addresses

      # All object ids should be equal
      assert_equal 0, assert_object_ids(list_of_objects) # should be 0

      GC.verify_compaction_references(toward: :empty)

      # Some should have moved
      id_count = assert_object_ids(list_of_objects)
      skip "couldn't get objects to move" if id_count == 0
      assert_operator id_count, :>, 0

      new_ids = list_of_objects.map(&:object_id)

      # Object ids should not change after compaction
      assert_equal ids, new_ids

      new_tenant = find_object_in_recycled_slot(addresses)
      return [list_of_objects, addresses, new_tenant] if new_tenant
    end

    flunk "Couldn't get objects to move"
  end

  def test_find_collided_object
    skip "figure out how to guarantee move"

    list_of_objects, addresses, new_tenant = try_to_move_objects

    # This is the object that used to be in new_object's position
    loc = memory_location(new_tenant)
    assert loc, "should have a memory location"

    if (ENV['TRAVIS'] && RUBY_PLATFORM =~ /darwin/)
      skip "tests are failing on Travis osx / Wercker from here"
    end

    address_idx = addresses.index(loc)
    assert address_idx, "should have an address index"

    previous_tenant = list_of_objects[address_idx]
    assert previous_tenant, "should have a previous tenant"

    assert_not_equal previous_tenant.object_id, new_tenant.object_id

    # Should be able to look up object by object_id
    assert_equal new_tenant, ObjectSpace._id2ref(new_tenant.object_id)

    # Should be able to look up object by object_id
    assert_equal previous_tenant, ObjectSpace._id2ref(previous_tenant.object_id)

    int = (new_tenant.object_id >> 1)
    # These two should be the same! but they are not :(
    assert_equal int, ObjectSpace._id2ref(int.object_id)
  end

  def test_many_collisions
    list_of_objects = big_list
    ids       = list_of_objects.map(&:object_id)
    addresses = list_of_objects.map(&self.:memory_location)

    GC.verify_compaction_references(toward: :empty)

    skip "time consuming"

    new_tenants = 10.times.map {
      find_object_in_recycled_slot(addresses)
    }

    collisions = GC.stat(:object_id_collisions)
    skip "couldn't get objects to collide" if collisions == 0
    assert_operator collisions, :>, 0
    ids.clear
    new_tenants.clear
  end

  def test_complex_hash_keys
    list_of_objects = big_list
    hash = list_of_objects.hash
    GC.verify_compaction_references(toward: :empty)
    assert_equal hash, list_of_objects.hash
  end
end
