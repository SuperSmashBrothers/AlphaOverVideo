/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "AAPLShaderTypes.h"

#import "MetalBT709Decoder.h"
#import "BGDecodeEncode.h"

@interface AAPLRenderer ()

@property (nonatomic, retain) MetalBT709Decoder *metalBT709Decoder;

@end

// Main class performing the rendering
@implementation AAPLRenderer
{
  // The device (aka GPU) we're using to render
  id<MTLDevice> _device;
  
  // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
  id<MTLRenderPipelineState> _pipelineState;
  
  // The command Queue from which we'll obtain command buffers
  id<MTLCommandQueue> _commandQueue;
  
  // Input to sRGB texture render comes from H.264 source
  CVPixelBufferRef _yCbCrPixelBuffer;
  
  // BT.709 render to sRGB texture
  id<MTLTexture> _srgbTexture;
  
  // The Metal buffer in which we store our vertex data
  id<MTLBuffer> _vertices;
  
  // The number of vertices in our vertex buffer
  NSUInteger _numVertices;
  
  // The current size of our view so we can use this in our render pipeline
  vector_uint2 _viewportSize;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
  self = [super init];
  if(self)
  {
    _device = mtkView.device;
    
//    NSURL *imageFileLocation = [[NSBundle mainBundle] URLForResource:@"Image"
//                                                       withExtension:@"tga"];
//
//    AAPLImage * image = [[AAPLImage alloc] initWithTGAFileAtLocation:imageFileLocation];
//
//    if(!image)
//    {
//      NSLog(@"Failed to create the image from %@", imageFileLocation.absoluteString);
//      return nil;
//    }
    
    int width = 256;
    int height = 256;
    
    // Configure Metal view so that it makes use of native sRGB texture values
    
#if TARGET_OS_IOS
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
#endif
    
    {
      // Init sRGB intermediate render texture
      
      MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
      
      textureDescriptor.textureType = MTLTextureType2D;
      
      // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
      // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
      
      // FIXME: write to sRGB texture seems to require MacOSX 10.14
#if TARGET_OS_IOS
      textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
#else
      textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
#endif
      
      // Set the pixel dimensions of the texture
      textureDescriptor.width = width;
      textureDescriptor.height = height;
      
      textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      
      // Create the texture from the device by using the descriptor
      _srgbTexture = [_device newTextureWithDescriptor:textureDescriptor];
      
      NSAssert(_srgbTexture, @"_srgbTexture");
    }
    
    /*
    // Init _texture
    
    {
      MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
      
      textureDescriptor.textureType = MTLTextureType2D;
      
      // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
      // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
      textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
      
      // Set the pixel dimensions of the texture
      textureDescriptor.width = image.width;
      textureDescriptor.height = image.height;
      
      //textureDescriptor.usage = MTLTextureUsageShaderRead;
      
      // Create the texture from the device by using the descriptor
      _texture = [_device newTextureWithDescriptor:textureDescriptor];
      
      // Calculate the number of bytes per row of our image.
      NSUInteger bytesPerRow = 4 * image.width;
      
      MTLRegion region = {
        { 0, 0, 0 },                   // MTLOrigin
        {image.width, image.height, 1} // MTLSize
      };
      
      // Copy the bytes from our data object into the texture
      [_texture replaceRegion:region
                  mipmapLevel:0
                    withBytes:image.data.bytes
                  bytesPerRow:bytesPerRow];
    }
    */
    
    // Set up a simple MTLBuffer with our vertices which include texture coordinates
    static const AAPLVertex quadVertices[] =
    {
      // Pixel positions, Texture coordinates
      { {  250,  -250 },  { 1.f, 0.f } },
      { { -250,  -250 },  { 0.f, 0.f } },
      { { -250,   250 },  { 0.f, 1.f } },
      
      { {  250,  -250 },  { 1.f, 0.f } },
      { { -250,   250 },  { 0.f, 1.f } },
      { {  250,   250 },  { 1.f, 1.f } },
    };
    
    // Create our vertex buffer, and initialize it with our quadVertices array
    _vertices = [_device newBufferWithBytes:quadVertices
                                     length:sizeof(quadVertices)
                                    options:MTLResourceStorageModeShared];
    
    // Calculate the number of vertices by dividing the byte length by the size of each vertex
    _numVertices = sizeof(quadVertices) / sizeof(AAPLVertex);
    
    /// Create render pipeline
    
    // Load all the shader files with a .metal file extension in the project
    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    // Init metalBT709Decoder
    
    self.metalBT709Decoder = [[MetalBT709Decoder alloc] init];
    
    self.metalBT709Decoder.device = _device;
    self.metalBT709Decoder.defaultLibrary = defaultLibrary;
    
    BOOL worked = [self.metalBT709Decoder setupMetal];
    NSAssert(worked, @"worked");
    
    // Decode H.264 to CoreVideo pixel buffer
    
    _yCbCrPixelBuffer = [self decodeH264YCbCr];
    //CVPixelBufferRetain(_yCbCrPixelBuffer);
    
    {
      // Load the vertex function from the library
      id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
      
      // Load the fragment function from the library
      id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];
      
      // Set up a descriptor for creating a pipeline state object
      MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
      pipelineStateDescriptor.label = @"Texturing Pipeline";
      pipelineStateDescriptor.vertexFunction = vertexFunction;
      pipelineStateDescriptor.fragmentFunction = fragmentFunction;
      pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
      
      NSError *error = NULL;
      _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                               error:&error];
      if (!_pipelineState)
      {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        //  If the Metal API validation is enabled, we can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode)
        NSLog(@"Failed to created pipeline state, error %@", error);
      }
    }
    
    // Create the command queue
    _commandQueue = [_device newCommandQueue];
  }
  
  return self;
}

// Decode a single frame of H.264 video as BT.709 formatted CoreVideo frame.
// Note that the ref count of the returned pixel buffer is 1.

- (CVPixelBufferRef) decodeH264YCbCr
{
  NSString *resFilename = @"osxcolor_test_image_24bit_BT709.m4v";
  
  NSArray *cvPixelBuffers = [BGDecodeEncode recompressKeyframesOnBackgroundThread:resFilename
                                                                    frameDuration:1.0/30
                                                                       renderSize:CGSizeMake(256, 256)
                                                                       aveBitrate:0];
  NSLog(@"returned %d YCbCr textures", (int)cvPixelBuffers.count);
  
  // Grab just the first texture, return retained ref
  
  CVPixelBufferRef cvPixelBuffer = (__bridge CVPixelBufferRef) cvPixelBuffers[0];
  
  CVPixelBufferRetain(cvPixelBuffer);
  
  return cvPixelBuffer;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
  BOOL worked;

  // Create a new command buffer for each render pass to the current drawable
  id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  commandBuffer.label = @"BT709 Render";
  
  // Obtain a reference to a sRGB intermediate texture
  
  worked = [self.metalBT709Decoder decodeBT709:_yCbCrPixelBuffer
                      bgraSRGBTexture:_srgbTexture
                        commandBuffer:commandBuffer
                   waitUntilCompleted:FALSE];
  NSAssert(worked, @"worked");

  // Obtain a renderPassDescriptor generated from the view's drawable textures
  MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
  
  if(renderPassDescriptor != nil)
  {
    // Create a render command encoder so we can render into something
    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"RescaleRender";
    
    // Set the region of the drawable to which we'll draw.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setVertexBytes:&_viewportSize
                           length:sizeof(_viewportSize)
                          atIndex:AAPLVertexInputIndexViewportSize];
    
    // Set the texture object.  The AAPLTextureIndexBaseColor enum value corresponds
    ///  to the 'colorMap' argument in our 'samplingShader' function because its
    //   texture attribute qualifier also uses AAPLTextureIndexBaseColor for its index
    [renderEncoder setFragmentTexture:_srgbTexture
                              atIndex:AAPLTextureIndexBaseColor];
    
    // Draw the vertices of our triangles
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:_numVertices];
    
    [renderEncoder endEncoding];
    
    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:view.currentDrawable];
  }
  
  
  // Finalize rendering here & push the command buffer to the GPU
  [commandBuffer commit];
}

@end
