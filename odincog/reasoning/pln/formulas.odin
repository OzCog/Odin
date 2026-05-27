// OdinCog - OpenCog Implementation in Pure Odin
// Truth Value Formulas
//
// This module implements the probabilistic truth value formulas used in
// OpenCog's Probabilistic Logic Networks (PLN). These formulas combine
// truth values according to logical operations while properly handling
// uncertainty.

package odincog_truthvalue

import "core:math"
import "../atom"

// =============================================================================
// CONSTANTS
// =============================================================================

// Default confidence-to-count constant
K :: 800.0

// Minimum confidence to prevent division by zero
MIN_CONFIDENCE :: 1.0e-10

// Maximum strength/confidence bounds
MAX_STRENGTH :: 1.0
MIN_STRENGTH :: 0.0

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Clamp value to [0, 1]
clamp01 :: proc(x: f64) -> f64 {
    return clamp(x, 0.0, 1.0)
}

// Convert confidence to count
conf_to_count :: proc(c: f64, k: f64 = K) -> f64 {
    if c >= 1.0 {
        return math.INF_F64
    }
    if c <= 0.0 {
        return 0.0
    }
    return k * c / (1.0 - c)
}

// Convert count to confidence
count_to_conf :: proc(n: f64, k: f64 = K) -> f64 {
    if n < 0.0 {
        return 0.0
    }
    return n / (n + k)
}

// Get count from truth value
tv_to_count :: proc(tv: atom.TruthValue, k: f64 = K) -> f64 {
    switch tv.type {
        case .COUNT:
            return tv.value.count.count
        case .SIMPLE, .FUZZY, .PROBABILISTIC:
            return conf_to_count(atom.tv_get_confidence(tv), k)
        case .INDEFINITE:
            return conf_to_count(atom.tv_get_confidence(tv), k)
    }
    return 0.0
}

// Create truth value from strength and count
make_stv_from_count :: proc(strength: f64, count: f64, k: f64 = K) -> atom.TruthValue {
    return atom.make_stv(clamp01(strength), count_to_conf(count, k))
}

// =============================================================================
// BASIC LOGICAL FORMULAS
// =============================================================================

// NOT formula: P(NOT A) = 1 - P(A)
// Confidence remains the same
tv_not :: proc(tv: atom.TruthValue) -> atom.TruthValue {
    s := atom.tv_get_strength(tv)
    c := atom.tv_get_confidence(tv)
    return atom.make_stv(1.0 - s, c)
}

// AND formula (independence assumption): P(A AND B) = P(A) * P(B)
// Confidence is the minimum of the two
tv_and :: proc(tv1: atom.TruthValue, tv2: atom.TruthValue) -> atom.TruthValue {
    s1 := atom.tv_get_strength(tv1)
    s2 := atom.tv_get_strength(tv2)
    c1 := atom.tv_get_confidence(tv1)
    c2 := atom.tv_get_confidence(tv2)
    
    // Independence-based AND
    new_s := s1 * s2
    new_c := min(c1, c2)
    
    return atom.make_stv(new_s, new_c)
}

// OR formula (independence assumption): P(A OR B) = P(A) + P(B) - P(A)*P(B)
tv_or :: proc(tv1: atom.TruthValue, tv2: atom.TruthValue) -> atom.TruthValue {
    s1 := atom.tv_get_strength(tv1)
    s2 := atom.tv_get_strength(tv2)
    c1 := atom.tv_get_confidence(tv1)
    c2 := atom.tv_get_confidence(tv2)
    
    // Independence-based OR
    new_s := s1 + s2 - s1 * s2
    new_c := min(c1, c2)
    
    return atom.make_stv(clamp01(new_s), new_c)
}

// N-ary AND
tv_and_n :: proc(tvs: []atom.TruthValue) -> atom.TruthValue {
    if len(tvs) == 0 {
        return atom.TRUE_TV
    }
    
    result := tvs[0]
    for i := 1; i < len(tvs); i += 1 {
        result = tv_and(result, tvs[i])
    }
    return result
}

// N-ary OR
tv_or_n :: proc(tvs: []atom.TruthValue) -> atom.TruthValue {
    if len(tvs) == 0 {
        return atom.FALSE_TV
    }
    
    result := tvs[0]
    for i := 1; i < len(tvs); i += 1 {
        result = tv_or(result, tvs[i])
    }
    return result
}

// =============================================================================
// PLN INFERENCE FORMULAS
// =============================================================================

// Revision formula - combines two truth values based on independent evidence
// This is the key formula for merging evidence from different sources
tv_revision :: proc(tv1: atom.TruthValue, tv2: atom.TruthValue, k: f64 = K) -> atom.TruthValue {
    s1 := atom.tv_get_strength(tv1)
    s2 := atom.tv_get_strength(tv2)
    n1 := tv_to_count(tv1, k)
    n2 := tv_to_count(tv2, k)
    
    // Combined count
    n := n1 + n2
    
    if n < MIN_CONFIDENCE {
        return atom.DEFAULT_TV
    }
    
    // Weighted average of strengths
    s := (s1 * n1 + s2 * n2) / n
    
    return make_stv_from_count(s, n, k)
}

// Deduction formula: Given P(A→B) and P(B→C), compute P(A→C)
// sAC = sAB * sBC + (1-sAB) * (sC - sB*sBC) / (1-sB)
tv_deduction :: proc(
    tv_ab: atom.TruthValue,  // P(A→B)
    tv_bc: atom.TruthValue,  // P(B→C)
    tv_a: atom.TruthValue,   // P(A) - prior
    tv_b: atom.TruthValue,   // P(B) - prior
    tv_c: atom.TruthValue,   // P(C) - prior
) -> atom.TruthValue {
    sAB := atom.tv_get_strength(tv_ab)
    sBC := atom.tv_get_strength(tv_bc)
    sA := atom.tv_get_strength(tv_a)
    sB := atom.tv_get_strength(tv_b)
    sC := atom.tv_get_strength(tv_c)
    
    // Avoid division by zero
    if sB >= 1.0 - MIN_CONFIDENCE {
        return atom.make_stv(sAB * sBC, min_confidence(tv_ab, tv_bc, tv_a, tv_b, tv_c))
    }
    
    // Deduction formula
    sAC := sAB * sBC + (1.0 - sAB) * (sC - sB * sBC) / (1.0 - sB)
    
    // Confidence is product of input confidences scaled by strength
    cAB := atom.tv_get_confidence(tv_ab)
    cBC := atom.tv_get_confidence(tv_bc)
    cA := atom.tv_get_confidence(tv_a)
    cB := atom.tv_get_confidence(tv_b)
    cC := atom.tv_get_confidence(tv_c)
    
    // Simple confidence: minimum of relevant confidences
    cAC := min(cAB, cBC) * min(cA, cB, cC)
    
    return atom.make_stv(clamp01(sAC), cAC)
}

// Simplified deduction (using default priors)
tv_deduction_simple :: proc(
    tv_ab: atom.TruthValue,
    tv_bc: atom.TruthValue,
) -> atom.TruthValue {
    sAB := atom.tv_get_strength(tv_ab)
    sBC := atom.tv_get_strength(tv_bc)
    cAB := atom.tv_get_confidence(tv_ab)
    cBC := atom.tv_get_confidence(tv_bc)
    
    // Simplified: sAC = sAB * sBC
    sAC := sAB * sBC
    cAC := cAB * cBC
    
    return atom.make_stv(sAC, cAC)
}

// Induction formula: Given P(A→B) and P(A→C), compute P(B→C)
// This is essentially "generalization from shared property A"
tv_induction :: proc(
    tv_ab: atom.TruthValue,  // P(A→B)
    tv_ac: atom.TruthValue,  // P(A→C)
    tv_a: atom.TruthValue,   // P(A)
    tv_b: atom.TruthValue,   // P(B)
    tv_c: atom.TruthValue,   // P(C)
) -> atom.TruthValue {
    sAB := atom.tv_get_strength(tv_ab)
    sAC := atom.tv_get_strength(tv_ac)
    sA := atom.tv_get_strength(tv_a)
    sB := atom.tv_get_strength(tv_b)
    sC := atom.tv_get_strength(tv_c)
    
    // Avoid division by zero
    if sB <= MIN_CONFIDENCE {
        return atom.DEFAULT_TV
    }
    
    // Induction formula
    sBC := (sA * sAB * sAC + (1.0 - sA) * sC * (1.0 - sAC)) / sB
    
    // Confidence is reduced compared to deduction
    cAB := atom.tv_get_confidence(tv_ab)
    cAC := atom.tv_get_confidence(tv_ac)
    cBC := min(cAB, cAC) * sA  // Scaled by sA since A is the common element
    
    return atom.make_stv(clamp01(sBC), cBC)
}

// Abduction formula: Given P(A→C) and P(B→C), compute P(A→B)
// This is "inference to the best explanation"
tv_abduction :: proc(
    tv_ac: atom.TruthValue,  // P(A→C)
    tv_bc: atom.TruthValue,  // P(B→C)
    tv_a: atom.TruthValue,   // P(A)
    tv_b: atom.TruthValue,   // P(B)
    tv_c: atom.TruthValue,   // P(C)
) -> atom.TruthValue {
    sAC := atom.tv_get_strength(tv_ac)
    sBC := atom.tv_get_strength(tv_bc)
    sA := atom.tv_get_strength(tv_a)
    sB := atom.tv_get_strength(tv_b)
    sC := atom.tv_get_strength(tv_c)
    
    // Avoid division by zero
    if sB <= MIN_CONFIDENCE || sC <= MIN_CONFIDENCE {
        return atom.DEFAULT_TV
    }
    
    // Abduction formula (similar structure to induction)
    sAB := (sC * sAC * sBC + (1.0 - sC) * sB * (1.0 - sBC)) / sB
    
    // Confidence is reduced
    cAC := atom.tv_get_confidence(tv_ac)
    cBC := atom.tv_get_confidence(tv_bc)
    cAB := min(cAC, cBC) * sC
    
    return atom.make_stv(clamp01(sAB), cAB)
}

// Modus Ponens: Given P(A) and P(A→B), compute P(B)
tv_modus_ponens :: proc(
    tv_a: atom.TruthValue,   // P(A)
    tv_ab: atom.TruthValue,  // P(A→B)
) -> atom.TruthValue {
    sA := atom.tv_get_strength(tv_a)
    sAB := atom.tv_get_strength(tv_ab)
    cA := atom.tv_get_confidence(tv_a)
    cAB := atom.tv_get_confidence(tv_ab)
    
    // P(B) = P(A) * P(A→B) + P(NOT A) * P(B|NOT A)
    // Assuming P(B|NOT A) = some background rate, we simplify:
    sB := sA * sAB
    cB := cA * cAB
    
    return atom.make_stv(sB, cB)
}

// =============================================================================
// SIMILARITY AND INHERITANCE FORMULAS
// =============================================================================

// Inheritance to member formula
// P(x ∈ A) given P(A ⊆ B) and P(x ∈ B)
tv_inheritance_to_member :: proc(
    tv_ab: atom.TruthValue,  // P(A ⊆ B) - inheritance
    tv_xb: atom.TruthValue,  // P(x ∈ B) - membership
) -> atom.TruthValue {
    sAB := atom.tv_get_strength(tv_ab)
    sXB := atom.tv_get_strength(tv_xb)
    
    // If x ∈ B and A ⊆ B, then P(x ∈ A) depends on how much of B is A
    sXA := sAB * sXB
    cXA := min(atom.tv_get_confidence(tv_ab), atom.tv_get_confidence(tv_xb))
    
    return atom.make_stv(sXA, cXA)
}

// Member to inheritance formula
// Given multiple membership observations, infer inheritance
tv_member_to_inheritance :: proc(
    positive_examples: int,  // Members of A that are also in B
    total_examples: int,     // Total members of A observed
    k: f64 = K,
) -> atom.TruthValue {
    if total_examples <= 0 {
        return atom.DEFAULT_TV
    }
    
    s := f64(positive_examples) / f64(total_examples)
    c := count_to_conf(f64(total_examples), k)
    
    return atom.make_stv(s, c)
}

// Similarity from inheritance
// P(A ~ B) = P(A→B) * P(B→A) (under independence)
tv_similarity_from_inheritance :: proc(
    tv_ab: atom.TruthValue,  // P(A→B)
    tv_ba: atom.TruthValue,  // P(B→A)
) -> atom.TruthValue {
    sAB := atom.tv_get_strength(tv_ab)
    sBA := atom.tv_get_strength(tv_ba)
    cAB := atom.tv_get_confidence(tv_ab)
    cBA := atom.tv_get_confidence(tv_ba)
    
    // Geometric mean of the two inheritance strengths
    s := math.sqrt(sAB * sBA)
    c := min(cAB, cBA)
    
    return atom.make_stv(s, c)
}

// =============================================================================
// ATTENTION-BASED FORMULAS
// =============================================================================

// Attention-weighted truth value combination
// Weights truth values by the attention of their sources
tv_attention_weighted :: proc(
    tvs: []atom.TruthValue,
    attentions: []f64,  // STI values (should be normalized)
) -> atom.TruthValue {
    if len(tvs) == 0 || len(tvs) != len(attentions) {
        return atom.DEFAULT_TV
    }
    
    total_weight := 0.0
    for a in attentions {
        total_weight += a
    }
    
    if total_weight <= MIN_CONFIDENCE {
        return atom.DEFAULT_TV
    }
    
    weighted_s := 0.0
    min_c := 1.0
    
    for i := 0; i < len(tvs); i += 1 {
        weight := attentions[i] / total_weight
        weighted_s += atom.tv_get_strength(tvs[i]) * weight
        min_c = min(min_c, atom.tv_get_confidence(tvs[i]))
    }
    
    return atom.make_stv(weighted_s, min_c)
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get minimum confidence from multiple truth values
min_confidence :: proc(tvs: ..atom.TruthValue) -> f64 {
    if len(tvs) == 0 {
        return 0.0
    }
    
    min_c := atom.tv_get_confidence(tvs[0])
    for i := 1; i < len(tvs); i += 1 {
        c := atom.tv_get_confidence(tvs[i])
        if c < min_c {
            min_c = c
        }
    }
    return min_c
}

// Check if truth value is "sufficiently confident" for inference
tv_is_confident :: proc(tv: atom.TruthValue, threshold: f64 = 0.5) -> bool {
    return atom.tv_get_confidence(tv) >= threshold
}

// Check if truth value represents "likely true"
tv_is_likely_true :: proc(tv: atom.TruthValue, strength_threshold: f64 = 0.5, conf_threshold: f64 = 0.5) -> bool {
    return atom.tv_get_strength(tv) >= strength_threshold && 
           atom.tv_get_confidence(tv) >= conf_threshold
}

// Check if truth value represents "likely false"
tv_is_likely_false :: proc(tv: atom.TruthValue, strength_threshold: f64 = 0.5, conf_threshold: f64 = 0.5) -> bool {
    return atom.tv_get_strength(tv) < strength_threshold && 
           atom.tv_get_confidence(tv) >= conf_threshold
}

// Compute entropy of a truth value (uncertainty measure)
tv_entropy :: proc(tv: atom.TruthValue) -> f64 {
    s := atom.tv_get_strength(tv)
    
    if s <= MIN_CONFIDENCE || s >= 1.0 - MIN_CONFIDENCE {
        return 0.0
    }
    
    // Binary entropy
    return -s * math.log2(s) - (1.0 - s) * math.log2(1.0 - s)
}

// Compute total uncertainty (combines strength uncertainty and confidence)
tv_uncertainty :: proc(tv: atom.TruthValue) -> f64 {
    c := atom.tv_get_confidence(tv)
    
    // Low confidence = high uncertainty
    conf_uncertainty := 1.0 - c
    
    // Strength near 0.5 = high uncertainty
    s := atom.tv_get_strength(tv)
    strength_uncertainty := 4.0 * s * (1.0 - s)  // Parabola peaking at 0.5
    
    // Combine
    return (conf_uncertainty + c * strength_uncertainty) / 2.0
}
