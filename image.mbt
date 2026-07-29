///|
/// RGBA8 image data in row-major order.
pub(all) struct Image {
  width : Int
  height : Int
  pixels : Bytes
} derive(Eq)

///|
/// Limits applied before allocating decoded image buffers.
pub(all) struct DecodeLimits {
  max_input_bytes : Int
  max_dimension : Int
  max_pixels : Int
}

///|
/// Default limits: 64 MiB compressed input, 16,384 pixels per edge, 64 MiB RGBA.
pub fn default_decode_limits() -> DecodeLimits {
  {
    max_input_bytes: 64 * 1024 * 1024,
    max_dimension: 16384,
    max_pixels: 16 * 1024 * 1024,
  }
}

///|
pub(all) enum ImageErrorKind {
  InvalidInput
  ResourceLimit
  UnsupportedFormat
  InvalidDimensions
  NotSquare
} derive(Eq, Debug)

///|
pub suberror ImageError {
  ImageError(ImageErrorKind, String)
}

///|
/// Construct a checked RGBA8 image.
pub fn Image::new(
  width : Int,
  height : Int,
  pixels : Bytes,
) -> Image raise ImageError {
  if width <= 0 || height <= 0 || width > 0x3fffffff / height {
    raise ImageError(InvalidDimensions, "image dimensions are invalid")
  }
  let expected = width * height
  if expected > 0x3fffffff / 4 || pixels.length() != expected * 4 {
    raise ImageError(
      InvalidDimensions,
      "RGBA8 buffer length does not match dimensions",
    )
  }
  { width, height, pixels }
}

///|
pub fn Image::is_square(self : Image) -> Bool {
  self.width == self.height
}

///|
fn checked_square(image : Image) -> Unit raise ImageError {
  if !image.is_square() {
    raise ImageError(NotSquare, "icon encoders require a square image")
  }
}

///|
fn u32_be(data : BytesView, offset : Int) -> Int {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
fn write_u16_le(out : Buffer, value : Int) -> Unit {
  out.write_byte((value & 0xff).to_byte())
  out.write_byte(((value >> 8) & 0xff).to_byte())
}

///|
fn write_u32_le(out : Buffer, value : Int) -> Unit {
  for shift = 0; shift < 32; shift = shift + 8 {
    out.write_byte(((value >> shift) & 0xff).to_byte())
  }
}

///|
fn write_u32_be(out : Buffer, value : Int) -> Unit {
  out.write_byte(((value >> 24) & 0xff).to_byte())
  out.write_byte(((value >> 16) & 0xff).to_byte())
  out.write_byte(((value >> 8) & 0xff).to_byte())
  out.write_byte((value & 0xff).to_byte())
}

///|
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = (p - a).abs()
  let pb = (p - b).abs()
  let pc = (p - c).abs()
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}
