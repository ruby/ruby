require 'date'
require_relative '../../spec_helper'

describe "Date.ordinal" do
  it "constructs a Date object from an ordinal date" do
    # October 1582 (the Gregorian calendar, Ordinal Date)
    #   S   M  Tu   W  Th   F   S
    #     274 275 276 277 278 279
    # 280 281 282 283 284 285 286
    # 287 288 289 290 291 292 293
    # 294
    Date.ordinal(1582, 274).should == Date.civil(1582, 10,  1)
    Date.ordinal(1582, 277).should == Date.civil(1582, 10,  4)
    Date.ordinal(1582, 278).should == Date.civil(1582, 10, 15)
    Date.ordinal(1582, 287, Date::ENGLAND).should == Date.civil(1582, 10, 14, Date::ENGLAND)
  end
end
