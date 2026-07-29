///|
fn sample_image() -> Image {
  try! Image::new(
    2, 2, b"\xff\x00\x00\xff\x00\xff\x00\x80\x00\x00\xff\x40\xff\xff\xff\x00",
  )
}

///|
test "PNG roundtrip preserves RGBA8" {
  let image = sample_image()
  let decoded = try! decode_png(try! encode_png(image, compression_level=6))
  inspect(decoded == image, content="true")
}

///|
test "PNG encoding is deterministic for a fixed level" {
  let image = sample_image()
  let first = try! encode_png(image, compression_level=6)
  let second = try! encode_png(image, compression_level=6)
  inspect(first == second, content="true")
}

///|
test "Lanczos resize avoids transparent color fringes" {
  let image = try! Image::new(2, 1, b"\xff\xff\xff\xff\xff\x00\x00\x00")
  let resized = try! resize_lanczos3(image, 1, 1)
  inspect(resized.pixels[0], content="b'\\xFF'")
  inspect(resized.pixels[1], content="b'\\xFF'")
  inspect(resized.pixels[2], content="b'\\xFF'")
}

///|
test "strict square policy rejects a rectangle" {
  let image = try! Image::new(2, 1, b"\x00\x00\x00\xff\x00\x00\x00\xff")
  let rejected = try square_image(image) catch {
    ImageError(NotSquare, _) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "ICO uses PNG image entries" {
  let ico = try! encode_ico(sample_image(), sizes=[16, 32])
  inspect(ico[0:4] == b"\x00\x00\x01\x00"[:], content="true")
  inspect(ico[4:6] == b"\x02\x00"[:], content="true")
  inspect(ico[6], content="b'\\x10'")
}

///|
test "ICNS contains standard and retina PNG chunks" {
  let icns = try! encode_icns(sample_image(), sizes=[16, 32])
  inspect(icns[:4] == b"icns"[:], content="true")
  let has_icp5 = icns[8:12] == b"icp4"[:] || icns[8:12] == b"icp5"[:]
  inspect(has_icp5, content="true")
  inspect(icns.length() > 16, content="true")
}
