// OdinCog - OpenCog Implementation in Pure Odin
// ECAN - Economic Attention Allocation Network
//
// ECAN manages computational attention in the AtomSpace using economic
// metaphors. Atoms compete for attention (STI) and pay rent for storage.
// This module implements:
// - Attention value management
// - Attentional focus
// - Importance updating, spreading, and diffusion
// - Forgetting and rent collection

package odincog_ecan

import "core:mem"
import "core:math"
import "core:sync"
import "core:container/priority_queue"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"

// =============================================================================
// ATTENTION BANK
// =============================================================================

// AttentionBank manages the global attention budget
AttentionBank :: struct {
    // Total STI in the system (should be conserved)
    total_sti:          i64,
    
    // Total LTI in the system
    total_lti:          i64,
    
    // STI funds available for distribution
    sti_funds:          i64,
    
    // LTI funds available
    lti_funds:          i64,
    
    // Rent collected this cycle
    rent_collected:     i64,
    
    // Configuration
    target_total_sti:   i64,
    min_sti:            i16,
    max_sti:            i16,
    
    // Concurrency
    lock:               sync.Mutex,
}

// Default attention bank configuration
DEFAULT_ATTENTION_BANK :: AttentionBank{
    total_sti = 0,
    total_lti = 0,
    sti_funds = 1000,
    lti_funds = 1000,
    rent_collected = 0,
    target_total_sti = 100000,
    min_sti = -32768,
    max_sti = 32767,
}

// Deposit STI into the bank
bank_deposit_sti :: proc(bank: ^AttentionBank, amount: i64) {
    sync.guard(&bank.lock)
    bank.sti_funds += amount
}

// Withdraw STI from the bank
bank_withdraw_sti :: proc(bank: ^AttentionBank, amount: i64) -> i64 {
    sync.guard(&bank.lock)
    
    withdrawn := min(amount, bank.sti_funds)
    bank.sti_funds -= withdrawn
    return withdrawn
}

// Update total STI count
bank_update_total_sti :: proc(bank: ^AttentionBank, delta: i64) {
    sync.guard(&bank.lock)
    bank.total_sti += delta
}

// =============================================================================
// ATTENTIONAL FOCUS
// =============================================================================

// AttentionalFocus manages the set of highly important atoms
AttentionalFocus :: struct {
    // Atoms in the attentional focus, ordered by STI
    atoms:              [dynamic]atom.Handle,
    
    // STI values for quick lookup
    sti_values:         map[atom.Handle]i16,
    
    // Focus boundary (minimum STI to be in focus)
    boundary:           i16,
    
    // Maximum size of the focus
    max_size:           int,
    
    // Reference to atomspace
    atomspace:          ^atomspace.AtomSpace,
    
    allocator:          mem.Allocator,
}

// Create attentional focus
af_create :: proc(as: ^atomspace.AtomSpace, boundary: i16 = 100, max_size: int = 1000, allocator := context.allocator) -> ^AttentionalFocus {
    af := new(AttentionalFocus, allocator)
    af.atoms = make([dynamic]atom.Handle, allocator)
    af.sti_values = make(map[atom.Handle]i16, allocator)
    af.boundary = boundary
    af.max_size = max_size
    af.atomspace = as
    af.allocator = allocator
    return af
}

// Destroy attentional focus
af_destroy :: proc(af: ^AttentionalFocus) {
    if af == nil {
        return
    }
    delete(af.atoms)
    delete(af.sti_values)
    free(af, af.allocator)
}

// Update the attentional focus
af_update :: proc(af: ^AttentionalFocus) {
    clear(&af.atoms)
    clear(&af.sti_values)
    
    // Iterate through all atoms and find those above boundary
    it := atomspace.atomspace_iterator(af.atomspace)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        if a.attention_value.sti >= af.boundary {
            append(&af.atoms, h)
            af.sti_values[h] = a.attention_value.sti
        }
    }
    
    // Sort by STI (descending) - simple insertion sort for now
    af_sort_by_sti(af)
    
    // Trim to max size
    if len(af.atoms) > af.max_size {
        resize(&af.atoms, af.max_size)
    }
}

// Sort atoms by STI (descending)
af_sort_by_sti :: proc(af: ^AttentionalFocus) {
    // Simple insertion sort (fine for small sizes)
    for i := 1; i < len(af.atoms); i += 1 {
        j := i
        for j > 0 {
            sti_j := af.sti_values[af.atoms[j]]
            sti_prev := af.sti_values[af.atoms[j-1]]
            if sti_j > sti_prev {
                af.atoms[j], af.atoms[j-1] = af.atoms[j-1], af.atoms[j]
                j -= 1
            } else {
                break
            }
        }
    }
}

// Check if atom is in attentional focus
af_contains :: proc(af: ^AttentionalFocus, h: atom.Handle) -> bool {
    _, ok := af.sti_values[h]
    return ok
}

// Get atoms in focus
af_get_atoms :: proc(af: ^AttentionalFocus) -> []atom.Handle {
    return af.atoms[:]
}

// Get top N atoms by STI
af_get_top_n :: proc(af: ^AttentionalFocus, n: int) -> []atom.Handle {
    count := min(n, len(af.atoms))
    return af.atoms[:count]
}

// =============================================================================
// ECAN MANAGER
// =============================================================================

// ECANConfig holds ECAN configuration parameters
ECANConfig :: struct {
    // Attentional focus boundary
    af_boundary:            i16,
    
    // Maximum atoms in focus
    af_max_size:            int,
    
    // Rent parameters
    rent_per_sti:           f64,  // Rent charged per unit of STI
    rent_period:            int,  // Cycles between rent collection
    
    // Diffusion parameters
    diffusion_percent:      f64,  // Percent of STI to diffuse each cycle
    spreading_factor:       f64,  // How much to spread via links
    
    // Forgetting parameters
    forgetting_threshold:   i16,  // STI below which atoms may be forgotten
    vlti_protection:        bool, // VLTI atoms are protected from forgetting
    
    // Hebbian learning
    hebbian_maxlink_value:  f64,
    hebbian_conjunction:    bool,
}

DEFAULT_ECAN_CONFIG :: ECANConfig{
    af_boundary = 100,
    af_max_size = 1000,
    rent_per_sti = 0.01,
    rent_period = 10,
    diffusion_percent = 0.1,
    spreading_factor = 0.5,
    forgetting_threshold = -100,
    vlti_protection = true,
    hebbian_maxlink_value = 1.0,
    hebbian_conjunction = true,
}

// ECANManager coordinates all ECAN activities
ECANManager :: struct {
    atomspace:        ^atomspace.AtomSpace,
    config:           ECANConfig,
    bank:             AttentionBank,
    focus:            ^AttentionalFocus,
    
    // Cycle counter
    cycle:            u64,
    
    allocator:        mem.Allocator,
}

// Create ECAN manager
ecan_create :: proc(
    as: ^atomspace.AtomSpace,
    config: ECANConfig = DEFAULT_ECAN_CONFIG,
    allocator := context.allocator,
) -> ^ECANManager {
    em := new(ECANManager, allocator)
    em.atomspace = as
    em.config = config
    em.bank = DEFAULT_ATTENTION_BANK
    em.focus = af_create(as, config.af_boundary, config.af_max_size, allocator)
    em.cycle = 0
    em.allocator = allocator
    return em
}

// Destroy ECAN manager
ecan_destroy :: proc(em: ^ECANManager) {
    if em == nil {
        return
    }
    af_destroy(em.focus)
    free(em, em.allocator)
}

// Run one ECAN cycle
ecan_run_cycle :: proc(em: ^ECANManager) {
    em.cycle += 1
    
    // 1. Update attentional focus
    af_update(em.focus)
    
    // 2. Run importance spreading
    ecan_spread_importance(em)
    
    // 3. Run importance diffusion
    ecan_diffuse_importance(em)
    
    // 4. Collect rent (periodically)
    if em.cycle % u64(em.config.rent_period) == 0 {
        ecan_collect_rent(em)
    }
    
    // 5. Run forgetting agent
    ecan_forget(em)
}

// =============================================================================
// IMPORTANCE SPREADING
// =============================================================================

// Spread importance from source atoms through links
ecan_spread_importance :: proc(em: ^ECANManager) {
    // Get atoms in attentional focus
    focus_atoms := af_get_atoms(em.focus)
    
    for src_h in focus_atoms {
        src_atom, ok := atomspace.atomspace_get(em.atomspace, src_h)
        if !ok {
            continue
        }
        
        // Calculate amount to spread
        spread_amount := i16(f64(src_atom.attention_value.sti) * em.config.spreading_factor * 0.1)
        if spread_amount <= 0 {
            continue
        }
        
        // Get incoming links (links that have this atom as target)
        incoming := atomspace.get_incoming(em.atomspace, src_h)
        
        for link_h in incoming {
            link_atom, ok2 := atomspace.atomspace_get(em.atomspace, link_h)
            if !ok2 {
                continue
            }
            
            // Skip non-Hebbian links
            if !is_hebbian_link(link_atom.atom_type) {
                continue
            }
            
            // Get the other target of the link
            outgoing := atom.atom_get_outgoing(link_atom)
            for target_h in outgoing {
                if atom.handle_equals(target_h, src_h) {
                    continue
                }
                
                // Spread to target
                target_atom, ok3 := atomspace.atomspace_get(em.atomspace, target_h)
                if ok3 {
                    ecan_stimulate(em, target_atom, spread_amount)
                }
            }
        }
    }
}

// Check if link type is Hebbian
is_hebbian_link :: proc(t: types.AtomType) -> bool {
    #partial switch t {
        case .HEBBIAN_LINK, .ASYMMETRIC_HEBBIAN_LINK, 
             .SYMMETRIC_HEBBIAN_LINK, .INVERSE_HEBBIAN_LINK:
            return true
        case:
            return false
    }
}

// =============================================================================
// IMPORTANCE DIFFUSION
// =============================================================================

// Diffuse importance evenly across neighbors
ecan_diffuse_importance :: proc(em: ^ECANManager) {
    // Get atoms in attentional focus
    focus_atoms := af_get_atoms(em.focus)
    
    // Calculate diffusion amounts first (to avoid order dependence)
    diffusion_map := make(map[atom.Handle]i16, em.allocator)
    defer delete(diffusion_map)
    
    for src_h in focus_atoms {
        src_atom, ok := atomspace.atomspace_get(em.atomspace, src_h)
        if !ok {
            continue
        }
        
        // Calculate amount to diffuse
        diffuse_amount := i16(f64(src_atom.attention_value.sti) * em.config.diffusion_percent)
        if diffuse_amount <= 0 {
            continue
        }
        
        // Get neighbors via incoming links
        incoming := atomspace.get_incoming(em.atomspace, src_h)
        neighbor_count := 0
        
        for link_h in incoming {
            link_atom, ok2 := atomspace.atomspace_get(em.atomspace, link_h)
            if !ok2 {
                continue
            }
            
            outgoing := atom.atom_get_outgoing(link_atom)
            for target_h in outgoing {
                if !atom.handle_equals(target_h, src_h) {
                    neighbor_count += 1
                }
            }
        }
        
        if neighbor_count == 0 {
            continue
        }
        
        // Distribute equally among neighbors
        per_neighbor := diffuse_amount / i16(neighbor_count)
        if per_neighbor <= 0 {
            continue
        }
        
        for link_h in incoming {
            link_atom, ok2 := atomspace.atomspace_get(em.atomspace, link_h)
            if !ok2 {
                continue
            }
            
            outgoing := atom.atom_get_outgoing(link_atom)
            for target_h in outgoing {
                if !atom.handle_equals(target_h, src_h) {
                    existing := diffusion_map[target_h]
                    diffusion_map[target_h] = existing + per_neighbor
                }
            }
        }
        
        // Deduct from source
        src_atom.attention_value.sti -= diffuse_amount
    }
    
    // Apply diffusion
    for target_h, amount in diffusion_map {
        if target_atom, ok := atomspace.atomspace_get(em.atomspace, target_h); ok {
            target_atom.attention_value.sti += amount
        }
    }
}

// =============================================================================
// RENT COLLECTION
// =============================================================================

// Collect rent from all atoms
ecan_collect_rent :: proc(em: ^ECANManager) {
    em.bank.rent_collected = 0
    
    it := atomspace.atomspace_iterator(em.atomspace)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        // Calculate rent based on STI
        rent := i16(f64(a.attention_value.sti) * em.config.rent_per_sti)
        if rent <= 0 {
            rent = 1  // Minimum rent
        }
        
        // Collect rent
        a.attention_value.sti -= rent
        em.bank.rent_collected += i64(rent)
        
        // Clamp STI
        a.attention_value.sti = clamp(a.attention_value.sti, em.config.forgetting_threshold, em.bank.max_sti)
    }
    
    // Add collected rent to bank
    bank_deposit_sti(&em.bank, em.bank.rent_collected)
}

// =============================================================================
// FORGETTING AGENT
// =============================================================================

// Forget (remove) low-importance atoms
ecan_forget :: proc(em: ^ECANManager) {
    atoms_to_forget := make([dynamic]atom.Handle, em.allocator)
    defer delete(atoms_to_forget)
    
    it := atomspace.atomspace_iterator(em.atomspace)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        // Check if below forgetting threshold
        if a.attention_value.sti < em.config.forgetting_threshold {
            // Check VLTI protection
            if em.config.vlti_protection && a.attention_value.vlti {
                continue
            }
            
            append(&atoms_to_forget, h)
        }
    }
    
    // Remove forgotten atoms
    for h in atoms_to_forget {
        atomspace.remove_atom(em.atomspace, h, false)  // Don't recursive delete
    }
}

// =============================================================================
// STIMULATION
// =============================================================================

// Stimulate an atom with additional STI
ecan_stimulate :: proc(em: ^ECANManager, a: ^atom.Atom, amount: i16) {
    a.attention_value.sti += amount
    a.attention_value.sti = clamp(a.attention_value.sti, em.bank.min_sti, em.bank.max_sti)
    
    // Update LTI based on cumulative stimulation
    if a.attention_value.sti > em.focus.boundary {
        a.attention_value.lti += 1
    }
}

// Stimulate an atom by handle
ecan_stimulate_handle :: proc(em: ^ECANManager, h: atom.Handle, amount: i16) {
    if a, ok := atomspace.atomspace_get(em.atomspace, h); ok {
        ecan_stimulate(em, a, amount)
    }
}

// =============================================================================
// HEBBIAN LEARNING
// =============================================================================

// Create or strengthen Hebbian link between co-activated atoms
ecan_hebbian_update :: proc(em: ^ECANManager, h1: atom.Handle, h2: atom.Handle) {
    // Check if both atoms are in focus
    if !af_contains(em.focus, h1) || !af_contains(em.focus, h2) {
        return
    }
    
    // Check if Hebbian link already exists
    incoming := atomspace.get_incoming_by_type(em.atomspace, h1, .SYMMETRIC_HEBBIAN_LINK)
    
    for link_h in incoming {
        link_atom, ok := atomspace.atomspace_get(em.atomspace, link_h)
        if !ok {
            continue
        }
        
        outgoing := atom.atom_get_outgoing(link_atom)
        for target_h in outgoing {
            if atom.handle_equals(target_h, h2) {
                // Strengthen existing link
                s := atom.tv_get_strength(link_atom.truth_value)
                c := atom.tv_get_confidence(link_atom.truth_value)
                
                // Increase strength (Hebbian learning)
                new_s := min(s + 0.1, em.config.hebbian_maxlink_value)
                new_c := min(c + 0.01, 0.99)
                
                link_atom.truth_value = atom.make_stv(new_s, new_c)
                return
            }
        }
    }
    
    // Create new Hebbian link
    atomspace.add_link(
        em.atomspace,
        .SYMMETRIC_HEBBIAN_LINK,
        []atom.Handle{h1, h2},
        atom.make_stv(0.5, 0.5),
    )
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get total STI in the system
ecan_get_total_sti :: proc(em: ^ECANManager) -> i64 {
    total: i64 = 0
    
    it := atomspace.atomspace_iterator(em.atomspace)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        total += i64(a.attention_value.sti)
    }
    
    return total
}

// Normalize STI values to maintain target total
ecan_normalize_sti :: proc(em: ^ECANManager) {
    current_total := ecan_get_total_sti(em)
    
    if current_total == 0 {
        return
    }
    
    scale := f64(em.bank.target_total_sti) / f64(current_total)
    
    it := atomspace.atomspace_iterator(em.atomspace)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        new_sti := i16(f64(a.attention_value.sti) * scale)
        a.attention_value.sti = clamp(new_sti, em.bank.min_sti, em.bank.max_sti)
    }
}

// Get attention statistics
ECANStats :: struct {
    total_sti:        i64,
    total_lti:        i64,
    atoms_in_focus:   int,
    min_sti:          i16,
    max_sti:          i16,
    avg_sti:          f64,
    cycle:            u64,
}

ecan_get_stats :: proc(em: ^ECANManager) -> ECANStats {
    stats := ECANStats{
        cycle = em.cycle,
        atoms_in_focus = len(em.focus.atoms),
        min_sti = em.bank.max_sti,
        max_sti = em.bank.min_sti,
    }
    
    count := 0
    it := atomspace.atomspace_iterator(em.atomspace)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        stats.total_sti += i64(a.attention_value.sti)
        stats.total_lti += i64(a.attention_value.lti)
        stats.min_sti = min(stats.min_sti, a.attention_value.sti)
        stats.max_sti = max(stats.max_sti, a.attention_value.sti)
        count += 1
    }
    
    if count > 0 {
        stats.avg_sti = f64(stats.total_sti) / f64(count)
    }
    
    return stats
}
