///|
fn js_text_decode(data : FixedArray[Byte], _encoding : String) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < data.length(); i = i + 1 {
    sb.write_char(data[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}
