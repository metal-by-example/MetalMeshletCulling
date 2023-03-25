
#import "MBEViewController.h"
#import "MBEMesh.h"
#import "MBEMeshletRenderer.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface MBEViewController () <MTKViewDelegate>
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) MBEMeshletRenderer *renderer;
@property (nonatomic, weak) MTKView *mtkView;
@end

@implementation MBEViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];

    MTKView *mtkView = [[MTKView alloc] initWithFrame:self.view.bounds device:self.device];
    mtkView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:mtkView];

    self.mtkView = mtkView;
    self.mtkView.delegate = self;
    self.mtkView.sampleCount = 4;
    self.mtkView.clearColor = MTLClearColorMake(1, 1, 1, 1.0);
    self.mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    self.mtkView.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    self.renderer = [[MBEMeshletRenderer alloc] initWithDevice:self.device
                                                  commandQueue:self.commandQueue
                                                          view:self.mtkView];

    NSURL *assetURL = [[NSBundle mainBundle] URLForResource:@"dragon" withExtension:@"mbemesh"];
    self.renderer.mesh = [[MBEMesh alloc] initWithURL:assetURL device:self.device];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.renderer.viewport = (MTLViewport){ 0.0, 0.0, size.width, size.height, 0.0, 1.0 };
}

- (void)drawInMTKView:(nonnull MTKView *)view {
    MTLRenderPassDescriptor *renderPass = view.currentRenderPassDescriptor;
    if (renderPass == nil) {
        return; // Didn't get a render pass descriptor; drop this frame
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    [self.renderer draw:renderCommandEncoder];
    [renderCommandEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

@end
