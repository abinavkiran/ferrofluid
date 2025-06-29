
#version 300 es

precision highp float;
precision highp int;
precision highp usampler2D;

uniform sampler2D u_positionTexture;
uniform usampler2D u_indicesTexture;
uniform usampler2D u_offsetTexture;

layout(std140) uniform u_SimulationParams {
    float H;
    float HSQ;
    float MASS;
    float REST_DENS;
    float GAS_CONST;
    float VISC;
    float POLY6;
    float SPIKY_GRAD;
    float VISC_LAP;
    float POINTER_RADIUS;
    float POINTER_STRENGTH;
    int PARTICLE_COUNT;
    vec3 DOMAIN_SCALE;
    ivec3 PARTICLE_GRID_DIMS;
    ivec2 OFFSET_TEX_DIMS;
    float CELL_SIZE;
    float COHESION_STRENGTH;  // New cohesion parameter
};

in vec2 v_uv;

out vec2 outDensityPressure;

#include ./utils/particle-utils.glsl;

float poly6Weight(float r2) {
    float temp = max(0., HSQ - r2);
    return POLY6 * temp * temp * temp;
}

void main() {
    ivec2 particleTexDimensions = textureSize(u_positionTexture, 0);
    // vec4 domainScale = vec4(DOMAIN_SCALE, 0., 0.); // Old line
    // DOMAIN_SCALE from UBO is already vec3.
    int emptyOffsetValue = PARTICLE_COUNT * PARTICLE_COUNT; // Max value for an empty offset
    int totalCells = PARTICLE_GRID_DIMS.x * PARTICLE_GRID_DIMS.y * PARTICLE_GRID_DIMS.z;

    vec4 p_tex = texture(u_positionTexture, v_uv); // p_tex.xyz is position
    vec3 pi = p_tex.xyz * DOMAIN_SCALE; // Scale position by domain
    float rho = MASS * poly6Weight(0.); // Initial density for self

    // find the 3D cell index of this particle
    // pi is already world_pos (p_tex.xyz * DOMAIN_SCALE)
    // pos2CellIndex now takes (vec3 world_pos, ivec3 grid_dims, float cell_size)
    ivec3 cellIndex3D = pos2CellIndex(pi, PARTICLE_GRID_DIMS, CELL_SIZE);

    // Iterate over 3x3x3 neighboring cells (including current cell)
    for(int k_offset = -1; k_offset <= 1; ++k_offset)
    {
        for(int j_offset = -1; j_offset <= 1; ++j_offset)
        {
            for(int i_offset = -1; i_offset <= 1; ++i_offset)
            {
                ivec3 neighborCell3D = cellIndex3D + ivec3(i_offset, j_offset, k_offset);

                // Boundary check for the neighboring cell index
                if (any(lessThan(neighborCell3D, ivec3(0))) || any(greaterThanEqual(neighborCell3D, PARTICLE_GRID_DIMS))) {
                    continue; // Skip out-of-bounds cells
                }

                int linearNeighborId = cell3DToLinearId(neighborCell3D, PARTICLE_GRID_DIMS);

                // look up the offset to the cell from the 2D offset texture
                // ndx2tex for offset texture uses OFFSET_TEX_DIMS
                int neighborIterator = int(texelFetch(u_offsetTexture, ndx2tex(OFFSET_TEX_DIMS, linearNeighborId), 0).x);

            // iterate through particles in the neighbour cell (if iterator offset is valid)
            while(neighborIterator != emptyOffsetValue && neighborIterator < PARTICLE_COUNT)
            {
                uvec2 indexData = texelFetch(u_indicesTexture, ndx2tex(particleTexDimensions, neighborIterator), 0).xy;

                if(int(indexData.x) != linearNeighborId) { // Check against the 3D linear cell ID
                    break;  // it means we stepped out of the neighbour cell list
                }

                // do density estimation
                uint pj_ndx = indexData.y;
                vec3 pj = texelFetch(u_positionTexture, ndx2tex(particleTexDimensions, int(pj_ndx)), 0).xyz * DOMAIN_SCALE;
                vec3 pij = pj - pi; // pij is now vec3

                float r2 = dot(pij, pij); // dot product of two vec3s
                if (r2 < HSQ) {
                    float t = MASS * poly6Weight(r2);
                    rho += t;
                }

                neighborIterator++;
            }
        }
    }

    // loop over all other particles
    /*for(int i=0; i<PARTICLE_COUNT; i++) {
        vec3 pj = texelFetch(u_positionTexture, ndx2tex(particleTexDimensions, i), 0).xyz * DOMAIN_SCALE;
        vec3 pij = pj - pi; // pij is vec3

        float r2 = dot(pij, pij); // dot product of two vec3s
        if (r2 < HSQ) {
            float t = MASS * poly6Weight(r2);
            rho += t;
        }
    }*/

    float pressure = max(GAS_CONST * (rho - REST_DENS), 0.);

    outDensityPressure = vec2(rho, pressure);
}