// spikes.vert.glsl (New version for Icosphere Globule)
#version 300 es
precision highp float;

uniform mat4 u_worldMatrix;
uniform mat4 u_viewMatrix;
uniform mat4 u_projectionMatrix;

// SPH particle data
uniform sampler2D u_particlePosTexture; // Texture with particle positions
uniform vec3 u_domainScale;            // Scale factor for particle positions from texture
uniform int u_numParticles;            // Total number of SPH particles (can be NUM_PARTICLES from JS)
uniform ivec2 u_particleTexSize;       // Dimensions of the particle position texture

// Displacement parameters (tunable)
uniform float u_influenceRadius;    // How far a particle's influence reaches (world units)
uniform float u_displacementFactor; // Overall strength of displacement
// uniform float u_smoothFactor;    // For smooth min (if implementing Voronoi-style)

// Input vertex attributes from icosphere
in vec3 position; // Vertex position (local space for sphere, e.g., radius 0.4, centered at origin)
in vec3 normal;   // Vertex normal (local space for sphere, points outwards from origin)
// in vec2 texcoord; // Unused for now

out vec3 v_position_world; // For fragment shader
out vec3 v_normal_world;   // For fragment shader


// Function to calculate displacement for a single sphere vertex 'p_sphere_local'
// Placeholder implementation: uniform displacement based on u_displacementFactor (which is audio-modulated)
float calculateDisplacement_placeholder(vec3 p_sphere_local_vertex_pos) {
    // u_displacementFactor is already (base_displacement_from_tweakpane + audio_boost) from JS.
    // This value directly represents the desired magnitude of displacement along the normal.
    return u_displacementFactor;
}

void main() {
    // u_displacementFactor is (base_displacement + audio_boost) from JS.
    // This is now the magnitude of displacement along the normal.
    float displacement_magnitude = calculateDisplacement_placeholder(position);

    // Displace vertex along its original normal
    vec3 displaced_position_local = position + normal * displacement_magnitude;
    
    // Transform to world and view/projection space
    vec4 world_pos = u_worldMatrix * vec4(displaced_position_local, 1.0);
    v_position_world = world_pos.xyz;

    // Normals:
    // For a sphere displaced radially from its center, the new normal is often approximated
    // by normalizing the displaced position (if the sphere is centered at the origin).
    // This assumes 'position' and 'displaced_position_local' are vectors from the sphere's center.
    vec3 final_normal_local;
    if (length(displaced_position_local) < 0.0001) { // Avoid normalization of zero vector
        final_normal_local = normal; // Use original normal if displacement collapses to origin
    } else {
        final_normal_local = normalize(displaced_position_local);
    }
    v_normal_world = normalize((u_worldMatrix * vec4(final_normal_local, 0.0)).xyz);

    gl_Position = u_projectionMatrix * u_viewMatrix * world_pos;
}