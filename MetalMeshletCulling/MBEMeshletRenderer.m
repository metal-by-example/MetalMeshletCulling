
#import "MBEMeshletRenderer.h"

simd_float4x4 simd_float4x4_translation(float tx, float ty, float tz)
{
    return simd_matrix((simd_float4){ 1, 0, 0, 0 },
                       (simd_float4){ 0, 1, 0, 0 },
                       (simd_float4){ 0, 0, 1, 0},
                       (simd_float4){ tx, ty, tz, 1 });
}

simd_float4x4 simd_float4x4_perspective_rh(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return simd_matrix((simd_float4){ xs, 0, 0, 0 },
                       (simd_float4){ 0, ys, 0, 0 },
                       (simd_float4){ 0, 0, zs, -1 },
                       (simd_float4){ 0, 0, nearZ * zs, 0 });
}

simd_float4x4 simd_float4x4_rotation_axis_angle(float axisX, float axisY, float axisZ, float angle) {
    simd_float3 unitAxis = simd_normalize((simd_float3){ axisX, axisY, axisZ });
    float ct = cosf(angle);
    float st = sinf(angle);
    float ci = 1 - ct;
    float x = unitAxis.x, y = unitAxis.y, z = unitAxis.z;
    return simd_matrix((simd_float4){     ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0 },
                       (simd_float4){ x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0 },
                       (simd_float4){ x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0 },
                       (simd_float4){                   0,                   0,                   0, 1 });
}

typedef struct InstanceData {
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 inverseModelViewMatrix;
    simd_float4x4 normalMatrix;
} InstanceData;

@interface MBEMeshletRenderer ()
@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;
@end

@implementation MBEMeshletRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device commandQueue:(id<MTLCommandQueue>)commandQueue view:(MTKView *)view {
    if (self = [super init]) {
        _device = device;
        _commandQueue = commandQueue;
        _viewport = (MTLViewport){ 0.0, 0.0, view.drawableSize.width, view.drawableSize.height, 0.0, 1.0 };
        view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;

        [self makeMeshRenderPipelineWithView:view];
    }
    return self;
}

- (void)makeMeshRenderPipelineWithView:(MTKView *)view {
    NSError *error = nil;
    id<MTLLibrary> library = [self.device newDefaultLibrary];

    id<MTLFunction> objectFunction = [library newFunctionWithName:@"object_main"];
    id<MTLFunction> meshFunction = [library newFunctionWithName:@"mesh_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    MTLMeshRenderPipelineDescriptor *pipelineDescriptor = [MTLMeshRenderPipelineDescriptor new];

    pipelineDescriptor.objectFunction = objectFunction;
    pipelineDescriptor.meshFunction = meshFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;

    pipelineDescriptor.rasterSampleCount = view.sampleCount;

    pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;

    MTLPipelineOption options = MTLPipelineOptionNone;
    self.meshRenderPipeline = [self.device newRenderPipelineStateWithMeshDescriptor:pipelineDescriptor
                                                                            options:options
                                                                         reflection:nil
                                                                              error:&error];

    MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthDescriptor.depthWriteEnabled = YES;
    self.depthStencilState = [self.device newDepthStencilStateWithDescriptor:depthDescriptor];
}

- (void)draw:(id<MTLRenderCommandEncoder>)renderCommandEncoder {
    if (self.mesh == nil) {
        return;
    }

    [renderCommandEncoder setDepthStencilState:self.depthStencilState];
    [renderCommandEncoder setRenderPipelineState:self.meshRenderPipeline];

    [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderCommandEncoder setCullMode:MTLCullModeBack];

    // We produce one vertex and/or one triangle per mesh thread, so calculate
    // the max number of threads we need to launch per mesh threadgroup.
    const size_t maxMeshThreads = MAX(self.mesh.meshletMaxVertexCount, self.mesh.meshletMaxTriangleCount);

    MBEMeshBuffer *vertexBuffer = self.mesh.vertexBuffers.firstObject;
    [renderCommandEncoder setMeshBuffer:vertexBuffer.buffer offset:vertexBuffer.offset atIndex:0];

    [renderCommandEncoder setMeshBuffer:self.mesh.meshletVertexBuffer.buffer
                                 offset:self.mesh.meshletVertexBuffer.offset
                                atIndex:2];

    float aspect = self.viewport.width / self.viewport.height;

    static float time = 0.0;
    //time += 0.0166;

    simd_float4x4 modelMatrix = simd_float4x4_rotation_axis_angle(0, 1, 0, time);

    simd_float4x4 viewMatrix = simd_float4x4_translation(0, -0.5, -2.0);
    simd_float4x4 projectionMatrix = simd_float4x4_perspective_rh(65.0 * (M_PI / 180), aspect, 0.1, 150.0);
    simd_float4x4 modelViewMatrix = simd_mul(viewMatrix, modelMatrix);
    simd_float4x4 mvpMatrix = simd_mul(projectionMatrix, modelViewMatrix);
    simd_float4x4 normalMatrix = simd_inverse(simd_transpose(modelViewMatrix));

    InstanceData instance = {
        .modelViewProjectionMatrix = mvpMatrix,
        .inverseModelViewMatrix = simd_inverse(modelViewMatrix),
        .normalMatrix = normalMatrix,
    };

    [renderCommandEncoder setObjectBytes:&instance length:sizeof(instance) atIndex:1];

    [renderCommandEncoder setMeshBytes:&instance length:sizeof(instance) atIndex:4];

    for (MBESubmesh *submesh in self.mesh.submeshes) {
        [renderCommandEncoder setObjectBuffer:submesh.meshletBuffer.buffer
                                       offset:submesh.meshletBuffer.offset
                                      atIndex:0];
        uint32_t meshletCount = (uint32_t)submesh.meshletCount;
        [renderCommandEncoder setObjectBytes:&meshletCount length:sizeof(meshletCount) atIndex:2];

        [renderCommandEncoder setMeshBuffer:submesh.meshletBuffer.buffer
                                     offset:submesh.meshletBuffer.offset
                                    atIndex:1];
        [renderCommandEncoder setMeshBuffer:submesh.meshletTriangleBuffer.buffer
                                     offset:submesh.meshletTriangleBuffer.offset
                                    atIndex:3];

        // TODO: Set fragment resources (material data, etc.)

        NSInteger threadsPerObjectGrid = submesh.meshletCount;
        NSInteger threadsPerObjectThreadgroup = 32;
        NSInteger threadgroupsPerObject = (threadsPerObjectGrid + threadsPerObjectThreadgroup - 1) / threadsPerObjectThreadgroup;
        NSInteger threadsPerMeshThreadgroup = maxMeshThreads;
        [renderCommandEncoder drawMeshThreadgroups:MTLSizeMake(threadgroupsPerObject, 1, 1)
                       threadsPerObjectThreadgroup:MTLSizeMake(threadsPerObjectThreadgroup, 1, 1)
                         threadsPerMeshThreadgroup:MTLSizeMake(threadsPerMeshThreadgroup, 1, 1)];
    }
}

@end
