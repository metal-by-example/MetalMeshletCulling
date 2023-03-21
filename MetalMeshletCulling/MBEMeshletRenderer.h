
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#import "MBEMesh.h"

NS_ASSUME_NONNULL_BEGIN

@interface MBEMeshletRenderer : NSObject

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> meshRenderPipeline;
@property (nonatomic, strong) MBEMesh *mesh;
@property (nonatomic, assign) MTLViewport viewport;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                  commandQueue:(id<MTLCommandQueue>)commandQueue
                          view:(MTKView *)view;

- (void)draw:(id<MTLRenderCommandEncoder>)renderCommandEncoder;

@end

NS_ASSUME_NONNULL_END
