
#import <Foundation/Foundation.h>
#import <ModelIO/ModelIO.h>

#include <vector>
#include <meshoptimizer/meshoptimizer.h>

#import "MBEMesh.h"

static const size_t kMeshletMaxVertices = 255;  // constants copied from meshoptimizer/clusterizer.cpp
static const size_t kMeshletMaxTriangles = 512;

struct Vertex {
    float x, y, z;
    float nx, ny, nz;
    float u, v;
};

struct Meshlet {
    uint32_t vertexOffset;
    uint32_t vertexCount;
    uint32_t triangleOffset;
    uint32_t triangleCount;
    float boundsCenter[3];
    float boundsRadius;
    float coneApex[3];
    float coneAxis[3];
    float coneCutoff, pad;
};

static void printUsage(void) {
    printf("Usage: meshletgen [-v <max_meshlet_vertex_count>] [-t <max_meshlet_primitive_count>] -i <input_path> -o <output_path>\n");
}

static void printUnknownOption(const char* flag) {
    printf("Unknown flag or option: %s\n", flag);
}

static bool buildMeshlets(std::vector<Vertex> const& vertices, std::vector<uint32_t> const& indices,
                          size_t maxMeshletVertexCount, size_t maxMeshletTriangleCount,
                          std::vector<Meshlet> /* out */ &meshlets,
                          std::vector<uint32_t> /* out */ &meshletVertices,
                          std::vector<uint8_t> /* out */ &meshletTriangles)
{
    const float coneWeight = 0.2f;
    size_t maxMeshletCount = meshopt_buildMeshletsBound(indices.size(), maxMeshletVertexCount, maxMeshletTriangleCount);
    std::vector<meshopt_Meshlet> meshletsInternal(maxMeshletCount);
    meshletVertices = std::vector<uint32_t>(maxMeshletCount * maxMeshletVertexCount);
    meshletTriangles = std::vector<uint8_t>(maxMeshletCount * maxMeshletTriangleCount * 3);

    size_t meshletCount = meshopt_buildMeshlets(meshletsInternal.data(), meshletVertices.data(), meshletTriangles.data(),
                                                indices.data(), indices.size(), &vertices[0].x, vertices.size(),
                                                sizeof(Vertex), maxMeshletVertexCount, maxMeshletTriangleCount, coneWeight);

    meshlets.reserve(meshletCount);
    for (int i = 0; i < meshletCount; ++i) {
        auto const& meshlet = meshletsInternal[i];
        meshopt_Bounds bounds = meshopt_computeMeshletBounds(meshletVertices.data() + meshlet.vertex_offset,
                                                             meshletTriangles.data() + meshlet.triangle_offset,
                                                             meshlet.triangle_count,
                                                             &vertices.data()[0].x,
                                                             vertices.size(), sizeof(Vertex));

        meshlets.push_back(Meshlet {
            meshlet.vertex_offset, meshlet.vertex_count,
            meshlet.triangle_offset, meshlet.triangle_count,
            { bounds.center[0], bounds.center[1], bounds.center[2] }, bounds.radius,
            { bounds.cone_apex[0], bounds.cone_apex[1], bounds.cone_apex[2] },
            { bounds.cone_axis[0], bounds.cone_axis[1], bounds.cone_axis[2] },
            bounds.cone_cutoff,
            0.0f // pad
        });
    }

    // Trim zeros from overestimated meshlet count
    meshletTriangles.resize(meshlets.back().triangleOffset + meshlets.back().triangleCount * 3);

    return (meshletCount > 0);
}

static bool buildMeshletsFromAsset(NSURL *inputURL, NSURL *outputURL, size_t maxMeshletVertexCount, size_t maxMeshletTriangleCount)
{
    MDLVertexDescriptor *vertexDescriptor = [MDLVertexDescriptor new];
    vertexDescriptor.attributes[0].name = MDLVertexAttributePosition;
    vertexDescriptor.attributes[0].format = MDLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;

    vertexDescriptor.attributes[1].name = MDLVertexAttributeNormal;
    vertexDescriptor.attributes[1].format = MDLVertexFormatFloat3;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 3;
    vertexDescriptor.attributes[1].bufferIndex = 0;

    vertexDescriptor.attributes[2].name = MDLVertexAttributeTextureCoordinate;
    vertexDescriptor.attributes[2].format = MDLVertexFormatFloat2;
    vertexDescriptor.attributes[2].offset = sizeof(float) * 6;
    vertexDescriptor.attributes[2].bufferIndex = 0;

    vertexDescriptor.layouts[0].stride = sizeof(float) * 8;

    NSError *error = nil;
    MDLAsset *asset = [[MDLAsset alloc] initWithURL:inputURL
                                   vertexDescriptor:vertexDescriptor
                                    bufferAllocator:nil
                                   preserveTopology:NO
                                              error:&error];

    if (asset == nil) {
        return false;
    }

    NSArray *meshes = [asset childObjectsOfClass:[MDLMesh class]];

    if (meshes.count == 0) {
        printf("Did not find any meshes in the asset. The mesh must be at the root of the asset hierarchy.\n");
        return false;
    }

    if (meshes.count != 1) {
        printf("Warning: Input asset contained more than one mesh. Only the first mesh will be processed.\n");
    }

    MDLMesh *sourceMesh = meshes.firstObject;

    id<MDLMeshBuffer> vertexBuffer = sourceMesh.vertexBuffers.firstObject;
    MDLMeshBufferMap *vertexMap = [vertexBuffer map];
    const Vertex *vertexBytes = (const Vertex *)vertexMap.bytes;
    std::vector<Vertex> sourceVertices { vertexBytes, vertexBytes + sourceMesh.vertexCount };

    for (int i = 0; i < 1/*sourceMesh.submeshes.count*/; ++i) {
        MDLSubmesh *sourceSubmesh = sourceMesh.submeshes[i];

        id<MDLMeshBuffer> indexBuffer = [sourceSubmesh indexBufferAsIndexType:MDLIndexBitDepthUInt32];
        MDLMeshBufferMap *indexMap = [indexBuffer map];
        const uint32_t *indexBytes = (const uint32_t *)indexMap.bytes;
        std::vector<uint32_t> sourceIndices { indexBytes, indexBytes + sourceSubmesh.indexCount };

        std::vector<Meshlet> meshlets;
        std::vector<uint32_t> meshletVertices;
        std::vector<uint8_t> meshletTriangles;
        buildMeshlets(sourceVertices, sourceIndices, maxMeshletVertexCount, maxMeshletTriangleCount,
                      meshlets, meshletVertices, meshletTriangles);

        MBEMeshFileHeader dummyHeader { 0 };
        MBEMeshFileSubmesh submesh = {
            .meshletsStartIndex = 0,
            .meshletsCount = (uint32_t)meshlets.size(),
        };

        size_t submeshOffset, meshletsOffset, vertexDataOffset, meshletVerticesOffset, meshletTrianglesOffset;
        size_t submeshCount = 1;
        size_t meshletCount = meshlets.size();
        size_t vertexDataLength = sourceVertices.size() * sizeof(Vertex);
        size_t meshletVerticesLength = meshletVertices.size() * sizeof(uint32_t);
        size_t meshletTrianglesLength = meshletTriangles.size() * sizeof(uint8_t);
        NSMutableData *meshletData = [NSMutableData new];
        [meshletData appendBytes:&dummyHeader length:sizeof(dummyHeader)]; // reserve space for header
        submeshOffset = meshletData.length;
        [meshletData appendBytes:&submesh length:sizeof(submesh)];
        meshletsOffset = meshletData.length;
        for (size_t i = 0; i < meshlets.size(); ++i) {
            MBEMeshFileMeshlet meshletRecord = {
                .vertexOffset = meshlets[i].vertexOffset,
                .vertexCount = meshlets[i].vertexCount,
                .triangleOffset = meshlets[i].triangleOffset,
                .triangleCount = meshlets[i].triangleCount,
                .bounds = {
                    meshlets[i].boundsCenter[0],
                    meshlets[i].boundsCenter[1],
                    meshlets[i].boundsCenter[2],
                    meshlets[i].boundsRadius
                },
                .coneApex = {
                    meshlets[i].coneApex[0],
                    meshlets[i].coneApex[1],
                    meshlets[i].coneApex[2],
                },
                .coneAxis = {
                    meshlets[i].coneAxis[0],
                    meshlets[i].coneAxis[1],
                    meshlets[i].coneAxis[2],
                },
                .coneCutoff = meshlets[i].coneCutoff,
                .pad = 0.0f,
            };
            [meshletData appendBytes:&meshletRecord length:sizeof(MBEMeshFileMeshlet)];
        }
        vertexDataOffset = meshletData.length;
        [meshletData appendBytes:sourceVertices.data() length:vertexDataLength];
        meshletVerticesOffset = meshletData.length;
        [meshletData appendBytes:meshletVertices.data() length:meshletVerticesLength];
        meshletTrianglesOffset = meshletData.length;
        [meshletData appendBytes:meshletTriangles.data() length:meshletTrianglesLength];

        MBEMeshFileHeader header = {
            .meshletMaxVertexCount = (uint32_t)maxMeshletVertexCount,
            .meshletMaxTriangleCount = (uint32_t)maxMeshletTriangleCount,
            .submeshOffset = (uint32_t)submeshOffset,
            .submeshCount = (uint32_t)submeshCount,
            .meshletsOffset = (uint32_t)meshletsOffset,
            .meshletCount = (uint32_t)meshletCount,
            .vertexDataOffset = (uint32_t)vertexDataOffset,
            .vertexDataLength = (uint32_t)vertexDataLength,
            .meshletVertexOffset = (uint32_t)meshletVerticesOffset,
            .meshletVertexLength = (uint32_t)meshletVerticesLength,
            .meshletTrianglesOffset = (uint32_t)meshletTrianglesOffset,
            .meshletTrianglesLength = (uint32_t)meshletTrianglesLength,
        };
        [meshletData replaceBytesInRange:NSMakeRange(0, sizeof(header)) withBytes:&header];

        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error];

        return [meshletData writeToURL:outputURL atomically:YES];
    }

    return true;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 5) {
            printUsage();
            return 0;
        }

        NSString *inputPath = nil;
        NSString *outputPath = nil;
        int maxVertCount = 64, maxTriCount = 124;

        for (int i = 1; i < argc; i += 2) {
            if (strcmp(argv[i], "-v") == 0) {
                assert(argc > i);
                maxVertCount = atoi(argv[i + 1]);
                continue;
            }
            if (strcmp(argv[i], "-t") == 0) {
                assert(argc > i);
                maxTriCount = atoi(argv[i + 1]);
                continue;
            }
            if (strcmp(argv[i], "-i") == 0) {
                assert(argc > i);
                inputPath = [NSString stringWithCString:argv[i + 1] encoding:NSUTF8StringEncoding];
                continue;
            }
            if (strcmp(argv[i], "-o") == 0) {
                assert(argc > i);
                outputPath = [NSString stringWithCString:argv[i + 1] encoding:NSUTF8StringEncoding];
                continue;
            }
            printUnknownOption(argv[i]);
            return 1;
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:inputPath]) {
            printf("Could not find input file %s\n", [inputPath cStringUsingEncoding:NSUTF8StringEncoding]);
            return 1;
        }

        // Sanity-check output limits
        if (maxVertCount < 3) { maxVertCount = 3; }
        if (maxTriCount < 1) { maxTriCount = 1; }

        // Constrain output limits to meshoptimizer implementation limits
        if (maxVertCount > kMeshletMaxVertices) { maxVertCount = kMeshletMaxVertices; }
        if (maxTriCount > kMeshletMaxTriangles) { maxTriCount = kMeshletMaxTriangles; }

        buildMeshletsFromAsset([NSURL fileURLWithPath:inputPath], [NSURL fileURLWithPath:outputPath],
                               maxVertCount, maxTriCount);
    }
    return 0;
}
