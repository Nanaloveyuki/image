///|
/// RGBA8 image data in row-major order.
#derive(Eq)
pub(all) struct Image {
  width : Int32
  height : Int32
  pixels : Bytes
}

///|
pub extend Image with Eq::{not_equal, equal}

///|
/// Limits applied before allocating decoded image buffers.
pub(all) struct DecodeLimits {
  max_input_bytes : Int32
  max_dimension : Int32
  max_pixels : Int32
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
#derive(Eq, Debug)
pub(all) enum ImageErrorKind {
  InvalidInput
  ResourceLimit
  UnsupportedFormat
  InvalidDimensions
  NotSquare
}

///|
pub extend ImageErrorKind with Eq::{not_equal, equal}

///|
pub extend ImageErrorKind with Debug::{to_repr}

///|
pub suberror ImageError {
  ImageError(ImageErrorKind, String)
}

///|
/// Construct a checked RGBA8 image.
pub fn Image::new(
  width : Int32,
  height : Int32,
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
  { width, height, pixels, }
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
fn u32_be(data : BytesView, offset : Int32) -> Int32 {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
fn write_u16_le(out : Buffer, value : Int32) -> Unit {
  out.write_uint16_le(value.reinterpret_as_uint().to_uint16())
}

///|
fn write_u32_le(out : Buffer, value : Int32) -> Unit {
  out.write_uint_le(value.reinterpret_as_uint())
}

///|
fn write_u32_be(out : Buffer, value : Int32) -> Unit {
  out.write_uint_be(value.reinterpret_as_uint())
}

///|
fn paeth(a : Int32, b : Int32, c : Int32) -> Int32 {
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
