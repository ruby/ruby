module ReadableFizzBuzz
  module Chain
  end
end

include ReadableFizzBuzz

Chain::Itself = Chain

module Chain::Itself
  module Void
    A = B = C = D = E = F = G = H = I = J = K = L = M = Void
    N = O = P = Q = R = S = T = U = V = W = X = Y = Z = Void

    module Set
    end

    module Put
    end

    module WriteBack
    end

    module Not
      include Void
    end
  end

  module Off
    include Void
  end

  module Nil
    A = B = C = D = E = F = G = H = I = J = K = L = M = Off
    N = O = P = Q = R = S = T = U = V = W = X = Y = Z = Off
  end

  module Next
    include Nil
  end

  module Current
    include Nil

    Not = Off
    Set = Put = Next
    WriteBack = Current
  end

  True = If = Current
  On = Next

  module On
    INT = 1
    FIZZ = 'Fizz'
    BUZZ = 'Buzz'
    PREFIX = '0b'
    FORMAT = "%d%s%s\n"
    NEXT = __FILE__
  end

  module Off
    INT = 0
    FIZZ = BUZZ = nil
    PREFIX = '0b1'
    FORMAT = "%2$s%3$s\n"
    NEXT = '/dev/null'
    Not = True
  end

  module Initial
    C = D = True
  end

  module ReadableFizzBuzz::Chain::Current
    include Initial
  end

  If::C::Set::E = If::E::Set::F = If::F::Set::C = On
  If::D::Set::G = If::G::Set::H = If::H::Set::I = If::I::Set::J = If::J::Set::D = On
  If::F::Not::J::Not::Set::B = On
  If::K::Not::Set::K = On
  If::K::WriteBack::L = True
  If::L::Not::M::Set::M = On
  If::L::M::Not::Put::M = On
  If::L::M::WriteBack::N = True
  If::N::Not::O::Set::O = On
  If::N::O::Not::Put::O = On
  If::N::O::WriteBack::P = True
  If::P::Not::Q::Set::Q = On
  If::P::Q::Not::Put::Q = On
  If::P::Q::WriteBack::R = True
  If::R::Not::S::Set::S = On
  If::R::S::Not::Put::S = On
  If::R::S::WriteBack::T = True
  If::T::Not::U::Set::U = On
  If::T::U::Not::Put::U = On
  If::T::U::WriteBack::V = True
  If::V::Not::W::Set::W = On
  If::V::W::Not::Put::W = On
  If::V::W::WriteBack::X = True
  If::X::Not::Y::Set::Y = On
  If::X::Y::Not::Put::Y = On
  If::X::Y::WriteBack::Z = True
  If::Z::Not::Set::A = On
end

module Chain::Chain
  Current = Chain::Next
end

include Chain

module Chain::Current
  NUMBER = A::PREFIX, Y::INT, W::INT, U::INT, S::INT, Q::INT, O::INT, M::INT, K::INT
  printf B::FORMAT, NUMBER.join, C::FIZZ, D::BUZZ
  load A::NEXT
end
