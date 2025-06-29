
#version 300 es

precision highp float;

uniform sampler2D u_forceTexture;
uniform sampler2D u_positionTexture;
uniform sampler2D u_velocityTexture;
uniform sampler2D u_densityPressureTexture;
uniform float u_dt;
uniform float u_frames;
uniform vec3 u_domainScale; // Changed to vec3
uniform float u_zoom;
uniform float u_audioAgitationStrength; // New uniform

layout(std140) uniform u_PointerParams {
    vec2 pointerPos;
    vec2 pointerVelocity;
    float pointerRadius;
    float pointerStrength;
};

in vec2 v_uv;

layout(location = 0) out vec4 outPosition;
layout(location = 1) out vec4 outVelocity;

 float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}

void main() {
    ivec2 particleTexDimensions = textureSize(u_positionTexture, 0);
    vec4 domainScale = vec4(u_domainScale, 0., 0.);

    vec4 pi = texture(u_positionTexture, v_uv); // pi.xyz is 3D position
    vec4 vi = texture(u_velocityTexture, v_uv); // vi.xyz is 3D velocity
    vec4 fi = texture(u_forceTexture, v_uv);    // fi.xyz is 3D force (as per force.frag.glsl output)
    vec4 ri = texture(u_densityPressureTexture, v_uv); // ri.x is density

    // integrate to update the velocity
    float dt = (u_dt * 0.001);
    float rho = ri.x + 0.000000001; // Add epsilon to avoid division by zero
    vec3 ai_xyz = fi.xyz / rho;    // 3D acceleration
    vi.xyz += ai_xyz * dt;         // Update 3D velocity

    // apply the pointer force (2D, leave as is for now, affects vi.xy)
    // pointerPos from UBO is vec2. This creates a vec4 for interaction.
    vec4 pointerPos_interaction = vec4(pointerPos, 0., 0.);
    float pr = length(pointerPos_interaction.xy * domainScale.xy - pi.xy * domainScale.xy);
    if (pr < pointerRadius) {
        vi.xy += pointerVelocity.xy * pointerStrength * (1. - pr / pointerRadius); // Ensure pointerVelocity.xy if it's vec2
    }

    // apply idle force
    vec2 idleForcePos = vec2(0., -0.1);
    float ir = length(idleForcePos - pi.xy);
    if (ir < 0.25) {
        vi.xy += vec2(0.005 * cos(u_frames * 0.01), 0.);
    }

    // Apply audio agitation to velocity (all components xyz)
    if (u_audioAgitationStrength > 0.0001) { // Check against a small epsilon
        vec2 seed = v_uv + fract(u_frames * 0.012345f + pi.x + pi.y); // Vary seed more
        float n1 = rand(seed * 1.23f);
        float n2 = rand(seed * 2.34f + vec2(0.1f, -0.15f));
        float n3 = rand(seed * 3.45f + vec2(-0.12f, 0.05f));
        vec3 random_dir = normalize(vec3(n1*2.0f-1.0f, n2*2.0f-1.0f, n3*2.0f-1.0f));

        // Add agitation as a direct velocity modification
        vi.xyz += random_dir * u_audioAgitationStrength;
    }

    // update the position (using 3D velocity and SPH acceleration)
    // vi.xyz now contains SPH-updated velocity + pointer/idle effects + audio agitation
    // ai_xyz is purely from SPH forces for this step
    pi.xyz += (vi.xyz + 0.5 * ai_xyz * dt) * dt;

    // apply nervous wiggle (2D, leave as is for now, affects pi.xy)
    float zoomForce = noise(pi.xy * 1000. + 500.);
    pi.xy += zoomForce * 0.008 * max(0., (1. - u_zoom * 2.5));

    outPosition = pi; // Output full vec4, pi.xyz is updated
    outVelocity = vi; // Output full vec4, vi.xyz is updated

    // damp the movement on the edges - Commented out for floating globule, relying on cohesion.
    // float dim = .9; // damping distance (in unscaled particle space)
    // float current_pi_length = length(pi.xyz); // Use .xyz for 3D length
    // float dampingFactor = 1. - max(0., current_pi_length - dim);
    // outVelocity.xyz *= dampingFactor; // Apply to .xyz components
}