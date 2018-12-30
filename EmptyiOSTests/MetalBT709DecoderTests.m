//
//  MetalBT709DecoderTests.m
//
//  Created by Mo DeJong on 12/13/18.
//

#import <XCTest/XCTest.h>

#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

#import "MetalBT709Decoder.h"

#import "BGRAToBT709Converter.h"

#import "CGFrameBuffer.h"

#import "MetalRenderContext.h"

@interface MetalBT709DecoderTests : XCTestCase

@end

static inline
BOOL
floatIsEqualEpsilion(float f1, float f2, float epsilion)
{
  float delta = f1 - f2;
  return (delta < epsilion);
}

static inline
BOOL
floatIsEqual(float f1, float f2)
{
  float epsilion = 0.001;
  return floatIsEqualEpsilion(f1, f2, epsilion);
}

static inline
uint32_t rgbToPixel(uint32_t R, uint32_t G, uint32_t B)
{
  uint32_t outPixel = (R << 16) | (G << 8) | B;
  return outPixel;
}

static inline
uint32_t rgbaToPixel(uint32_t R, uint32_t G, uint32_t B, uint32_t A)
{
  uint32_t outPixel = (A << 24) | (R << 16) | (G << 8) | B;
  return outPixel;
}

// Unpack a pixel and assign to variables

static inline
void pixelToRGBA(uint32_t inPixel, uint32_t * R, uint32_t * G, uint32_t* B, uint32_t * A)
{
  uint32_t c0 = (inPixel & 0xFF);
  uint32_t c1 = ((inPixel >> 8) & 0xFF);
  uint32_t c2 = ((inPixel >> 16) & 0xFF);
  uint32_t c3 = ((inPixel >> 16) & 0xFF);
 
  *B = c0;
  *G = c1;
  *R = c2;
  *A = c3;
}

static inline
uint32_t grayToPixel(uint32_t gray)
{
  return rgbaToPixel(gray, gray, gray, 0xFF);
}

@implementation MetalBT709DecoderTests

- (void)setUp {
  // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (BOOL) isExactlyTheSame:(int)R
                        G:(int)G
                        B:(int)B
                     decR:(int)decR
                     decG:(int)decG
                     decB:(int)decB
{
  return (B == decB) && (G == decG) && (R == decR);
}

// Is v2 close enough to v1 (+- delta), return TRUE if so

- (BOOL) isCloseEnough:(int)v1
                    v2:(int)v2
                 delta:(int)delta
{
  assert(delta > 0);
  
  int max = (v1 + delta);
  int min = (v1 - delta);
  
  if (v2 >= min && v2 <= max) {
    return TRUE;
  } else {
    return FALSE;
  }
}

- (BOOL) isOffBy:(int)R
               G:(int)G
               B:(int)B
            decR:(int)decR
            decG:(int)decG
            decB:(int)decB
           delta:(int)delta
{
  BOOL BClose = [self isCloseEnough:B v2:decB delta:delta];
  BOOL GClose = [self isCloseEnough:G v2:decG delta:delta];
  BOOL RClose = [self isCloseEnough:R v2:decR delta:delta];
  
  if (BClose == FALSE || GClose == FALSE || RClose == FALSE) {
    // One of these values is larger than +-1 delta
    return FALSE;
  } else {
    // All 3 values are close enough
    return TRUE;
  }
}

// Convert a BGRA pixel to XCrCbY packed into a uint32_t

- (uint32_t) convert_srgb_to_bt709:(uint32_t)sRGB
                              type:(BGRAToBT709ConverterTypeEnum)type
{
  const int debug = 1;
  
  uint32_t Rin, Gin, Bin, dummy;
  
  pixelToRGBA(sRGB, &Rin, &Gin, &Bin, &dummy);
  
  uint32_t Y, Cb, Cr;
  
  const int width = 2;
  const int height = 2;
  
  BOOL worked;
  
  uint32_t inBGRA[width*height];
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(inBGRA, 0, sizeof(inBGRA));
  memset(outBT709, 0, sizeof(outBT709));
  memset(outBGRA, 0, sizeof(outBGRA));
  
  // Init the first pixel value
  
  inBGRA[0] = rgbToPixel(Rin, Gin, Bin);
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  inBGRA[1] = inBGRA[0];
  inBGRA[2] = inBGRA[0];
  inBGRA[3] = inBGRA[0];
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  worked = [BGRAToBT709Converter convert:inBGRA outBT709Pixels:outBT709 width:width height:height type:type];
  XCTAssert(worked == TRUE, @"worked");
  
  uint32_t yuvOutPixel = outBT709[0];
  
  if (debug) {
    pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
    
    NSLog(@"R G B : (%d %d %d) -> Y Cb Cr : (%d %d %d)", Rin, Gin, Bin, Y, Cb, Cr);
  }
  
  return yuvOutPixel;
}

// Invoke metal shader and convert from BT.709 encoded pixel to RGB

- (uint32_t) convert_bt709_to_srgb:(uint32_t)bt709
                              type:(BGRAToBT709ConverterTypeEnum)type
{
  const int debug = 1;
  
  uint32_t Y, Cb, Cr, dummy;
  
  pixelToRGBA(bt709, &Cr, &Cb, &Y, &dummy);
  
  const int width = 2;
  const int height = 2;
  
  uint32_t outBT709[width*height];
  uint32_t outBGRA[width*height];
  
  memset(outBGRA, 0, sizeof(outBGRA));
  
  outBT709[0] = bt709;
  
  // Copy the same pixel value to the other 3 pixels so that subsampling
  // would see the identical value for all Cb and Cr inputs
  
  outBT709[1] = outBT709[0];
  outBT709[2] = outBT709[0];
  outBT709[3] = outBT709[0];
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;

  // Use Metal impl to convert BT709 data to BGRA
  
  MetalRenderContext *metalRenderContext = [[MetalRenderContext alloc] init];
  metalRenderContext.device = MTLCreateSystemDefaultDevice();
  
  MetalBT709Decoder *metalDecoder = [[MetalBT709Decoder alloc] init];
  
  metalDecoder.metalRenderContext = metalRenderContext;
  
  metalDecoder.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
  
  BOOL worked = [metalDecoder setupMetal];
  XCTAssert(worked, @"setupMetal");
  
  id<MTLTexture> bgraSRGBTexture = [metalRenderContext makeBGRATexture:CGSizeMake(width, height) pixels:NULL usage:MTLTextureUsageShaderWrite isSRGB:TRUE];
  
  CVPixelBufferRef yCbCrBuffer = [BGRAToBT709Converter createCoreVideoYCbCrBuffer:CGSizeMake(width, height)];
  
  [BGRAToBT709Converter setBT709Attributes:yCbCrBuffer];
  
  [BGRAToBT709Converter copyBT709ToCoreVideo:outBT709 cvPixelBuffer:yCbCrBuffer];
  
  id<MTLCommandBuffer> commandBuffer = [metalRenderContext.commandQueue commandBuffer];
  
  worked = [metalDecoder decodeBT709:yCbCrBuffer
                     bgraSRGBTexture:bgraSRGBTexture
                       commandBuffer:commandBuffer
                  waitUntilCompleted:TRUE];
  XCTAssert(worked, @"decodeBT709");
  
  CVPixelBufferRelease(yCbCrBuffer);
  
  NSData *pixelsAsBytes = [metalRenderContext getBGRATexturePixels:bgraSRGBTexture];
  
  memcpy(outBGRA, pixelsAsBytes.bytes, (int)pixelsAsBytes.length);
  
  // Convert back to BGRA
  
  uint32_t Rout, Gout, Bout;
  
  uint32_t bgraOutPixel = outBGRA[0];
  
  if (debug) {
    pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
    
    NSLog(@"Y Cb Cr : (%d %d %d) -> R G B : (%d %d %d)", Y, Cb, Cr, Rout, Gout, Bout);
  }
  
  return bgraOutPixel;
}

// Convert with C or vImage and then decode with Metal shader

- (void)testMetalBT709Decoder_Gray100Percent_0xFFFFFF {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray at 100% intensity
  //
  // sRGB (255 255 255) -> Linear RGB (255 255 255) -> REC.709 (235 128 128)
  
  Rin = 255;
  Gin = Rin;
  Bin = Rin;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 235;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Gray67Percent_0xAAAAAA {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray at 67% intensity
  //
  // sRGB (170 170 170) -> Linear RGB (103 103 103) -> REC.709 (154 128 128)
  
  Rin = 170;
  Gin = Rin;
  Bin = Rin;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 154;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Gray50Percent_0x808080 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray at 50% between black and white
  //
  // sRGB (128 128 128) -> Linear RGB (55 55 55) -> REC.709 (115 128 128)
  
  Rin = 128;
  Gin = Rin;
  Bin = Rin;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 115;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Gray33Percent_0x555555 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray at 33% between black and white
  //
  // sRGB (85 85 85) -> Linear RGB (23 23 23) -> REC.709 (76 128 128)
  
  Rin = 85;
  Gin = Rin;
  Bin = Rin;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 76;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_Gray0Percent_0x000000 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray at 0% between
  //
  // sRGB (0 0 0) -> Linear RGB (0 0 0) -> REC.709 (16 128 128)
  
  Rin = 0;
  Gin = Rin;
  Bin = Rin;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 16;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

// Blue Cyan Column

- (void)testMetalBT709Decoder_0x0000FF {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Blue at 100% intensity
  //
  // sRGB (0 0 255) -> Linear RGB (0 0 255) -> REC.709 (32 240 118)
  
  Rin = 0;
  Gin = 0;
  Bin = 255;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 32;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 240;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 118;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (2 0 255)
  
  {
    int v = Rout;
    int expectedVal = Rin + 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x0000AA {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Blue at 67% intensity
  //
  // sRGB (0 0 170) -> Linear RGB (0 0 103) -> REC.709 (26 199 122)
  
  Rin = 0;
  Gin = 0;
  Bin = 170;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 26;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 199;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 122;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (2 0 170)
  
  {
    int v = Rout;
    int expectedVal = Rin + 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x00FFFF {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Blue and Green at 100%
  //
  // sRGB (0 255 255) -> Linear RGB (0 255 255) -> REC.709 (188 154 16)
  
  Rin = 0;
  Gin = 255;
  Bin = 255;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 188;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 154;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 16;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (0 254 255)
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin - 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x005555 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Blue and Green at 33%
  //
  // sRGB (0 85 85) -> Linear RGB (0 23 23) -> REC.709 (63 135 97)
  
  Rin = 0;
  Gin = 85;
  Bin = 85;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 63;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 135;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 97;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (0 85 84)
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin - 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

// Green Yellow Row

- (void)testMetalBT709Decoder_0x00FF00 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Green at 100% intensity
  //
  // sRGB (0 255 0) -> Linear RGB (0 255 0) -> REC.709 (173 42 26)
  
  Rin = 0;
  Gin = 255;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 173;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 42;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 26;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (0 255 3)
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin + 3;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x00AA00 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Green at 67% intensity
  //
  // sRGB (0 170 0) -> Linear RGB (0 103 0) -> REC.709 (115 74 64)
  
  Rin = 0;
  Gin = 170;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 115;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    // C code returns 74 but vImage returns 74 (74 seems more correct)
    int expectedVal = 73;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 64;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (1 170 0)
  
  {
    int v = Rout;
    int expectedVal = Rin + 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0xFFFF00 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Yellow at 100% intensity
  //
  // sRGB (255 255 0) -> Linear RGB (255 255 0) -> REC.709 (219 16 138)
  
  Rin = 255;
  Gin = 255;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 219;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 16;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 138;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (254 255 0)
  
  {
    int v = Rout;
    int expectedVal = Rin - 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x555500 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Yellow at 33% intensity
  //
  // sRGB (85 85 0) -> Linear RGB (23 23 0) -> REC.709 (72 97 131)
  
  Rin = 85;
  Gin = 85;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 72;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 97;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 131;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

// Red Purple Row

- (void)testMetalBT709Decoder_0xFF0000 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Red at 100% intensity
  //
  // sRGB (255 0 0) -> Linear RGB (255 0 0) -> REC.709 (63 102 240)
  
  Rin = 255;
  Gin = 0;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 63;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 102;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 240;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  // Decoded (255 2 0)
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin + 2;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}


- (void)testMetalBT709Decoder_0xAA0000 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Red at 67% intensity
  //
  // sRGB (170 0 0) -> Linear RGB (103 0 0) -> REC.709 (45 112 199)
  
  Rin = 170;
  Gin = 0;
  Bin = 0;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 45;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 112;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 199;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0xFF00FF {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Red and Blue at 100% intensity (purple)
  //
  // sRGB (255 0 255) -> Linear RGB (255 0 255) -> REC.709 (78 214 230)
  
  Rin = 255;
  Gin = 0;
  Bin = 255;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 78;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 214;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 230;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin - 1;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

- (void)testMetalBT709Decoder_0x550055 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Red and Blue at 33% intensity (dark purple)
  //
  // sRGB (85 0 85) -> Linear RGB (23 0 23) -> REC.709 (33 152 156)
  
  Rin = 85;
  Gin = 0;
  Bin = 85;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 33;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 152;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 156;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

// SMPTE colorbars : gray (192 192 192) yellow (192 192 0) cyan (0 192 192)

- (void)testMetalBT709Decoder_SMPTE_Gray_0xc0c0c0 {
  uint32_t Rin, Gin, Bin;
  uint32_t Y, Cb, Cr, dummy;
  uint32_t Rout, Gout, Bout;
  
  // Gray 75% intensity
  //
  // sRGB (192 192 192) -> Linear RGB (134 134 134) -> REC.709 (175 128 128)
  
  Rin = 192;
  Gin = 192;
  Bin = 192;
  
  //BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterSoftware;
  BGRAToBT709ConverterTypeEnum type = BGRAToBT709ConverterVImage;
  
  uint32_t yuvOutPixel = [self convert_srgb_to_bt709:rgbToPixel(Rin, Gin, Bin) type:type];
  
  pixelToRGBA(yuvOutPixel, &Cr, &Cb, &Y, &dummy);
  
  {
    int v = Y;
    int expectedVal = 175;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cb;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Cr;
    int expectedVal = 128;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  uint32_t bgraOutPixel = [self convert_bt709_to_srgb:yuvOutPixel type:type];
  
  pixelToRGBA(bgraOutPixel, &Rout, &Gout, &Bout, &dummy);
  
  {
    int v = Rout;
    int expectedVal = Rin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Gout;
    int expectedVal = Gin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
  {
    int v = Bout;
    int expectedVal = Bin;
    XCTAssert(v == expectedVal, @"%3d != %3d", v, expectedVal);
  }
  
}

@end