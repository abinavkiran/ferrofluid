// src/app/shader/utils/particle-utils.glsl

// convert 2D texture coordinates to a 1D index
int tex2ndx(ivec2 tex_size, ivec2 tex_coord) {
    return tex_coord.x + tex_coord.y * tex_size.x;
}

// convert a 1D index to 2D texture coordinates
ivec2 ndx2tex(ivec2 tex_size, int index) {
    // Ensure index is not negative, can happen if cellId becomes negative before clamping
    // though pos2CellIndex should prevent this for cell_idx.
    index = max(0, index);
    return ivec2(index % tex_size.x, index / tex_size.x);
}

// Get the 3D cell index from a world position.
// Assumes grid is centered at origin.
// world_pos: particle position in simulation world space (already scaled by DOMAIN_SCALE).
// grid_dims: number of cells along each axis (e.g., ivec3(11, 11, 11)).
// cell_size: size of one cell in world units (H, the kernel radius).
ivec3 pos2CellIndex(vec3 world_pos, ivec3 grid_dims, float cell_size) {
    // Calculate the total size of the grid in world units
    vec3 grid_total_world_size = vec3(grid_dims) * cell_size;

    // Offset world_pos so that the conceptual minimum corner of the grid volume
    // (e.g., world_pos corresponding to cell_idx (0,0,0)) aligns with the origin (0,0,0)
    // for the subsequent division.
    vec3 local_grid_pos = world_pos + grid_total_world_size * 0.5;

    ivec3 cell_idx = ivec3(floor(local_grid_pos / cell_size));

    // Clamp to grid boundaries [0, grid_dims-1]
    cell_idx = max(ivec3(0), min(cell_idx, grid_dims - 1));

    return cell_idx;
}

// Convert a 3D cell index to a 1D linear cell ID.
// cell_idx: 3D index of the cell (x, y, z components), already clamped by pos2CellIndex.
// grid_dims: number of cells along each axis.
int cell3DToLinearId(ivec3 cell_idx, ivec3 grid_dims) {
    // Linearize: X varies fastest, then Y, then Z.
    return cell_idx.x + cell_idx.y * grid_dims.x + cell_idx.z * grid_dims.x * grid_dims.y;
}

/*
// --- Old 2D versions from the project ---
// ivec2 pos2CellIndex_OLD(vec2 p, ivec2 cellTexSize, vec2 domainScale, float cellSize) {
// This assumed p was in [-1,1] if domainScale was the full world size.
// Or p was [-0.5, 0.5] if domainScale was half world size (radius).
// The multiplication by 0.5 and addition of 0.5 suggests p was intended to be in [-1,1] range.
// vec2 pi = p * 0.5 + 0.5; // map [-1,1] to [0,1]
// pi = clamp(pi, vec2(0.001), vec2(.999)); // clamp to avoid edges
// pi *= domainScale; // scale to world size [0, domainScale]
// return ivec2(pi / cellSize); // get cell index
// }

// int pos2CellId_OLD(vec2 p, ivec2 cellTexSize, vec2 domainScale, float cellSize) {
// ivec2 cellIndex = pos2CellIndex_OLD(p, cellTexSize, domainScale, cellSize);
// return tex2ndx(cellTexSize, cellIndex);
// }

// This was an alternative hashing function, not used by the main SPH logic previously.
// int getFlatCellIndex_HASH(ivec2 cellIndex, int numGridCells) {
// int p1 = 73856093; // some large primes
// int p2 = 19349663;
// int n = p1 * cellIndex.x ^ p2 * cellIndex.y;
// n %= numGridCells; // Ensure it's within the number of cells
// return n;
// }
*/