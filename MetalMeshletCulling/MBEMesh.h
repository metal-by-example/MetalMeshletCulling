
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
//#import <ModelIO/ModelIO.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct MBEMeshFileHeader {
    uint32_t submeshOffset; // offset in bytes from the start of the file to submesh entries
    uint32_t submeshCount;
    uint32_t meshletsOffset; // offset in bytes from the start of the file to meshlet entries
    uint32_t meshletCount;
    uint32_t vertexDataOffset; // offset in bytes from the start of the file to the vertex data
    uint32_t vertexDataLength;
    uint32_t meshletTrianglesOffset; // offset in bytes from the start of the file to the meshlet triangle data
    uint32_t meshletTrianglesLength;
} MBEMeshFileHeader;

typedef struct MBEMeshFileSubmesh {
    uint32_t meshletsStartIndex;
    uint32_t meshletsCount;
} MBEMeshFileSubmesh;

typedef struct MBEMeshFileMeshlet {
    uint32_t vertexOffset;
    uint32_t vertexCount;
    uint32_t triangleOffset;
    uint32_t triangleCount;
    float bounds[4]; // bounding circle center (x, y, z) and radius (w)
} MBEMeshFileMeshlet;

@interface MBEMeshBuffer : NSObject

@property (nonatomic, strong) id<MTLBuffer> buffer;
@property (nonatomic, assign) NSInteger offset;

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer offset:(NSInteger)offset;

@end

@interface MBESubmesh : NSObject

//@property (nonatomic, strong) MDLMaterial *material;
@property (nonatomic, assign) NSInteger meshletCount;
@property (nonatomic, strong) MBEMeshBuffer *meshletBuffer;
@property (nonatomic, strong) MBEMeshBuffer *meshletTriangleBuffer;

@end

@interface MBEMesh : NSObject

@property (nonatomic, copy) MTLVertexDescriptor *vertexDescriptor;
@property (nonatomic, copy) NSArray<MBEMeshBuffer *> *vertexBuffers;
@property (nonatomic, copy) NSArray<MBESubmesh *> *submeshes;

- (instancetype _Nullable)initWithURL:(NSURL *)url device:(id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
