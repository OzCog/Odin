// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Arena Memory Allocator
//
// This module implements custom arena allocators optimized for the cognitive
// architecture's memory access patterns. Includes:
// - Arena allocator for zero-cost per-frame allocations
// - Double-buffering for state transitions
// - Scratch allocators for temporary computations
// - Memory pools for hot paths (atoms, patterns, bindings)

package odincog_arena_memory

import "core:mem"
import "core:sync"
import "core:intrinsics"

// =============================================================================
// ARENA ALLOCATOR
// =============================================================================

// Arena is a simple bump allocator that grows monotonically
Arena :: struct {
    data:           []byte,
    offset:         int,
    peak_usage:     int,
    allocations:    int,
    
    // Backing allocator for the arena's memory
    backing:        mem.Allocator,
    
    // Optional: linked list of additional blocks
    next_block:     ^Arena,
    block_size:     int,
}

// ArenaConfig for arena creation
ArenaConfig :: struct {
    initial_size:   int,
    grow_size:      int,
    alignment:      int,
}

DEFAULT_ARENA_CONFIG :: ArenaConfig{
    initial_size = 1024 * 1024,      // 1MB
    grow_size = 1024 * 1024,         // 1MB growth
    alignment = 16,
}

// Create a new arena
arena_create :: proc(config: ArenaConfig = DEFAULT_ARENA_CONFIG, backing := context.allocator) -> ^Arena {
    arena := new(Arena, backing)
    arena.data = make([]byte, config.initial_size, backing)
    arena.offset = 0
    arena.peak_usage = 0
    arena.allocations = 0
    arena.backing = backing
    arena.block_size = config.grow_size
    arena.next_block = nil
    return arena
}

// Destroy an arena and free all memory
arena_destroy :: proc(arena: ^Arena) {
    if arena == nil {
        return
    }
    
    // Free any overflow blocks
    next := arena.next_block
    for next != nil {
        current := next
        next = current.next_block
        delete(current.data, current.backing)
        free(current, current.backing)
    }
    
    delete(arena.data, arena.backing)
    free(arena, arena.backing)
}

// Reset arena to empty (keeps allocated memory)
arena_reset :: proc(arena: ^Arena) {
    arena.offset = 0
    arena.allocations = 0
    
    // Reset overflow blocks too
    next := arena.next_block
    for next != nil {
        next.offset = 0
        next.allocations = 0
        next = next.next_block
    }
}

// Allocate memory from arena
arena_alloc :: proc(arena: ^Arena, size: int, alignment: int = 16) -> rawptr {
    // Align the current offset
    aligned_offset := align_forward(arena.offset, alignment)
    
    // Check if we have space
    if aligned_offset + size > len(arena.data) {
        // Try overflow blocks
        if arena.next_block != nil {
            return arena_alloc(arena.next_block, size, alignment)
        }
        
        // Allocate new block
        new_size := max(arena.block_size, size + alignment)
        new_block := new(Arena, arena.backing)
        new_block.data = make([]byte, new_size, arena.backing)
        new_block.offset = 0
        new_block.backing = arena.backing
        new_block.block_size = arena.block_size
        new_block.next_block = nil
        
        arena.next_block = new_block
        return arena_alloc(new_block, size, alignment)
    }
    
    ptr := &arena.data[aligned_offset]
    arena.offset = aligned_offset + size
    arena.allocations += 1
    
    if arena.offset > arena.peak_usage {
        arena.peak_usage = arena.offset
    }
    
    return ptr
}

// Create an Odin allocator from arena
arena_allocator :: proc(arena: ^Arena) -> mem.Allocator {
    return mem.Allocator{
        procedure = arena_allocator_proc,
        data = arena,
    }
}

// Arena allocator procedure
arena_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
    arena := cast(^Arena)allocator_data
    
    switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            ptr := arena_alloc(arena, size, alignment)
            if ptr == nil {
                return nil, .Out_Of_Memory
            }
            if mode == .Alloc {
                mem.zero(ptr, size)
            }
            return mem.byte_slice(ptr, size), nil
            
        case .Resize, .Resize_Non_Zeroed:
            // Arena doesn't support true resize - allocate new
            new_ptr := arena_alloc(arena, size, alignment)
            if new_ptr == nil {
                return nil, .Out_Of_Memory
            }
            if old_memory != nil && old_size > 0 {
                copy_size := min(size, old_size)
                mem.copy(new_ptr, old_memory, copy_size)
            }
            if mode == .Resize && size > old_size {
                mem.zero(mem.ptr_offset(cast(^byte)new_ptr, old_size), size - old_size)
            }
            return mem.byte_slice(new_ptr, size), nil
            
        case .Free:
            // Arena doesn't support individual frees - no-op
            return nil, nil
            
        case .Free_All:
            arena_reset(arena)
            return nil, nil
            
        case .Query_Info:
            return nil, .Mode_Not_Implemented
            
        case .Query_Features:
            set := cast(^mem.Allocator_Features)old_memory
            set^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free_All}
            return nil, nil
    }
    
    return nil, nil
}

// =============================================================================
// DOUBLE BUFFER ARENA
// =============================================================================

// DoubleBufferArena provides two alternating arenas for frame-to-frame allocation
DoubleBufferArena :: struct {
    arenas:         [2]^Arena,
    current:        int,
    
    // Stats
    total_swaps:    u64,
}

// Create a double-buffered arena
double_buffer_create :: proc(
    config: ArenaConfig = DEFAULT_ARENA_CONFIG,
    backing := context.allocator,
) -> ^DoubleBufferArena {
    db := new(DoubleBufferArena, backing)
    db.arenas[0] = arena_create(config, backing)
    db.arenas[1] = arena_create(config, backing)
    db.current = 0
    db.total_swaps = 0
    return db
}

// Destroy double-buffered arena
double_buffer_destroy :: proc(db: ^DoubleBufferArena) {
    if db == nil {
        return
    }
    arena_destroy(db.arenas[0])
    arena_destroy(db.arenas[1])
    free(db)
}

// Get the current arena (for this frame)
double_buffer_current :: proc(db: ^DoubleBufferArena) -> ^Arena {
    return db.arenas[db.current]
}

// Get the previous arena (from last frame)
double_buffer_previous :: proc(db: ^DoubleBufferArena) -> ^Arena {
    return db.arenas[1 - db.current]
}

// Swap buffers (call at end of frame)
double_buffer_swap :: proc(db: ^DoubleBufferArena) {
    db.current = 1 - db.current
    arena_reset(db.arenas[db.current])
    db.total_swaps += 1
}

// Get allocator for current buffer
double_buffer_allocator :: proc(db: ^DoubleBufferArena) -> mem.Allocator {
    return arena_allocator(db.arenas[db.current])
}

// =============================================================================
// SCRATCH ALLOCATOR
// =============================================================================

// ScratchArena is a temporary allocation scope within an arena
ScratchArena :: struct {
    arena:          ^Arena,
    saved_offset:   int,
}

// Begin a scratch scope
scratch_begin :: proc(arena: ^Arena) -> ScratchArena {
    return ScratchArena{
        arena = arena,
        saved_offset = arena.offset,
    }
}

// End scratch scope (revert allocations)
scratch_end :: proc(scratch: ScratchArena) {
    scratch.arena.offset = scratch.saved_offset
}

// Get allocator for scratch scope
scratch_allocator :: proc(scratch: ^ScratchArena) -> mem.Allocator {
    return arena_allocator(scratch.arena)
}

// =============================================================================
// MEMORY POOL
// =============================================================================

// Pool provides fixed-size block allocation with O(1) alloc/free
Pool :: struct {
    block_size:     int,
    block_align:    int,
    blocks_per_chunk: int,
    
    // Free list (intrusive linked list)
    free_list:      rawptr,
    
    // Chunks of memory
    chunks:         [dynamic][]byte,
    
    // Stats
    total_blocks:   int,
    used_blocks:    int,
    
    backing:        mem.Allocator,
}

// FreeNode is used for the intrusive free list
FreeNode :: struct {
    next: ^FreeNode,
}

// Create a memory pool
pool_create :: proc(
    block_size: int,
    blocks_per_chunk: int = 64,
    backing := context.allocator,
) -> ^Pool {
    pool := new(Pool, backing)
    pool.block_size = max(block_size, size_of(FreeNode))
    pool.block_align = 16
    pool.blocks_per_chunk = blocks_per_chunk
    pool.free_list = nil
    pool.chunks = make([dynamic][]byte, backing)
    pool.backing = backing
    pool.total_blocks = 0
    pool.used_blocks = 0
    
    // Allocate initial chunk
    pool_grow(pool)
    
    return pool
}

// Destroy a memory pool
pool_destroy :: proc(pool: ^Pool) {
    if pool == nil {
        return
    }
    
    for chunk in pool.chunks {
        delete(chunk, pool.backing)
    }
    delete(pool.chunks)
    free(pool, pool.backing)
}

// Grow the pool by adding a new chunk
pool_grow :: proc(pool: ^Pool) {
    chunk_size := pool.block_size * pool.blocks_per_chunk
    chunk := make([]byte, chunk_size, pool.backing)
    append(&pool.chunks, chunk)
    
    // Add all blocks to free list
    for i := 0; i < pool.blocks_per_chunk; i += 1 {
        block := &chunk[i * pool.block_size]
        node := cast(^FreeNode)block
        node.next = cast(^FreeNode)pool.free_list
        pool.free_list = node
    }
    
    pool.total_blocks += pool.blocks_per_chunk
}

// Allocate a block from the pool
pool_alloc :: proc(pool: ^Pool) -> rawptr {
    if pool.free_list == nil {
        pool_grow(pool)
    }
    
    node := cast(^FreeNode)pool.free_list
    pool.free_list = node.next
    pool.used_blocks += 1
    
    // Zero the memory
    mem.zero(node, pool.block_size)
    
    return node
}

// Free a block back to the pool
pool_free :: proc(pool: ^Pool, ptr: rawptr) {
    if ptr == nil {
        return
    }
    
    node := cast(^FreeNode)ptr
    node.next = cast(^FreeNode)pool.free_list
    pool.free_list = node
    pool.used_blocks -= 1
}

// Reset the pool (all blocks become free)
pool_reset :: proc(pool: ^Pool) {
    pool.free_list = nil
    pool.used_blocks = 0
    
    // Re-add all blocks to free list
    for chunk in pool.chunks {
        for i := 0; i < pool.blocks_per_chunk; i += 1 {
            if i * pool.block_size >= len(chunk) {
                break
            }
            block := &chunk[i * pool.block_size]
            node := cast(^FreeNode)block
            node.next = cast(^FreeNode)pool.free_list
            pool.free_list = node
        }
    }
}

// Create allocator from pool (only supports single-size allocations)
pool_allocator :: proc(pool: ^Pool) -> mem.Allocator {
    return mem.Allocator{
        procedure = pool_allocator_proc,
        data = pool,
    }
}

// Pool allocator procedure
pool_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
    pool := cast(^Pool)allocator_data
    
    switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            if size > pool.block_size {
                return nil, .Invalid_Argument
            }
            ptr := pool_alloc(pool)
            if ptr == nil {
                return nil, .Out_Of_Memory
            }
            return mem.byte_slice(ptr, pool.block_size), nil
            
        case .Free:
            pool_free(pool, old_memory)
            return nil, nil
            
        case .Free_All:
            pool_reset(pool)
            return nil, nil
            
        case .Resize, .Resize_Non_Zeroed:
            if size > pool.block_size {
                return nil, .Invalid_Argument
            }
            return mem.byte_slice(old_memory, pool.block_size), nil
            
        case .Query_Info:
            return nil, .Mode_Not_Implemented
            
        case .Query_Features:
            set := cast(^mem.Allocator_Features)old_memory
            set^ = {.Alloc, .Free, .Free_All}
            return nil, nil
    }
    
    return nil, nil
}

// =============================================================================
// FRAME ALLOCATOR
// =============================================================================

// FrameAllocator combines arena + pool allocation for optimal per-frame usage
FrameAllocator :: struct {
    // Arena for variable-size allocations
    arena:          ^Arena,
    
    // Pools for common sizes
    small_pool:     ^Pool,   // 64 bytes
    medium_pool:    ^Pool,   // 256 bytes
    large_pool:     ^Pool,   // 1024 bytes
    
    // Thresholds
    small_threshold:  int,
    medium_threshold: int,
    large_threshold:  int,
    
    backing:        mem.Allocator,
}

// Create frame allocator
frame_allocator_create :: proc(
    arena_size: int = 1024 * 1024,
    backing := context.allocator,
) -> ^FrameAllocator {
    fa := new(FrameAllocator, backing)
    
    fa.arena = arena_create(ArenaConfig{
        initial_size = arena_size,
        grow_size = arena_size / 2,
        alignment = 16,
    }, backing)
    
    fa.small_pool = pool_create(64, 256, backing)
    fa.medium_pool = pool_create(256, 64, backing)
    fa.large_pool = pool_create(1024, 16, backing)
    
    fa.small_threshold = 64
    fa.medium_threshold = 256
    fa.large_threshold = 1024
    
    fa.backing = backing
    
    return fa
}

// Destroy frame allocator
frame_allocator_destroy :: proc(fa: ^FrameAllocator) {
    if fa == nil {
        return
    }
    
    arena_destroy(fa.arena)
    pool_destroy(fa.small_pool)
    pool_destroy(fa.medium_pool)
    pool_destroy(fa.large_pool)
    free(fa, fa.backing)
}

// Reset frame allocator (call at end of frame)
frame_allocator_reset :: proc(fa: ^FrameAllocator) {
    arena_reset(fa.arena)
    pool_reset(fa.small_pool)
    pool_reset(fa.medium_pool)
    pool_reset(fa.large_pool)
}

// Get allocator interface
frame_allocator_allocator :: proc(fa: ^FrameAllocator) -> mem.Allocator {
    return mem.Allocator{
        procedure = frame_allocator_proc,
        data = fa,
    }
}

// Frame allocator procedure
frame_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: mem.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
    fa := cast(^FrameAllocator)allocator_data
    
    switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            // Choose allocation strategy based on size
            if size <= fa.small_threshold {
                ptr := pool_alloc(fa.small_pool)
                if ptr != nil {
                    return mem.byte_slice(ptr, size), nil
                }
            } else if size <= fa.medium_threshold {
                ptr := pool_alloc(fa.medium_pool)
                if ptr != nil {
                    return mem.byte_slice(ptr, size), nil
                }
            } else if size <= fa.large_threshold {
                ptr := pool_alloc(fa.large_pool)
                if ptr != nil {
                    return mem.byte_slice(ptr, size), nil
                }
            }
            
            // Fall back to arena
            ptr := arena_alloc(fa.arena, size, alignment)
            if ptr == nil {
                return nil, .Out_Of_Memory
            }
            return mem.byte_slice(ptr, size), nil
            
        case .Free:
            // Frame allocator doesn't free individual allocations
            return nil, nil
            
        case .Free_All:
            frame_allocator_reset(fa)
            return nil, nil
            
        case .Resize, .Resize_Non_Zeroed:
            // Allocate new and copy
            result, err := frame_allocator_proc(
                allocator_data, mode == .Resize ? .Alloc : .Alloc_Non_Zeroed,
                size, alignment, nil, 0, location,
            )
            if err != nil {
                return nil, err
            }
            if old_memory != nil && old_size > 0 {
                mem.copy(&result[0], old_memory, min(size, old_size))
            }
            return result, nil
            
        case .Query_Info:
            return nil, .Mode_Not_Implemented
            
        case .Query_Features:
            set := cast(^mem.Allocator_Features)old_memory
            set^ = {.Alloc, .Free_All, .Resize}
            return nil, nil
    }
    
    return nil, nil
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Align value forward to alignment boundary
align_forward :: proc(value: int, alignment: int) -> int {
    if alignment == 0 {
        return value
    }
    mask := alignment - 1
    return (value + mask) & ~mask
}

// Get arena statistics
ArenaStats :: struct {
    used:           int,
    peak:           int,
    capacity:       int,
    allocations:    int,
    blocks:         int,
}

arena_stats :: proc(arena: ^Arena) -> ArenaStats {
    stats := ArenaStats{
        used = arena.offset,
        peak = arena.peak_usage,
        capacity = len(arena.data),
        allocations = arena.allocations,
        blocks = 1,
    }
    
    // Count overflow blocks
    next := arena.next_block
    for next != nil {
        stats.capacity += len(next.data)
        stats.used += next.offset
        stats.blocks += 1
        next = next.next_block
    }
    
    return stats
}

// Get pool statistics
PoolStats :: struct {
    total_blocks:   int,
    used_blocks:    int,
    free_blocks:    int,
    block_size:     int,
    chunks:         int,
}

pool_stats :: proc(pool: ^Pool) -> PoolStats {
    return PoolStats{
        total_blocks = pool.total_blocks,
        used_blocks = pool.used_blocks,
        free_blocks = pool.total_blocks - pool.used_blocks,
        block_size = pool.block_size,
        chunks = len(pool.chunks),
    }
}
