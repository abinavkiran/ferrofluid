#version 300 es

precision highp float;
precision highp int;
precision highp usampler2D;

uniform sampler2D u_positionTexture;
uniform sampler2D u_velocityTexture;
uniform usampler2D u_indicesTexture;
uniform usampler2D u_offsetTexture;
uniform sampler2D u_densityPressureTexture;
uniform int u_particleCount;
uniform vec2 u_domainScale;

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

out vec4 outForce;

#include ./utils/particle-utils.glsl;

float spiky_grad2Weight(float r) {
    float temp = max(0., H - r);
    return (SPIKY_GRAD * temp * temp) / r;
}

float visc_laplWeight(float r) {
    return VISC_LAP * (1. - r / H);
}

void main() {
    ivec2 particleTexDimensions = textureSize(u_positionTexture, 0);
    // vec4 domainScale = vec4(DOMAIN_SCALE, 0., 0.); // Old line
    // DOMAIN_SCALE from UBO is vec3.
    int emptyOffsetValue = PARTICLE_COUNT * PARTICLE_COUNT; // Max value for an empty offset
    int totalCells = PARTICLE_GRID_DIMS.x * PARTICLE_GRID_DIMS.y * PARTICLE_GRID_DIMS.z;

    vec4 p_tex = texture(u_positionTexture, v_uv); // position from texture
    vec3 pi = p_tex.xyz * DOMAIN_SCALE;            // scaled 3D position
    vec3 vi = texture(u_velocityTexture, v_uv).xyz; // 3D velocity
    vec2 ri = texture(u_densityPressureTexture, v_uv).xy;
    float pi_rho = ri.x;
    float pi_pressure = ri.y;
    vec3 force = vec3(0.); // Force is 3D
    
    // find the 3D cell index of this particle
    // pi is already world_pos (p_tex.xyz * DOMAIN_SCALE)
    // pos2CellIndex now takes (vec3 world_pos, ivec3 grid_dims, float cell_size)
    ivec3 cellIndex3D = pos2CellIndex(pi, PARTICLE_GRID_DIMS, CELL_SIZE);

    // Iterate over 3x3x3 neighboring cells
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

                // do force calculation
                uint pj_ndx = indexData.y;
                ivec2 pj_tex = ndx2tex(particleTexDimensions, int(pj_ndx));
                vec3 pj = texelFetch(u_positionTexture, pj_tex, 0).xyz * DOMAIN_SCALE;
                vec3 pij = pj - pi; // pij is vec3
                float r2 = dot(pij, pij); // dot product of two vec3s

                if (r2 < HSQ) {
                    float r = sqrt(r2);

                    if (r >= 0.00001) { // Avoid division by zero if r is exactly 0
                        vec3 pressureForce = vec3(pij); // pressureForce is vec3
                        vec3 viscosityForce; // viscosityForce is vec3

                        vec2 rj = texelFetch(u_densityPressureTexture, pj_tex, 0).xy;
                        float pj_rho = rj.x;
                        float pj_pressure = rj.y;
                        vec3 vj = texelFetch(u_velocityTexture, pj_tex, 0).xyz; // vj is vec3

                        // compute pressure force contribution
                        // Note: spiky_grad2Weight returns value/r, so pressureForce = (pij/r) * SPIKY_GRAD * temp^2
                        // This means pij term in pressureForce should be normalized if spiky_grad2Weight doesn't account for it.
                        // Original spiky_grad2Weight(r) = (SPIKY_GRAD * temp * temp) / r. So pij * (stuff / r) is correct.
                        float pF_scalar = MASS * ((pi_pressure + pj_pressure) / (2. * pj_rho)) * spiky_grad2Weight(r);
                        pressureForce *= pF_scalar;

                        // compute viscosity force contribution
                        viscosityForce = (vj - vi) * (VISC * MASS * visc_laplWeight(r) / pj_rho);

                        force += pressureForce + viscosityForce; // Add vec3s
                    }
                }

                neighborIterator++;
            }
        }
    }

    // loop over all other particles
    /*for(int i=0; i<PARTICLE_COUNT; i++) {
        ivec2 pj_tex = ndx2tex(particleTexDimensions, i);
        vec3 pj = texelFetch(u_positionTexture, pj_tex, 0).xyz * DOMAIN_SCALE;
        vec3 pij = pj - pi; // vec3
        float r2 = dot(pij, pij); // vec3 dot

        if (r2 < HSQ) {
            float r = sqrt(r2);

            if (r == 0.) continue;

            vec3 pressureForce = vec3(pij); // vec3
            vec3 viscosityForce;            // vec3

            vec2 rj = texelFetch(u_densityPressureTexture, pj_tex, 0).xy;
            float pj_rho = rj.x;
            float pj_pressure = rj.y;
            vec3 vj = texelFetch(u_velocityTexture, pj_tex, 0).xyz; // vec3

            // compute pressure force contribution
            float pF_scalar = MASS * ((pi_pressure + pj_pressure) / (2. * pj_rho)) * spiky_grad2Weight(r);
            pressureForce *= pF_scalar;

            // compute viscosity force contribution
            viscosityForce = (vj - vi) * (VISC * MASS * visc_laplWeight(r) / pj_rho);

            force += pressureForce + viscosityForce; // vec3 add
        }
    }*/

    // compute boundary forces - REMOVE for floating globule
    // float h = H;
    // float scale = 1.;
    // vec3 minBound = -DOMAIN_SCALE * scale; // Use vec3 DOMAIN_SCALE
    // vec3 maxBound = DOMAIN_SCALE * scale;  // Use vec3 DOMAIN_SCALE
    // float f_boundary_scalar = (MASS / (pi_rho + 0.0000000001)) * pi_pressure;

    // if (pi.x < minBound.x + h) {
    //     float r_bound = pi.x - minBound.x;
    //     force.x -= f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // } else if (pi.x > maxBound.x - h) {
    //     float r_bound = maxBound.x - pi.x;
    //     force.x += f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // }
    // if (pi.y < minBound.y + h) {
    //     float r_bound = pi.y - minBound.y;
    //     force.y -= f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // } else if (pi.y > maxBound.y - h) {
    //     float r_bound = maxBound.y - pi.y;
    //     force.y += f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // }
    // if (pi.z < minBound.z + h) { // Add Z boundary
    //     float r_bound = pi.z - minBound.z;
    //     force.z -= f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // } else if (pi.z > maxBound.z - h) {
    //     float r_bound = maxBound.z - pi.z;
    //     force.z += f_boundary_scalar * spiky_grad2Weight(r_bound) * r_bound;
    // }

    // Add cohesion force (simple attraction to center)
    // float cohesionStrength = 0.05; // Old hardcoded value
    vec3 center = vec3(0.0);
    vec3 toCenter = center - pi; // Vector from particle to center (pi is already scaled by DOMAIN_SCALE)
    // A gentler cohesion: force proportional to distance, acting like a spring to the center
    force += toCenter * COHESION_STRENGTH * MASS; // COHESION_STRENGTH from UBO


    outForce = vec4(force, 0.); // Output vec3 force, w component is 0
}