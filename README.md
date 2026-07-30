# image

`Nanaloveyuki/image` is Orbit's lightweight pure MoonBit image companion. It
decodes PNG into RGBA8, resizes in premultiplied-alpha space, deterministically
encodes PNG, and assembles ICO and ICNS containers. All APIs accept and return
`Bytes`; the library has no filesystem or CLI surface and links no native image
library. New capabilities are added only for a concrete Orbit requirement.

## Install

After the package is published to MoonCake, add it to a MoonBit module:

```powershell
moon add Nanaloveyuki/image
```

Import the root package from the consuming package's `moon.pkg`:

```text
import {
  "Nanaloveyuki/image",
}
```

## Decode and Encode PNG

`decode_png` verifies every PNG chunk CRC and the zlib checksum before returning
an `Image`. It applies limits before allocation and streams decompression into a
bounded output buffer.

```mbt
fn normalize_icon(source : Bytes) -> Bytes raise @image.ImageError {
  let image = @image.decode_png(source)
  let square = @image.square_image(image)
  let resized = @image.resize_lanczos3(square, 256, 256)
  @image.encode_png(resized, compression_level=6)
}
```

The decoder accepts non-interlaced 8-bit grayscale, palette, RGB,
grayscale-alpha, and RGBA PNGs. Unsupported PNG layouts return `ImageError`;
they are never partially decoded. Use `default_decode_limits()` as the baseline
or pass a narrower `DecodeLimits` value to `decode_png`.

`encode_png` emits exactly `IHDR`, `IDAT`, and `IEND`, so output is stable for a
fixed library version, source image, and compression level.

## Generate Icons

Icon encoders require a square source image by default. This makes source image
requirements explicit; `square_image(image, policy=CenterCrop)` is available when
the caller deliberately wants center cropping.

```mbt
fn icon_artifacts(source : Bytes) -> (Bytes, Bytes, Array[@image.PngVariant]) raise @image.ImageError {
  let image = @image.square_image(@image.decode_png(source))
  let pngs = @image.encode_png_sizes(image, [16, 32, 64, 128, 256])
  let ico = @image.encode_ico(image)
  let icns = @image.encode_icns(image)
  (ico, icns, pngs)
}
```

`encode_ico` defaults to 16/24/32/48/64/128/256 PNG entries. `encode_icns`
defaults to 16 through 1024 and emits the matching Retina ICNS PNG chunk types.
Writing returned bytes to project-specific paths is the caller's responsibility.

## SVG Wrapper

`png_data_uri_svg(png, width, height)` wraps an existing PNG as a base64 data URI
inside SVG. It does not vectorize pixels and is not used by the icon encoders.

## Development

See [docs/development.md](docs/development.md) for local validation, API-change
requirements, and contribution review rules.
