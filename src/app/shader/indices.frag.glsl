#version 300 es

precision highp float;

uniform sampler2D u_positionTexture;
uniform vec3 u_domainScale;       // Domain scale for particle positions
uniform ivec3 u_particleGridDims; // Dimensions of the 3D particle grid (e.g., [11, 11, 11])
uniform float u_cellSize;         // Uniform cell size (H)


#include ./utils/particle-utils.glsl;

out uvec2 outIndices;

void main() {
    ivec2 texSize = textureSize(u_positionTexture, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);

    int particleId = tex2ndx(texSize, ivec2(gl_FragCoord.xy)); // particleId from fragment coord

    // Fetch the unscaled 3D particle position
    // Note: Positions in texture are typically [-0.5, 0.5] or similar small range if not scaled by DOMAIN_SCALE yet.
    // The SPH simulation steps (pressure, force) use positions scaled by DOMAIN_SCALE.
    // Here, we need the position that corresponds to the grid defined by PARTICLE_GRID_DIMS over DOMAIN_SCALE.
    // Fetch the local 3D particle position (e.g., in range like [-0.5, 0.5])
    vec3 p_local = texelFetch(u_positionTexture, ivec2(gl_FragCoord.xy), 0).xyz;

    // Scale local position to world simulation space
    vec3 p_world = p_local * u_domainScale;

    // Get the 3D cell index in the grid
    // pos2CellIndex now takes (vec3 world_pos, ivec3 grid_dims, float cell_size)
    ivec3 cellIndex3D = pos2CellIndex(p_world, u_particleGridDims, u_cellSize);

    // Convert 3D cell index to a single linear cell ID
    // cell3DToLinearId is expected to be added to particle-utils.glsl
    // It takes ivec3 cell index and ivec3 grid dimensions.
    int linearCellId = cell3DToLinearId(cellIndex3D, u_particleGridDims);

    outIndices = uvec2(linearCellId, particleId);
}