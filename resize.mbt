///|
pub(all) enum SquarePolicy {
  Strict
  CenterCrop
} derive(Eq, Debug)

///|
/// Return a square source image. `Strict` rejects a non-square input; the
/// opt-in crop policy retains the centered square region.
pub fn square_image(
  image : Image,
  policy? : SquarePolicy = Strict,
) -> Image raise ImageError {
  if image.is_square() {
    return image
  }
  if policy is Strict {
    raise ImageError(NotSquare, "square image required")
  }
  let side = if image.width < image.height { image.width } else { image.height }
  let left = (image.width - side) / 2
  let top = (image.height - side) / 2
  let pixels = Array::make(side * side * 4, b'\x00')
  for y in 0..<side {
    let src = ((top + y) * image.width + left) * 4
    let dst = y * side * 4
    for x in 0..<(side * 4) {
      pixels[dst + x] = image.pixels[src + x]
    }
  }
  Image::new(side, side, Bytes::from_array(pixels))
}

///|
fn lanczos_kernel(x : Double) -> Double {
  let ax = if x < 0.0 { -x } else { x }
  if ax >= 3.0 {
    return 0.0
  }
  if ax < 0.0000001 {
    return 1.0
  }
  let p = @math.PI
  3.0 * @math.sin(p * ax) * @math.sin(p * ax / 3.0) / (p * p * ax * ax)
}

///|
fn clamp_byte(value : Double) -> Byte {
  let rounded = @math.floor(value + 0.5).to_int()
  (if rounded < 0 { 0 } else if rounded > 255 { 255 } else { rounded }).to_byte()
}

///|
/// Resize RGBA8 pixels with a Lanczos3 reconstruction filter in premultiplied
/// alpha space. Premultiplication prevents transparent colors from producing
/// dark fringes after resampling.
pub fn resize_lanczos3(
  image : Image,
  width : Int,
  height : Int,
) -> Image raise ImageError {
  if width <= 0 ||
    height <= 0 ||
    width > 0x3fffffff / height ||
    width * height > 64 * 1024 * 1024 {
    raise ImageError(InvalidDimensions, "resize dimensions are invalid")
  }
  if image.width == width && image.height == height {
    return image
  }
  let result = Array::make(width * height * 4, b'\x00')
  let sx = image.width.to_double() / width.to_double()
  let sy = image.height.to_double() / height.to_double()
  let scale_x = if sx > 1.0 { sx } else { 1.0 }
  let scale_y = if sy > 1.0 { sy } else { 1.0 }
  let radius_x = (3.0 * scale_x).to_int() + 1
  let radius_y = (3.0 * scale_y).to_int() + 1
  for y in 0..<height {
    let center_y = (y.to_double() + 0.5) * sy - 0.5
    let first_y = @math.floor(center_y - radius_y.to_double()).to_int()
    let last_y = @math.ceil(center_y + radius_y.to_double()).to_int()
    let end_y = last_y + 1
    for x in 0..<width {
      let center_x = (x.to_double() + 0.5) * sx - 0.5
      let first_x = @math.floor(center_x - radius_x.to_double()).to_int()
      let last_x = @math.ceil(center_x + radius_x.to_double()).to_int()
      let end_x = last_x + 1
      let mut weight_sum = 0.0
      let mut r = 0.0
      let mut g = 0.0
      let mut b = 0.0
      let mut a = 0.0
      for iy in first_y..<end_y {
        if iy >= 0 && iy < image.height {
          let wy = lanczos_kernel((center_y - iy.to_double()) / scale_y)
          for ix in first_x..<end_x {
            if ix >= 0 && ix < image.width {
              let weight = wy *
                lanczos_kernel((center_x - ix.to_double()) / scale_x)
              let source = (iy * image.width + ix) * 4
              let alpha = image.pixels[source + 3].to_int().to_double() / 255.0
              r = r + image.pixels[source].to_int().to_double() * alpha * weight
              g = g +
                image.pixels[source + 1].to_int().to_double() * alpha * weight
              b = b +
                image.pixels[source + 2].to_int().to_double() * alpha * weight
              a = a + alpha * weight
              weight_sum = weight_sum + weight
            }
          }
        }
      }
      let output = (y * width + x) * 4
      let normalized_a = if weight_sum == 0.0 { 0.0 } else { a / weight_sum }
      result[output + 3] = clamp_byte(normalized_a * 255.0)
      if a == 0.0 {
        result[output] = b'\x00'
        result[output + 1] = b'\x00'
        result[output + 2] = b'\x00'
      } else {
        result[output] = clamp_byte(r / a)
        result[output + 1] = clamp_byte(g / a)
        result[output + 2] = clamp_byte(b / a)
      }
    }
  }
  Image::new(width, height, Bytes::from_array(result))
}

///|
pub(all) struct PngVariant {
  size : Int
  png : Bytes
}

///|
/// Encode caller-selected square PNG icon sizes in the requested order.
pub fn encode_png_sizes(
  image : Image,
  sizes : Array[Int],
  compression_level? : Int = 6,
) -> Array[PngVariant] raise ImageError {
  checked_square(image)
  let output = []
  for size in sizes {
    if size <= 0 {
      raise ImageError(InvalidDimensions, "PNG output size must be positive")
    }
    let resized = resize_lanczos3(image, size, size)
    output.push({ size, png: encode_png(resized, compression_level~) })
  }
  output
}
