# OdinCog

**OpenCog Implementation in Pure Odin Language**

OdinCog is a from-scratch implementation of the OpenCog cognitive architecture in the Odin programming language. It provides a high-performance, data-oriented implementation of the core OpenCog components for knowledge representation, reasoning, and learning.

## Features

### Core Foundation (Phase 1) ✅
- **Atom Type System**: Complete hierarchy of OpenCog atom types (ConceptNode, PredicateNode, InheritanceLink, etc.)
- **Atom Data Structures**: Handles, TruthValues, AttentionValues, Nodes, and Links
- **AtomSpace**: Central hypergraph knowledge container with O(1) lookup, type indexing, and incoming set tracking

### Pattern Matching (Phase 2) ✅
- **Variable Binding**: VariableNode and GlobNode support
- **Pattern Matcher**: Backtracking search with constraint propagation
- **Substitution**: Apply bindings to create grounded atoms

### Truth Value System (Phase 3) ✅
- **Truth Value Types**: Simple, Count, and Indefinite truth values
- **PLN Formulas**: Deduction, Induction, Abduction, Revision, AND/OR/NOT

### Unified Rule Engine (Phase 4) ✅
- **Rule Representation**: BindLink-compatible rules with patterns and rewrites
- **Forward Chainer**: Data-driven inference with configurable termination
- **Backward Chainer**: Goal-driven inference with proof tree generation

### ECAN Attention (Phase 6) ✅
- **Attention Values**: STI, LTI, VLTI management
- **Attentional Focus**: Importance-ordered atom access
- **ECAN Agents**: Importance spreading, diffusion, rent collection, forgetting

### Agent Framework (Phase 11) ✅
- **Mind Agents**: Generic agent interface with lifecycle management
- **Scheduler**: Priority-based agent scheduling with thread pool support

### Persistence (Phase 9) ✅
- **Atomese Format**: S-expression serialization compatible with OpenCog
- **JSON Format**: Interoperability format
- **Binary Format**: High-performance serialization

## Project Structure

```
odincog/
├── core/
│   ├── types/          # Atom type system and hierarchy
│   │   └── atom_types.odin
│   ├── atom/           # Atom structures (Handle, TruthValue, Node, Link)
│   │   └── atom.odin
│   ├── atomspace/      # AtomSpace container
│   │   └── atomspace.odin
│   └── pattern/        # Pattern matching engine
│       └── pattern.odin
├── reasoning/
│   ├── pln/            # Probabilistic Logic Networks
│   │   └── formulas.odin
│   └── ure/            # Unified Rule Engine
│       └── ure.odin
├── attention/
│   └── ecan/           # Economic Attention Allocation
│       └── ecan.odin
├── agents/
│   └── framework/      # Agent framework
│       └── agent.odin
├── persist/
│   └── file/           # File persistence
│       └── persist.odin
├── arena/              # Phase II: Game Loop Arena
│   ├── loop/           # Fixed timestep game loop
│   │   └── game_loop.odin
│   ├── memory/         # Arena allocators
│   │   └── arena.odin
│   ├── state/          # World state management
│   │   └── world_state.odin
│   └── sensors/        # Observation system
│       └── sensors.odin
├── active_inference/   # Phase II: Active Inference Engine
│   ├── model/          # Generative model
│   │   └── generative_model.odin
│   ├── inference/      # Free energy minimization
│   │   └── free_energy.odin
│   ├── agent/          # Active inference agent
│   │   └── active_agent.odin
│   └── policy/         # Policy inference
│       └── policy_inference.odin
├── meta/               # Phase II: Self-Reflective Code
│   ├── types/          # Code atom types
│   │   └── code_types.odin
│   ├── reflect/        # Code introspection
│   │   └── code_reflect.odin
│   ├── patterns/       # Meta-patterns
│   │   └── meta_patterns.odin
│   └── rules/          # Meta-rules
│       └── meta_rules.odin
├── niche/              # Phase II: Niche Construction
│   ├── construction/   # Affordances and scaffolds
│   │   └── niche_construction.odin
│   ├── evolution/      # Coevolution dynamics
│   │   └── coevolution.odin
│   └── stigmergy/      # Stigmergic traces
│       └── stigmergy.odin
├── systems/            # Phase II: Integrated Systems
│   ├── cycle/          # Cognitive cycle
│   │   ├── cognitive_cycle.odin
│   │   └── tick.odin
│   └── goals/          # Goal system
│       └── goal_system.odin
└── tests/              # Test suite
    └── tests.odin
```

## Usage

### Creating an AtomSpace

```odin
import "odincog/core/atomspace"
import "odincog/core/atom"
import "odincog/core/types"

main :: proc() {
    // Create AtomSpace
    as := atomspace.atomspace_create("main")
    defer atomspace.atomspace_destroy(as)
    
    // Add nodes
    dog, _ := atomspace.add_node(as, .CONCEPT_NODE, "dog", 
        atom.make_stv(0.9, 0.8))
    animal, _ := atomspace.add_node(as, .CONCEPT_NODE, "animal")
    
    // Add inheritance link
    atomspace.add_link(as, .INHERITANCE_LINK, {dog, animal},
        atom.make_stv(0.95, 0.9))
}
```

### Pattern Matching

```odin
import "odincog/core/pattern"

// Create pattern: (InheritanceLink $X (ConceptNode "animal"))
p := pattern.pattern_create()
defer pattern.pattern_destroy(p)

var_x := pattern.pattern_add_variable(p, "X", .CONCEPT_NODE)
animal_node := pattern.pattern_add_node(p, .CONCEPT_NODE, "animal")
link := pattern.pattern_add_link(p, .INHERITANCE_LINK, {var_x, animal_node})
pattern.pattern_set_root(p, link)

// Find all matches
matches := pattern.pattern_match_all(p, atomspace)
```

### PLN Inference

```odin
import "odincog/reasoning/pln"
import "odincog/reasoning/ure"

// Create rule base with default PLN rules
rb := ure.create_default_rulebase()
defer ure.rulebase_destroy(rb)

// Create forward chainer
fc := ure.fc_create(atomspace, rb)
defer ure.fc_destroy(fc)

// Run inference
results := ure.fc_run(fc)
```

### ECAN Attention

```odin
import "odincog/attention/ecan"

// Create ECAN manager
em := ecan.ecan_create(atomspace)
defer ecan.ecan_destroy(em)

// Run attention cycle
ecan.ecan_run_cycle(em)

// Check what's in focus
focus_atoms := ecan.af_get_atoms(em.focus)
```

### Persistence

```odin
import "odincog/persist/file"

// Save in Atomese format
file.save_atomese(atomspace, "knowledge.scm")

// Load from Atomese file
file.load_atomese(atomspace, "knowledge.scm")

// Save in JSON format
file.save_json(atomspace, "knowledge.json")
```

## Design Philosophy

OdinCog leverages Odin's strengths for a high-performance cognitive architecture:

1. **Data-Oriented Design**: SOA layouts for cache-efficient atom traversal
2. **Explicit Memory Management**: Custom allocators for atom pools
3. **No Hidden Control Flow**: Explicit error handling and control
4. **Compile-Time Safety**: Strong typing with discriminated unions

## Phase II: AIGLA (Active Inference Game Loop Agent) ✅

OdinCog Phase II transforms the cognitive architecture into a self-modifying, active inference-based system where:
- The **entire AtomSpace** is the agent's "world state"
- **Active inference** replaces hand-coded control loops
- A **game loop arena** provides deterministic, tick-based execution
- **Niche construction** allows the agent to modify its own environment

### AIGLA Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ACTIVE INFERENCE GAME LOOP                        │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────┐ │
│  │   OBSERVE   │───▶│   PREDICT    │───▶│    ACT      │───▶│ MUTATE  │ │
│  │  (Sensors)  │    │ (Generative) │    │  (Policy)   │    │ (Arena) │ │
│  └─────────────┘    └──────────────┘    └─────────────┘    └─────────┘ │
│        ▲                                                        │       │
│        └────────────────── WORLD STATE ◀────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

### Phase II Components

#### Arena Architecture (`arena/`)
- **Game Loop** (`loop/game_loop.odin`): Fixed timestep execution with 7 phases
- **Arena Allocator** (`memory/arena.odin`): Zero-cost per-frame allocations
- **World State** (`state/world_state.odin`): Immutable snapshots with transactions
- **Sensors** (`sensors/sensors.odin`): AtomSpace delta and external input sensors

#### Active Inference Engine (`active_inference/`)
- **Generative Model** (`model/generative_model.odin`): Belief states and predictions
- **Free Energy** (`inference/free_energy.odin`): Variational free energy minimization
- **Active Agent** (`agent/active_agent.odin`): Full active inference agent
- **Policy Inference** (`policy/policy_inference.odin`): Policy as inference

#### Self-Reflective Code Atoms (`meta/`)
- **Code Types** (`types/code_types.odin`): PROCEDURE_NODE, MODULE_NODE, etc.
- **Code Mirror** (`reflect/code_reflect.odin`): Parse codebase into AtomSpace
- **Meta-Patterns** (`patterns/meta_patterns.odin`): Patterns over code structure
- **Meta-Rules** (`rules/meta_rules.odin`): Self-modification with sandboxing

#### Niche Construction (`niche/`)
- **Construction** (`construction/niche_construction.odin`): Affordances and scaffolds
- **Coevolution** (`evolution/coevolution.odin`): Fitness landscapes and stability
- **Stigmergy** (`stigmergy/stigmergy.odin`): Pheromone-like attention traces

#### Integrated Systems (`systems/`)
- **Cognitive Cycle** (`cycle/cognitive_cycle.odin`): Unified integration
- **Tick Function** (`cycle/tick.odin`): Observe→Predict→Infer→Act→Learn→Attend→Construct
- **Goal System** (`goals/goal_system.odin`): Goals as preferred observations

### Cognitive Tick

```odin
cognitive_tick :: proc(cycle: ^CognitiveCycle) {
    // 1. OBSERVE - Gather sensory input
    observe(cycle)
    
    // 2. PREDICT - Generate predictions from model
    predict(cycle)
    
    // 3. INFER - Update beliefs (minimize free energy)
    infer(cycle)
    
    // 4. ACT - Select and execute policy
    act(cycle)
    
    // 5. LEARN - Update model parameters
    learn(cycle)
    
    // 6. ATTEND - ECAN cycle
    attend(cycle)
    
    // 7. CONSTRUCT - Niche construction
    construct(cycle)
}
```

### Design Principles

1. **Everything is an Atom** — Code, data, beliefs, preferences, policies all live in AtomSpace
2. **Active Inference** — Principled free energy minimization replaces ad-hoc control
3. **Game Loop Determinism** — Fixed timestep enables reproducible behavior
4. **Arena Allocation** — Predictable memory patterns with zero per-tick cost
5. **Niche Construction** — Agent shapes environment, which shapes agent

## Comparison with OpenCog C++

| Feature | OpenCog C++ | OdinCog |
|---------|-------------|---------|
| AtomSpace | ✅ | ✅ |
| Pattern Matching | ✅ | ✅ |
| PLN | ✅ | ✅ (Core formulas) |
| URE | ✅ | ✅ |
| ECAN | ✅ | ✅ |
| Active Inference | ❌ | ✅ |
| Game Loop Arena | ❌ | ✅ |
| Code Self-Reflection | ❌ | ✅ |
| Niche Construction | ❌ | ✅ |
| MOSES | ✅ | 🔜 Planned |
| NLP Pipeline | ✅ | 🔜 Planned |
| Distributed | ✅ | 🔜 Planned |

## Running Tests

```bash
cd odincog
odin test tests
```

## License

This implementation follows the same open-source principles as OpenCog.

## References

- [OpenCog Wiki](https://wiki.opencog.org/)
- [AtomSpace Documentation](https://wiki.opencog.org/w/AtomSpace)
- [PLN Book](https://wiki.opencog.org/w/PLN_Book)
- [Odin Language](https://odin-lang.org/)
