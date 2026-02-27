///|
test "FlateErrorCode::code() UnexpectedEOF" {
  assert_eq(@types.FlateErrorCode::UnexpectedEOF.code(), 0)
}

///|
test "FlateErrorCode::code() InvalidBlockType" {
  assert_eq(@types.FlateErrorCode::InvalidBlockType.code(), 1)
}

///|
test "FlateErrorCode::code() InvalidLengthLiteral" {
  assert_eq(@types.FlateErrorCode::InvalidLengthLiteral.code(), 2)
}

///|
test "FlateErrorCode::code() InvalidDistance" {
  assert_eq(@types.FlateErrorCode::InvalidDistance.code(), 3)
}

///|
test "FlateErrorCode::code() StreamFinished" {
  assert_eq(@types.FlateErrorCode::StreamFinished.code(), 4)
}

///|
test "FlateErrorCode::code() NoStreamHandler" {
  assert_eq(@types.FlateErrorCode::NoStreamHandler.code(), 5)
}

///|
test "FlateErrorCode::code() InvalidHeader" {
  assert_eq(@types.FlateErrorCode::InvalidHeader.code(), 6)
}

///|
test "FlateErrorCode::code() NoCallback" {
  assert_eq(@types.FlateErrorCode::NoCallback.code(), 7)
}

///|
test "FlateErrorCode::code() InvalidUTF8" {
  assert_eq(@types.FlateErrorCode::InvalidUTF8.code(), 8)
}

///|
test "FlateErrorCode::code() ExtraFieldTooLong" {
  assert_eq(@types.FlateErrorCode::ExtraFieldTooLong.code(), 9)
}

///|
test "FlateErrorCode::code() InvalidDate" {
  assert_eq(@types.FlateErrorCode::InvalidDate.code(), 10)
}

///|
test "FlateErrorCode::code() FilenameTooLong" {
  assert_eq(@types.FlateErrorCode::FilenameTooLong.code(), 11)
}

///|
test "FlateErrorCode::code() StreamFinishing" {
  assert_eq(@types.FlateErrorCode::StreamFinishing.code(), 12)
}

///|
test "FlateErrorCode::code() InvalidZipData" {
  assert_eq(@types.FlateErrorCode::InvalidZipData.code(), 13)
}

///|
test "FlateErrorCode::code() UnknownCompressionMethod" {
  assert_eq(@types.FlateErrorCode::UnknownCompressionMethod.code(), 14)
}
