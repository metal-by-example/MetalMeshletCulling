
#import "MBEMesh.h"

@implementation MBEMeshBuffer

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer offset:(NSInteger)offset {
    if (self = [super init]) {
        _buffer = buffer;
        _offset = offset;
    }
    return self;
}

@end

@implementation MBESubmesh

@end

@implementation MBEMesh

- (instancetype)initWithURL:(NSURL *)url device:(id<MTLDevice>)device {
    if (self = [super init]) {
        NSData *meshData = [NSData dataWithContentsOfURL:url];
        if (meshData == nil) {
            return nil;
        }

        MBEMeshFileHeader header;
        [meshData getBytes:&header length:sizeof(header)];

        _meshletMaxVertexCount = header.meshletMaxVertexCount;
        _meshletMaxTriangleCount = header.meshletMaxTriangleCount;

        MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
        vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[0].offset = 0;
        vertexDescriptor.attributes[0].bufferIndex = 0;

        vertexDescriptor.attributes[1].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[1].offset = sizeof(float) * 3;
        vertexDescriptor.attributes[1].bufferIndex = 0;

        vertexDescriptor.attributes[2].format = MTLVertexFormatFloat2;
        vertexDescriptor.attributes[2].offset = sizeof(float) * 6;
        vertexDescriptor.attributes[2].bufferIndex = 0;

        vertexDescriptor.layouts[0].stride = sizeof(float) * 8;

        _vertexDescriptor = vertexDescriptor;

        id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:meshData.bytes + header.vertexDataOffset
                                                          length:header.vertexDataLength
                                                         options:MTLResourceStorageModeShared];
        vertexBuffer.label = @"Mesh Vertices";

        _vertexBuffers = @[[[MBEMeshBuffer alloc] initWithBuffer:vertexBuffer offset:0]];
        id<MTLBuffer> meshletVertexBuffer = [device newBufferWithBytes:meshData.bytes + header.meshletVertexOffset
                                                                  length:header.meshletVertexLength
                                                                 options:MTLResourceStorageModeShared];
        meshletVertexBuffer.label = @"Meshlet Vertex Map";
        _meshletVertexBuffer = [[MBEMeshBuffer alloc] initWithBuffer:meshletVertexBuffer offset:0];

        NSAssert(header.submeshCount == 1, @"Only meshes with exactly one submesh are currently supported");
        for (int i = 0; i < header.submeshCount; ++i) {
            MBESubmesh *submesh = [MBESubmesh new];

            id<MTLBuffer> meshletBuffer = [device newBufferWithBytes:meshData.bytes + header.meshletsOffset
                                                              length:header.meshletCount * sizeof(MBEMeshFileMeshlet)
                                                              options:MTLResourceStorageModeShared];
            meshletBuffer.label = @"Meshlet Descriptors";

            id<MTLBuffer> meshletTriangleBuffer = [device newBufferWithBytes:meshData.bytes + header.meshletTrianglesOffset
                                                                      length:header.meshletTrianglesLength
                                                                     options:MTLResourceStorageModeShared];
            meshletTriangleBuffer.label = @"Meshlet Triangles";

            submesh.meshletTriangleBuffer = [[MBEMeshBuffer alloc] initWithBuffer:meshletTriangleBuffer offset:0];
            submesh.meshletBuffer = [[MBEMeshBuffer alloc] initWithBuffer:meshletBuffer offset:0];
            submesh.meshletCount = header.meshletCount;

            _submeshes = @[ submesh ];
        }
    }
    
    return self;
}

@end
