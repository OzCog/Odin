// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Meta-Rules (Self-Modification)
//
// This module implements self-modification capabilities through meta-rules.
// Meta-rules can:
// - Generate new rules from patterns
// - Adapt rule weights based on utility
// - Synthesize procedures from examples
// - Safely sandbox mutations

package odincog_meta_rules

import "core:mem"
import "core:time"
import "core:strings"
import "core:fmt"
import "../types"
import "../patterns"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/pattern"
import coreTypes "../../core/types"
import "../../reasoning/ure"

// =============================================================================
// META-RULE TYPES
// =============================================================================

// MetaRuleType indicates what kind of meta-level operation
MetaRuleType :: enum {
    // Rule generation
    GENERATE_RULE,              // Create new rule from pattern
    COMPOSE_RULES,              // Combine existing rules
    SPECIALIZE_RULE,            // Create more specific version
    GENERALIZE_RULE,            // Create more general version
    
    // Rule modification
    ADAPT_WEIGHT,               // Modify rule weight
    ENABLE_RULE,                // Enable a disabled rule
    DISABLE_RULE,               // Disable a rule
    
    // Procedure synthesis
    SYNTHESIZE_PROCEDURE,       // Create procedure from examples
    REFACTOR_PROCEDURE,         // Refactor existing procedure
    
    // Knowledge modification
    ADD_KNOWLEDGE,              // Add new knowledge atoms
    REVISE_KNOWLEDGE,           // Revise existing beliefs
    FORGET_KNOWLEDGE,           // Remove low-utility knowledge
}

// MetaRule represents a rule that operates on rules/code
MetaRule :: struct {
    name:               string,
    type:               MetaRuleType,
    
    // Input pattern (what to match)
    input_pattern:      ^patterns.MetaPattern,
    
    // Transformation
    transformation:     ^MetaTransform,
    
    // Constraints
    constraints:        MetaRuleConstraints,
    
    // Execution state
    enabled:            bool,
    sandbox_mode:       bool,  // If true, don't actually apply
    
    // Statistics
    applications:       int,
    successes:          int,
    last_applied:       time.Time,
    avg_utility:        f64,
    
    allocator:          mem.Allocator,
}

// MetaTransform defines how to transform matched elements
MetaTransform :: struct {
    // For rule generation
    rule_template:      RuleTemplate,
    
    // For weight adaptation
    weight_adjustment:  WeightAdjustment,
    
    // For procedure synthesis
    synthesis_config:   SynthesisConfig,
    
    // Custom transformation function
    custom_transform:   proc(^MetaRule, []patterns.MetaPatternMatch, ^atomspace.AtomSpace) -> MetaRuleResult,
}

// RuleTemplate for generating new rules
RuleTemplate :: struct {
    name_template:      string,
    category:           ure.RuleCategory,
    base_weight:        f64,
    base_cost:          f64,
    tv_formula:         ure.TruthValueFormula,
}

// WeightAdjustment specifies how to modify rule weights
WeightAdjustment :: struct {
    method:             WeightAdjustmentMethod,
    delta:              f64,
    min_weight:         f64,
    max_weight:         f64,
}

WeightAdjustmentMethod :: enum {
    ADDITIVE,           // weight += delta
    MULTIPLICATIVE,     // weight *= delta
    DECAY,              // weight *= decay_factor
    REINFORCE,          // weight += success_rate * delta
}

// SynthesisConfig for procedure synthesis
SynthesisConfig :: struct {
    min_examples:       int,
    max_complexity:     int,
    allow_recursion:    bool,
    allowed_calls:      []string,
}

// MetaRuleConstraints limit when meta-rules can apply
MetaRuleConstraints :: struct {
    // Frequency limits
    min_interval:       time.Duration,
    max_applications:   int,
    
    // Scope limits
    allowed_modules:    []string,
    forbidden_modules:  []string,
    
    // Safety limits
    max_rules_created:  int,
    max_atoms_modified: int,
    require_approval:   bool,
}

// MetaRuleResult holds the result of applying a meta-rule
MetaRuleResult :: struct {
    success:            bool,
    
    // Created entities
    created_rules:      [dynamic]^ure.Rule,
    created_atoms:      [dynamic]atom.Handle,
    
    // Modified entities
    modified_rules:     [dynamic]^ure.Rule,
    modified_atoms:     [dynamic]atom.Handle,
    
    // Messages
    messages:           [dynamic]string,
    
    // Metrics
    utility_estimate:   f64,
}

// =============================================================================
// META-RULE LIFECYCLE
// =============================================================================

// Create a meta-rule
meta_rule_create :: proc(
    name: string,
    type: MetaRuleType,
    allocator := context.allocator,
) -> ^MetaRule {
    mr := new(MetaRule, allocator)
    mr.name = strings.clone(name, allocator)
    mr.type = type
    mr.enabled = true
    mr.sandbox_mode = false  // Default to actual application
    mr.transformation = new(MetaTransform, allocator)
    mr.allocator = allocator
    
    // Default constraints
    mr.constraints = MetaRuleConstraints{
        min_interval = time.Second,
        max_applications = 100,
        max_rules_created = 10,
        max_atoms_modified = 100,
    }
    
    return mr
}

// Destroy a meta-rule
meta_rule_destroy :: proc(mr: ^MetaRule) {
    if mr == nil {
        return
    }
    
    if mr.input_pattern != nil {
        patterns.meta_pattern_destroy(mr.input_pattern)
    }
    
    free(mr.transformation, mr.allocator)
    delete(mr.name, mr.allocator)
    free(mr, mr.allocator)
}

// Set input pattern
meta_rule_set_pattern :: proc(mr: ^MetaRule, mp: ^patterns.MetaPattern) {
    mr.input_pattern = mp
}

// Set rule template
meta_rule_set_template :: proc(mr: ^MetaRule, template: RuleTemplate) {
    mr.transformation.rule_template = template
}

// Set weight adjustment
meta_rule_set_weight_adjustment :: proc(mr: ^MetaRule, adj: WeightAdjustment) {
    mr.transformation.weight_adjustment = adj
}

// Set custom transformation
meta_rule_set_transform :: proc(
    mr: ^MetaRule,
    transform: proc(^MetaRule, []patterns.MetaPatternMatch, ^atomspace.AtomSpace) -> MetaRuleResult,
) {
    mr.transformation.custom_transform = transform
}

// Enable sandbox mode
meta_rule_set_sandbox :: proc(mr: ^MetaRule, sandbox: bool) {
    mr.sandbox_mode = sandbox
}

// =============================================================================
// META-RULE APPLICATION
// =============================================================================

// Apply a meta-rule to the AtomSpace
meta_rule_apply :: proc(
    mr: ^MetaRule,
    as: ^atomspace.AtomSpace,
    rb: ^ure.RuleBase,
) -> MetaRuleResult {
    result := MetaRuleResult{
        success = false,
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    // Check if enabled
    if !mr.enabled {
        append(&result.messages, "Meta-rule is disabled")
        return result
    }
    
    // Check constraints
    if !check_constraints(mr) {
        append(&result.messages, "Constraints not satisfied")
        return result
    }
    
    // Find matches
    var matches: []patterns.MetaPatternMatch
    if mr.input_pattern != nil {
        matches = patterns.meta_pattern_match_all(mr.input_pattern, as)
    }
    
    // Apply transformation
    if mr.transformation.custom_transform != nil {
        result = mr.transformation.custom_transform(mr, matches, as)
    } else {
        result = apply_default_transform(mr, matches, as, rb)
    }
    
    // Update statistics
    mr.applications += 1
    if result.success {
        mr.successes += 1
    }
    mr.last_applied = time.now()
    
    // Update average utility
    n := f64(mr.applications)
    mr.avg_utility = ((n - 1) * mr.avg_utility + result.utility_estimate) / n
    
    return result
}

// Check if constraints allow application
check_constraints :: proc(mr: ^MetaRule) -> bool {
    c := &mr.constraints
    
    // Check interval
    if mr.applications > 0 {
        elapsed := time.diff(mr.last_applied, time.now())
        if elapsed < c.min_interval {
            return false
        }
    }
    
    // Check max applications
    if mr.applications >= c.max_applications {
        return false
    }
    
    return true
}

// Apply default transformation based on meta-rule type
apply_default_transform :: proc(
    mr: ^MetaRule,
    matches: []patterns.MetaPatternMatch,
    as: ^atomspace.AtomSpace,
    rb: ^ure.RuleBase,
) -> MetaRuleResult {
    result := MetaRuleResult{
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    if mr.sandbox_mode {
        append(&result.messages, "Running in sandbox mode - no actual changes")
    }
    
    #partial switch mr.type {
        case .GENERATE_RULE:
            result = apply_generate_rule(mr, matches, as, rb)
            
        case .ADAPT_WEIGHT:
            result = apply_adapt_weight(mr, matches, rb)
            
        case .DISABLE_RULE:
            result = apply_disable_rule(mr, matches, rb)
            
        case .ADD_KNOWLEDGE:
            result = apply_add_knowledge(mr, matches, as)
            
        case:
            append(&result.messages, "Transformation type not implemented")
    }
    
    return result
}

// =============================================================================
// TRANSFORMATION IMPLEMENTATIONS
// =============================================================================

// Generate new rules from patterns
apply_generate_rule :: proc(
    mr: ^MetaRule,
    matches: []patterns.MetaPatternMatch,
    as: ^atomspace.AtomSpace,
    rb: ^ure.RuleBase,
) -> MetaRuleResult {
    result := MetaRuleResult{
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    template := mr.transformation.rule_template
    
    for i, match in matches {
        if i >= mr.constraints.max_rules_created {
            break
        }
        
        // Get atom name for rule naming
        atom_obj, ok := atomspace.atomspace_get(as, match.handle)
        if !ok {
            continue
        }
        
        name := atom.atom_get_name(atom_obj)
        if len(name) == 0 {
            name = fmt.tprintf("rule_%d", i)
        }
        
        // Generate rule name
        rule_name := strings.replace(template.name_template, "{name}", name, -1, mr.allocator)
        
        // Create rule
        if !mr.sandbox_mode {
            rule := ure.rule_create(rule_name, mr.allocator)
            rule.category = template.category
            rule.weight = template.base_weight
            rule.cost = template.base_cost
            rule.tv_formula = template.tv_formula
            
            // Add to rule base
            ure.rulebase_add_rule(rb, rule)
            
            append(&result.created_rules, rule)
        }
        
        append(&result.messages, fmt.aprintf("Created rule: %s", rule_name, allocator = mr.allocator))
    }
    
    result.success = len(result.created_rules) > 0 || mr.sandbox_mode
    result.utility_estimate = f64(len(matches)) * 0.1  // Simple utility estimate
    
    return result
}

// Adapt rule weights based on utility
apply_adapt_weight :: proc(
    mr: ^MetaRule,
    matches: []patterns.MetaPatternMatch,
    rb: ^ure.RuleBase,
) -> MetaRuleResult {
    result := MetaRuleResult{
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    adj := mr.transformation.weight_adjustment
    rules := ure.rulebase_get_rules(rb)
    
    for rule in rules {
        // Check if rule matches criteria (by name pattern)
        should_adjust := true  // In a real implementation, check matches
        
        if should_adjust {
            old_weight := rule.weight
            new_weight := old_weight
            
            #partial switch adj.method {
                case .ADDITIVE:
                    new_weight = old_weight + adj.delta
                case .MULTIPLICATIVE:
                    new_weight = old_weight * adj.delta
                case .DECAY:
                    new_weight = old_weight * (1.0 - adj.delta)
                case .REINFORCE:
                    // Would use success rate here
                    new_weight = old_weight + 0.5 * adj.delta
            }
            
            // Clamp
            new_weight = clamp(new_weight, adj.min_weight, adj.max_weight)
            
            if !mr.sandbox_mode {
                rule.weight = new_weight
            }
            
            append(&result.modified_rules, rule)
            append(&result.messages, fmt.aprintf("Adjusted %s: %.3f -> %.3f", 
                rule.name, old_weight, new_weight, allocator = mr.allocator))
        }
    }
    
    result.success = len(result.modified_rules) > 0 || mr.sandbox_mode
    result.utility_estimate = f64(len(result.modified_rules)) * 0.05
    
    return result
}

// Disable rules matching pattern
apply_disable_rule :: proc(
    mr: ^MetaRule,
    matches: []patterns.MetaPatternMatch,
    rb: ^ure.RuleBase,
) -> MetaRuleResult {
    result := MetaRuleResult{
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    // In a real implementation, we'd mark rules as disabled
    append(&result.messages, "Rule disabling not yet implemented")
    
    result.success = false
    return result
}

// Add knowledge atoms based on patterns
apply_add_knowledge :: proc(
    mr: ^MetaRule,
    matches: []patterns.MetaPatternMatch,
    as: ^atomspace.AtomSpace,
) -> MetaRuleResult {
    result := MetaRuleResult{
        created_rules = make([dynamic]^ure.Rule, mr.allocator),
        created_atoms = make([dynamic]atom.Handle, mr.allocator),
        modified_rules = make([dynamic]^ure.Rule, mr.allocator),
        modified_atoms = make([dynamic]atom.Handle, mr.allocator),
        messages = make([dynamic]string, mr.allocator),
    }
    
    for match in matches {
        if len(result.created_atoms) >= mr.constraints.max_atoms_modified {
            break
        }
        
        // Create meta-knowledge atom about the match
        if !mr.sandbox_mode {
            meta_h, _ := atomspace.add_node(
                as,
                coreTypes.AtomType.CONCEPT_NODE,
                fmt.tprintf("meta_%d", match.handle.idx),
            )
            
            // Link to original
            atomspace.add_link(
                as,
                coreTypes.AtomType.EVALUATION_LINK,
                []atom.Handle{meta_h, match.handle},
            )
            
            append(&result.created_atoms, meta_h)
        }
        
        append(&result.messages, fmt.aprintf("Added meta-knowledge for handle %d", 
            match.handle.idx, allocator = mr.allocator))
    }
    
    result.success = len(result.created_atoms) > 0 || mr.sandbox_mode
    result.utility_estimate = f64(len(result.created_atoms)) * 0.02
    
    return result
}

// =============================================================================
// META-RULE MANAGER
// =============================================================================

// MetaRuleManager coordinates meta-rule application
MetaRuleManager :: struct {
    rules:              [dynamic]^MetaRule,
    
    // Configuration
    auto_apply:         bool,
    apply_interval:     time.Duration,
    
    // State
    last_apply:         time.Time,
    total_applications: int,
    
    // History
    history:            [dynamic]MetaRuleApplication,
    max_history:        int,
    
    allocator:          mem.Allocator,
}

// MetaRuleApplication records a meta-rule application
MetaRuleApplication :: struct {
    rule_name:          string,
    timestamp:          time.Time,
    success:            bool,
    changes:            int,
    utility:            f64,
}

// Create meta-rule manager
meta_rule_manager_create :: proc(allocator := context.allocator) -> ^MetaRuleManager {
    mrm := new(MetaRuleManager, allocator)
    mrm.rules = make([dynamic]^MetaRule, allocator)
    mrm.history = make([dynamic]MetaRuleApplication, allocator)
    mrm.apply_interval = time.Second * 10
    mrm.max_history = 1000
    mrm.allocator = allocator
    return mrm
}

// Destroy meta-rule manager
meta_rule_manager_destroy :: proc(mrm: ^MetaRuleManager) {
    if mrm == nil {
        return
    }
    
    for mr in mrm.rules {
        meta_rule_destroy(mr)
    }
    delete(mrm.rules)
    delete(mrm.history)
    free(mrm, mrm.allocator)
}

// Register a meta-rule
meta_rule_manager_register :: proc(mrm: ^MetaRuleManager, mr: ^MetaRule) {
    append(&mrm.rules, mr)
}

// Apply all enabled meta-rules
meta_rule_manager_apply_all :: proc(
    mrm: ^MetaRuleManager,
    as: ^atomspace.AtomSpace,
    rb: ^ure.RuleBase,
) {
    // Check interval
    if time.diff(mrm.last_apply, time.now()) < mrm.apply_interval {
        return
    }
    
    mrm.last_apply = time.now()
    
    for mr in mrm.rules {
        if !mr.enabled {
            continue
        }
        
        result := meta_rule_apply(mr, as, rb)
        
        // Record application
        record := MetaRuleApplication{
            rule_name = mr.name,
            timestamp = time.now(),
            success = result.success,
            changes = len(result.created_atoms) + len(result.modified_atoms) + 
                     len(result.created_rules) + len(result.modified_rules),
            utility = result.utility_estimate,
        }
        append(&mrm.history, record)
        mrm.total_applications += 1
        
        // Prune history
        if len(mrm.history) > mrm.max_history {
            remove_range(&mrm.history, 0, len(mrm.history) - mrm.max_history)
        }
    }
}

// Get statistics
MetaRuleManagerStats :: struct {
    total_rules:        int,
    enabled_rules:      int,
    total_applications: int,
    successful_apps:    int,
    avg_utility:        f64,
}

meta_rule_manager_stats :: proc(mrm: ^MetaRuleManager) -> MetaRuleManagerStats {
    stats := MetaRuleManagerStats{
        total_rules = len(mrm.rules),
        total_applications = mrm.total_applications,
    }
    
    for mr in mrm.rules {
        if mr.enabled {
            stats.enabled_rules += 1
        }
    }
    
    total_utility: f64 = 0
    for record in mrm.history {
        if record.success {
            stats.successful_apps += 1
        }
        total_utility += record.utility
    }
    
    if len(mrm.history) > 0 {
        stats.avg_utility = total_utility / f64(len(mrm.history))
    }
    
    return stats
}

// =============================================================================
// PREDEFINED META-RULES
// =============================================================================

// Create meta-rule that boosts frequently successful rules
create_success_booster :: proc(allocator := context.allocator) -> ^MetaRule {
    mr := meta_rule_create("success_booster", .ADAPT_WEIGHT, allocator)
    
    mr.transformation.weight_adjustment = WeightAdjustment{
        method = .REINFORCE,
        delta = 0.05,
        min_weight = 0.1,
        max_weight = 5.0,
    }
    
    mr.constraints.min_interval = time.Minute
    
    return mr
}

// Create meta-rule that decays unused rules
create_decay_rule :: proc(allocator := context.allocator) -> ^MetaRule {
    mr := meta_rule_create("unused_decay", .ADAPT_WEIGHT, allocator)
    
    mr.transformation.weight_adjustment = WeightAdjustment{
        method = .DECAY,
        delta = 0.01,
        min_weight = 0.01,
        max_weight = 10.0,
    }
    
    mr.constraints.min_interval = time.Minute * 5
    
    return mr
}

// Create meta-rule that generates rules from patterns
create_pattern_generator :: proc(allocator := context.allocator) -> ^MetaRule {
    mr := meta_rule_create("pattern_generator", .GENERATE_RULE, allocator)
    
    mr.transformation.rule_template = RuleTemplate{
        name_template = "generated_{name}",
        category = .CUSTOM,
        base_weight = 0.5,
        base_cost = 1.0,
        tv_formula = .IDENTITY,
    }
    
    mr.constraints.max_rules_created = 5
    mr.constraints.min_interval = time.Minute * 10
    
    return mr
}
