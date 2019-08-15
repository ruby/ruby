require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

platform_is pointer_size: 64 do
  describe "Array#pack with format 'J'" do
    it_behaves_like :array_pack_basic, 'J'
    it_behaves_like :array_pack_basic_non_float, 'J'
    it_behaves_like :array_pack_arguments, 'J'
    it_behaves_like :array_pack_numeric_basic, 'J'
    it_behaves_like :array_pack_integer, 'J'
  end

  describe "Array#pack with format 'j'" do
    it_behaves_like :array_pack_basic, 'j'
    it_behaves_like :array_pack_basic_non_float, 'j'
    it_behaves_like :array_pack_arguments, 'j'
    it_behaves_like :array_pack_numeric_basic, 'j'
    it_behaves_like :array_pack_integer, 'j'
  end

  little_endian do
    describe "Array#pack with format 'J'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_64bit_le, 'J_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_64bit_le, 'J!'
      end
    end

    describe "Array#pack with format 'j'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_64bit_le, 'j_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_64bit_le, 'j!'
      end
    end
  end

  big_endian do
    describe "Array#pack with format 'J'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_64bit_be, 'J_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_64bit_be, 'J!'
      end
    end

    describe "Array#pack with format 'j'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_64bit_be, 'j_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_64bit_be, 'j!'
      end
    end
  end

  describe "Array#pack with format 'J'" do
    describe "with modifier '<' and '_'" do
      it_behaves_like :array_pack_64bit_le, 'J<_'
      it_behaves_like :array_pack_64bit_le, 'J_<'
    end

    describe "with modifier '<' and '!'" do
      it_behaves_like :array_pack_64bit_le, 'J<!'
      it_behaves_like :array_pack_64bit_le, 'J!<'
    end

    describe "with modifier '>' and '_'" do
      it_behaves_like :array_pack_64bit_be, 'J>_'
      it_behaves_like :array_pack_64bit_be, 'J_>'
    end

    describe "with modifier '>' and '!'" do
      it_behaves_like :array_pack_64bit_be, 'J>!'
      it_behaves_like :array_pack_64bit_be, 'J!>'
    end
  end

  describe "Array#pack with format 'j'" do
    describe "with modifier '<' and '_'" do
      it_behaves_like :array_pack_64bit_le, 'j<_'
      it_behaves_like :array_pack_64bit_le, 'j_<'
    end

    describe "with modifier '<' and '!'" do
      it_behaves_like :array_pack_64bit_le, 'j<!'
      it_behaves_like :array_pack_64bit_le, 'j!<'
    end

    describe "with modifier '>' and '_'" do
      it_behaves_like :array_pack_64bit_be, 'j>_'
      it_behaves_like :array_pack_64bit_be, 'j_>'
    end

    describe "with modifier '>' and '!'" do
      it_behaves_like :array_pack_64bit_be, 'j>!'
      it_behaves_like :array_pack_64bit_be, 'j!>'
    end
  end
end

platform_is pointer_size: 32 do
  describe "Array#pack with format 'J'" do
    it_behaves_like :array_pack_basic, 'J'
    it_behaves_like :array_pack_basic_non_float, 'J'
    it_behaves_like :array_pack_arguments, 'J'
    it_behaves_like :array_pack_numeric_basic, 'J'
    it_behaves_like :array_pack_integer, 'J'
  end

  describe "Array#pack with format 'j'" do
    it_behaves_like :array_pack_basic, 'j'
    it_behaves_like :array_pack_basic_non_float, 'j'
    it_behaves_like :array_pack_arguments, 'j'
    it_behaves_like :array_pack_numeric_basic, 'j'
    it_behaves_like :array_pack_integer, 'j'
  end

  big_endian do
    describe "Array#pack with format 'J'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_32bit_be, 'J_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_32bit_be, 'J!'
      end
    end

    describe "Array#pack with format 'j'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_32bit_be, 'j_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_32bit_be, 'j!'
      end
    end
  end

  little_endian do
    describe "Array#pack with format 'J'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_32bit_le, 'J_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_32bit_le, 'J!'
      end
    end

    describe "Array#pack with format 'j'" do
      describe "with modifier '_'" do
        it_behaves_like :array_pack_32bit_le, 'j_'
      end

      describe "with modifier '!'" do
        it_behaves_like :array_pack_32bit_le, 'j!'
      end
    end
  end

  describe "Array#pack with format 'J'" do
    describe "with modifier '<' and '_'" do
      it_behaves_like :array_pack_32bit_le, 'J<_'
      it_behaves_like :array_pack_32bit_le, 'J_<'
    end

    describe "with modifier '<' and '!'" do
      it_behaves_like :array_pack_32bit_le, 'J<!'
      it_behaves_like :array_pack_32bit_le, 'J!<'
    end

    describe "with modifier '>' and '_'" do
      it_behaves_like :array_pack_32bit_be, 'J>_'
      it_behaves_like :array_pack_32bit_be, 'J_>'
    end

    describe "with modifier '>' and '!'" do
      it_behaves_like :array_pack_32bit_be, 'J>!'
      it_behaves_like :array_pack_32bit_be, 'J!>'
    end
  end

  describe "Array#pack with format 'j'" do
    describe "with modifier '<' and '_'" do
      it_behaves_like :array_pack_32bit_le, 'j<_'
      it_behaves_like :array_pack_32bit_le, 'j_<'
    end

    describe "with modifier '<' and '!'" do
      it_behaves_like :array_pack_32bit_le, 'j<!'
      it_behaves_like :array_pack_32bit_le, 'j!<'
    end

    describe "with modifier '>' and '_'" do
      it_behaves_like :array_pack_32bit_be, 'j>_'
      it_behaves_like :array_pack_32bit_be, 'j_>'
    end

    describe "with modifier '>' and '!'" do
      it_behaves_like :array_pack_32bit_be, 'j>!'
      it_behaves_like :array_pack_32bit_be, 'j!>'
    end
  end
end
