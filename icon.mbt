///|
pub fn default_ico_sizes() -> Array[Int] {
  [16, 24, 32, 48, 64, 128, 256]
}

///|
pub fn default_icns_sizes() -> Array[Int] {
  [16, 32, 64, 128, 256, 512, 1024]
}

///|
/// Encode an ICO whose directory entries point to PNG payloads.
pub fn encode_ico(
  image : Image,
  sizes? : Array[Int] = default_ico_sizes(),
  compression_level? : Int = 6,
) -> Bytes raise ImageError {
  let variants = encode_png_sizes(image, sizes, compression_level~)
  if variants.length() == 0 || variants.length() > 65535 {
    raise ImageError(InvalidInput, "ICO requires between one and 65535 images")
  }
  let out = Buffer()
  write_u16_le(out, 0)
  write_u16_le(out, 1)
  write_u16_le(out, variants.length())
  let mut offset = 6 + variants.length() * 16
  for variant in variants {
    if variant.size > 256 {
      raise ImageError(InvalidDimensions, "ICO image size exceeds 256")
    }
    out.write_byte(
      (if variant.size == 256 { 0 } else { variant.size }).to_byte(),
    )
    out.write_byte(
      (if variant.size == 256 { 0 } else { variant.size }).to_byte(),
    )
    out.write_byte(b'\x00')
    out.write_byte(b'\x00')
    write_u16_le(out, 1)
    write_u16_le(out, 32)
    write_u32_le(out, variant.png.length())
    write_u32_le(out, offset)
    offset = offset + variant.png.length()
  }
  for variant in variants {
    out.write_bytes(variant.png[:])
  }
  out.to_bytes()
}

///|
fn icns_types(size : Int) -> Array[Bytes] raise ImageError {
  match size {
    16 => [b"icp4"]
    32 => [b"icp5", b"ic11"]
    64 => [b"icp6", b"ic12"]
    128 => [b"ic07"]
    256 => [b"ic08", b"ic13"]
    512 => [b"ic09", b"ic14"]
    1024 => [b"ic10"]
    _ => raise ImageError(InvalidDimensions, "unsupported ICNS PNG size")
  }
}

///|
/// Encode a deterministic ICNS containing PNG chunks for standard macOS icon
/// sizes and their Retina chunk counterparts.
pub fn encode_icns(
  image : Image,
  sizes? : Array[Int] = default_icns_sizes(),
  compression_level? : Int = 6,
) -> Bytes raise ImageError {
  let variants = encode_png_sizes(image, sizes, compression_level~)
  if variants.length() == 0 {
    raise ImageError(InvalidInput, "ICNS requires at least one image")
  }
  let chunks = Buffer()
  for variant in variants {
    for kind in icns_types(variant.size) {
      chunks.write_bytes(kind[:])
      write_u32_be(chunks, variant.png.length() + 8)
      chunks.write_bytes(variant.png[:])
    }
  }
  let out = Buffer()
  out.write_bytes(b"icns")
  write_u32_be(out, chunks.length() + 8)
  out.write_bytes(chunks.to_bytes()[:])
  out.to_bytes()
}

///|
fn base64_digit(index : Int) -> Byte {
  b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[index]
}

///|
/// Wrap a PNG byte sequence in a portable data-URI SVG image element.
pub fn png_data_uri_svg(
  png : Bytes,
  width : Int,
  height : Int,
) -> String raise ImageError {
  if width <= 0 || height <= 0 {
    raise ImageError(InvalidDimensions, "SVG dimensions must be positive")
  }
  let encoded = Buffer()
  let mut index = 0
  while index < png.length() {
    let remaining = png.length() - index
    let a = png[index].to_int()
    let b = if remaining > 1 { png[index + 1].to_int() } else { 0 }
    let c = if remaining > 2 { png[index + 2].to_int() } else { 0 }
    encoded.write_byte(base64_digit(a >> 2))
    encoded.write_byte(base64_digit(((a & 3) << 4) | (b >> 4)))
    encoded.write_byte(
      if remaining > 1 {
        base64_digit(((b & 15) << 2) | (c >> 6))
      } else {
        b'='
      },
    )
    encoded.write_byte(if remaining > 2 { base64_digit(c & 63) } else { b'=' })
    index = index + 3
  }
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\"><image width=\"100%\" height=\"100%\" href=\"data:image/png;base64,{encoded.to_bytes().to_unchecked_string()}\"/></svg>"
}
