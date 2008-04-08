require 'cmath'

Object.instance_eval{remove_const :Math}
Math = CMath
