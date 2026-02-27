///|
extern "js" fn js_text_decode(data : FixedArray[Byte], encoding : String) -> String =
  #| (data, encoding) => {
  #|   try { return new TextDecoder(encoding).decode(new Uint8Array(data)); }
  #|   catch(_) { return Array.from(data, b => String.fromCharCode(b)).join(''); }
  #| }
