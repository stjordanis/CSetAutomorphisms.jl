using Catlab.Theories: adom, attr, attrtype, attr, adom, acodom
using Catlab.Present
using Catlab.CategoricalAlgebra.CSetDataStructures: struct_acset


const VPSI = Vector{Pair{Symbol, Int}}

"""
To compute automorphisms of Attributed CSets, we create a pseudo CSet which has
additional components for each data type.

This is inefficient for attributes which have a total order on them
(e.g. integers/strings) since we solve for a canonical permutation of the
attributes. Future work could address this by initializing the coloring with
the 'correct' canonical order.
"""
function pseudo_cset(g::StructACSet{S}
                    )::Tuple{StructACSet, Dict{Symbol,Vector{Any}}} where {S}
  tabs, arrs = collect(ob(S)), collect(hom(S))
  src, tgt = dom(S), codom(S)
  dtabs, darrs = collect(attrtype(S)), collect(attr(S))
  dsrc, dtgt = adom(S), acodom(S)

  # Create copy of schema (+ an extra component for each datatype)
  pres = Presentation(FreeSchema)
  xobs = [Ob(FreeSchema,t) for t in vcat(tabs,dtabs)]
  xobsdic = Dict([t=>Ob(FreeSchema,t) for t in vcat(tabs,dtabs)])
  n = length(tabs)
  for x in xobs add_generator!(pres, x) end

  for (arr, s, t) in zip(map(collect, [arrs, src, tgt])...)
    add_generator!(pres, Hom(arr, xobsdic[s], xobsdic[t]))
  end

  # Add an arrow for each attr and store all possible Data values
  attrvals = Dict([t=>Set() for t in dtabs])
  for (arr, s, t) in zip(darrs, dsrc, dtgt)
    add_generator!(pres, Hom(arr, xobsdic[s], xobsdic[t]))
    union!(attrvals[t], Set(g[arr]))
  end

  # Use Julia ordering to give each value an index
  attrvals = Dict([k=>sort(collect(x)) for (k,x) in collect(attrvals)])

  # Create and populate pseudo-cset
  name = Symbol("Pseudo_$(typeof(g).name.name)")
  expr = struct_acset(name, StructACSet, pres, index=vcat(arrs,darrs))
  eval(expr)
  csettype = eval(name)
  res = Base.invokelatest(eval(name))

  # Copy the original non-attr data
  for t in tabs
    add_parts!(res, t, nparts(g,t))
  end
  for a in arrs
    set_subpart!(res, a, g[a])
  end

  # initialize pseudo data components
  for t in dtabs
    add_parts!(res, t, length(attrvals[t]))
  end

  # Replace data value with an index for each attribute
  for (a,t) in zip(darrs, dtgt)
    fks = [findfirst(==(v), attrvals[t]) for v in g[a]]
    set_subpart!(res, a, fks)
  end

  return res, attrvals
end

pluspair(x::Pair{Int, Int}, y::Pair{Int,Int})::Pair{Int,Int} = x[1]+y[1] => x[2]+y[2]

"""
Heuristic for total ordering of objects of a CSet. We want things that will
be easily distinguished to be first. Things are very easily distinguished by
in-arrows, and somewhat distinguished by out arrows. So each object gets a
score based on this criteria. We then iterate until convergence.

We use this total ordering to order arrows by their target's score.

As an example, consider the triangle:
     f
  A --> B
  g ↘  ↙ h
     C
The stable order of the objects is:
  [A (low, high), B (mid mid), C (high, low)]
This induces an order on the arrows:
  [f (low+mid, high+mid), g (low+high, high+low), h (mid+high, mid+low)]

TO DO test this heuristic vs random heuristics to see that it's actually
effective.
"""
function order_syms(::StructACSet{S})::Vector{Symbol} where {S}
  os, arrs, srcs, tgts = ob(S), hom(S), dom(S), codom(S)
  function score_obj(obj::Symbol, scores::Dict{Symbol, Pair{Int,Int}})::Pair{Int,Int}
    arr_in = sum([scores[s][1] for (s, t) in zip(srcs, tgts) if t == obj])
    arr_ot = sum([scores[t][2] for (s, t) in zip(srcs, tgts) if s == obj])
    return arr_in => arr_ot
  end
  getorder(scores)::Vector{Symbol} = map(last, sort([(b,a) for (a,b)
                                                     in collect(scores)]))
  scores = Dict(zip(os, [(1=>1) for _ in os]))
  oldorder = []
  neworder = getorder(scores)
  while oldorder != neworder
    oldorder = neworder
    scores = Dict([o=> pluspair(scores[o],score_obj(o, scores)) for o in os])
    neworder = getorder(scores)
  end
  ordarrs = [(h, pluspair(scores[s], scores[t]))
             for (h, s, t) in zip(arrs, srcs, tgts)]
  return reverse(getorder(ordarrs))
end

"""
Inverse of pseudo_cset. Requires mapping (generated by `pseudo_cset`) of indices
for each Data to the actual data values.
"""
function pseudo_cset_inv(g::StructACSet,
                         orig::StructACSet{S},
                         attrvals::Dict{Symbol,Vector{Any}}
                        )::StructACSet{S} where {S}
  orig = deepcopy(orig)
  arrs = hom(S)
  darrs, dtabs = attr(S), acodom(S)
  for arr in arrs
    set_subpart!(orig, arr, g[arr])
  end
  for (darr,tgt) in zip(darrs, dtabs)
    set_subpart!(orig, darr, attrvals[tgt][g[darr]])
  end
  return orig
end


"""Lexicographic minimum of all automorphisms"""
function canonical_iso(g::StructCSet{S})::StructCSet{S} where {S}
  os = order_syms(g)
  opt = sort(collect(autos(g)[1]), by=(γ->order_perms(g, γ, os)))
  ord(x) = [x[s] for s in os]
  applied = [apply_automorphism(g, Dict(a)) for a in autos(g)[1]]
  for a in applied
    is_isomorphic(a, g) || error("BAD AUTO FOUND")
  end
  isos = sort(applied, by=ord)
  return isempty(isos) ? g : isos[1]
end

function isos(g::StructACSet{S})::Vector{StructACSet{S}} where {S}
  p, avals = pseudo_cset(g)
  return [pseudo_cset_inv(apply_automorphism(p, Dict(a)), g, avals)
               for a in autos(p)[1]]
end

"""
Compute automorphisms for the pseudo-cset, but then substitute in
the actual attribute values before evaluating the lexicographic order
"""
function canonical_iso(g::StructACSet{S}; pres::Union{Nothing,Presentation}
                      )::StructACSet{S} where {S}
  if !isnothing(pres) return canonical_iso_nauty(g, pres) end
  os = order_syms(g)
  ord(x) = vcat([x[a] for a in attr(S)],[x[s] for s in os])

  is = isos(g)
  !isempty(is) || error("Empty isos?")
  return sort(is, by=ord)[1]
end

"""Hash of canonical isomorphism."""
function canonical_hash(g::StructACSet;
                        pres::Union{Nothing,Presentation}=nothing)::UInt64
  hash(string(canonical_iso(g; pres=pres)))
end

"""Find index at which two vectors diverge (used in `search_tree`)"""
function common(v1::Vector{T}, v2::Vector{T})::Int where {T}
  for (i, (x, y)) in enumerate(zip(v1, v2))
    if x != y
      return i-1
    end
  end
  return min(length(v1), length(v2))
end

"""Search tree explored by Nauty"""
mutable struct Tree
  coloring::CDict
  saturated::CDict
  indicator::UInt64
  children::Dict{Pair{Symbol, Int}, Tree}
  function Tree()
    return new(CDict(),CDict(),UInt64(0),
               Dict{Pair{Symbol, Int},Tree}())
  end
end

"""
Keep track of what happens during the automorphism search. Possible actions:
- start_iter: val is a search tree + a location in the search tree
- add_leaf
- auto_prune
- order_prune
- orbit_prune
- flag_skip
- new_child
"""
mutable struct History
  action::String
  val::Any
end

"""
Container for the optimal automorphism seen so far
Store values of indicator function for each node in search tree
en route to the leaf node
"""
mutable struct Indicator
  val::Union{Nothing,Vector{UInt64}}
  function Indicator()
    return new(nothing)
  end
end

hpush!(hist::Vector{History}, act::String, val::Any) = (isempty(hist) ?
  nothing : push!(hist, History(act, val)))

function Base.size(t::Tree)::Int
  return 1 + (isempty(t.children) ? 0 : sum(map(Base.size, values(t.children))))
end

"""Get a node via a sequence of edges from the root"""
function Base.getindex(t::Tree, pth::VPSI)::Tree
  ptr = t
  for p in pth
    ptr = ptr.children[p]
  end
  return ptr
end

function get_indicators(t::Tree, pth::VPSI)::Vector{UInt64}
  ptr, inds = t, UInt64[]
  for p in pth
    ptr = ptr.children[p]
    push!(inds, ptr.indicator)
  end
  return inds
end


"""Automorphism based pruning when we've found a new leaf node (τ @ t)"""
function compute_auto_prune(tree::Tree, t::VPSI, τ::CDict, leafnodes::Set{VPSI})::Set{VPSI}
  skip = Set{VPSI}()
  for p in filter(!=(t), leafnodes)
    π = tree[p].saturated
    i = common(p, t)
    a, b, c = abc = p[1:i], p[1:i+1], t[1:i+1] # == t[1:i]
    a_, b_, c_ = [tree[x].saturated for x in abc]
    γ = compose_perms(π, invert_perms(τ))
    if (compose_perms(γ, a_) == a_ &&
        compose_perms(γ, b_) == c_)
      # skip everything from c to a
      for i in length(c):length(t)
        push!(skip, t[1:i])
      end
      break
    end
  end
  return filter(!=(t), skip) # has something gone wrong if we need to do this?
end


"""To reduce branching factor, split on the SMALLEST nontrivial partition"""
function split_data(coloring::CDict)::Tuple{Symbol, Int, Vector{Int}}
  colors_by_size = sort(get_colors_by_size(coloring), rev=false)
  if isempty(colors_by_size)
    return :_nothing, 0, []
  end
  split_tab, split_color = colors_by_size[1][2]
  colors = coloring[split_tab]
  split_inds = findall(==(split_color), colors)
  return split_tab, split_color, split_inds
end

"""
DFS tree of colorings, with edges being choices in how to break symmetry
Goal is to acquire all leaf nodes.

Algorithm from "McKay’s Canonical Graph Labeling Algorithm" by Hartke and
Radcliffe (2009).

McKay's "Practical Graph Isomorphism" (Section 2.29: "storage of identity
nodes") warns that it's not a good idea to check for every possible automorphism
pruning (for memory and time concerns). To do: look into doing this in a more
balanced way. Profiling code will probably reveal that checking for automorphism
pruning is a bottleneck.

Inputs:
 - g: our structure that we are computing automorphisms for
 - res: all automorphisms found so far
 - split_seq: sequence of edges (our current location in the tree)
 - tree: all information known so far - this gets modified
 - leafnodes: coordinates of all automorphisms found so far
 - perm_worsts: data used for order pruning
 - skip: flagged coordinates which have been pruned
 - history: log all the transformations made to a data structure for analysis
 - auto_prune:  whether or not to use automorphisms to prune
 - orbit_prune: whether or not to use orbit information to prune
 - order_prune: whether or not to use "indicator functions" to prune
"""
function search_tree!(g::StructACSet{S},
                      init_coloring::CDict,
                      split_seq::VPSI,
                      tree::Tree,
                      leafnodes::Set{VPSI},
                      indicator::Indicator,
                      skip::Set{VPSI};
                      history::Vector{History}=History[],
                      auto_prune::Bool=true,
                      orbit_prune::Bool=true,
                      order_prune::Bool=false,
                     )::Nothing where {S}
  # Perform color saturation
  color_seq, new_ind = color_saturate(g; init_color=init_coloring, history=!isempty(history))
  curr_tree = tree[split_seq]
  curr_tree.coloring = init_coloring
  curr_tree.indicator = new_ind
  curr_tree.saturated = coloring = color_seq[end]
  curr_inds = get_indicators(tree, split_seq)
  ci_len = length(curr_inds)

  if order_prune && !isnothing(indicator.val) && (
      curr_inds < let v=indicator.val; v[1:min(length(v), ci_len)] end)
    hpush!(history, "order_prune", (curr_inds, indicator.val))
    return nothing
  end

  split_tab, split_color, split_inds = sd = split_data(coloring)
  hpush!(history, "start_iter", (split_seq, color_seq, new_ind, sd))

  # Check if we are now at a leaf node
  if isempty(split_inds)
    # Add result to list of results
    push!(leafnodes, split_seq)
    invert_perms(coloring) # fail if not a perm
    #hpush!(history, "add_leaf", split_seq)

    if isnothing(indicator.val) || indicator.val < curr_inds
      indicator.val = curr_inds
    end

    # Prune with automorphisms
    if auto_prune
      pruned = compute_auto_prune(tree, split_seq, coloring, leafnodes)
      if !isempty(pruned)
        hpush!(history, "auto_prune", pruned)
        union!(skip, pruned)
      end
    end

    return nothing
  end
  # Branch on this leaf
  for split_ind in split_inds
    if split_ind != split_inds[1]
      hpush!(history, "return", split_seq)
    end

    if split_seq ∈ skip
      hpush!(history, "flag_skip", split_ind)
    elseif  orbit_prune && orbit_check(curr_tree, split_tab, split_color)
      hpush!(history, "orbit_prune", nothing)
    else
      # Construct arguments for recursive call to child
      new_coloring = deepcopy(coloring)
      new_seq = vcat(split_seq, [split_tab => split_ind])
      new_coloring[split_tab][split_ind] = maximum(coloring[split_tab]) + 1
      curr_tree.children[split_tab => split_ind] = Tree()
      search_tree!(g, new_coloring, new_seq, tree, leafnodes, indicator, skip;
                   auto_prune=auto_prune, orbit_prune=orbit_prune,
                   order_prune=order_prune, history=history)
    end
  end

  return nothing
end

"""
Get coordinates of all nodes in a tree that have no children
"""
function get_leaves(t::Tree)::Vector{VPSI}
  if isempty(t.children)
    return [Pair{Symbol,Int}[]]
  else
    res = []
    for (kv, c) in t.children
      for pth in get_leaves(c)
        push!(res, vcat([kv],pth))
      end
    end
    return res
  end
end

"""
Look at all automorphisms between leaf nodes. If they generate a group with
just one orbit in the specific part where the current tree got differentiated,
we need not explore further (returns true)
"""
function orbit_check(t::Tree, pₛ::Symbol, pᵢ::Int; verbose::Bool=false)::Bool
  leaves, auts = filter(l->is_perms(t[l].saturated),get_leaves(t)), Perm[]
  for i in 1:length(leaves)
    icolor = t[leaves[i]].saturated[pₛ]
    for j in i+1:length(leaves)
      jcolor = t[leaves[j]].saturated[pₛ]
      push!(auts,Perm(compose_comp(icolor, Base.invperm(jcolor))))
    end
  end
  all_i = findall(==(pᵢ), t.saturated[pₛ])
  length(all_i) > 1 || error("branched on nontrivial color")
  o = Orbit(auts, all_i[1])
  if verbose
    println("pₛpᵢ=$pₛ$pᵢ all_i=$all_i \nauts=$auts\norb=$(collect(o))") end
  return isempty(setdiff(all_i, collect(o)))
end

"""Compute the automorphisms of a CSet"""
function autos(g::StructACSet;
               history::Bool=false,
               auto_prune::Bool=true,
               orbit_prune::Bool=true,
               order_prune::Bool=false)::Tuple{Set{CDict},Tree, Vector{History}}
  tree, leafnodes = Tree(), Set{VPSI}()
  hist = history ? [History("start", g)] : History[]
  search_tree!(g, nocolor(g), VPSI(), tree, leafnodes,Indicator(),Set{VPSI}();
               history=hist, auto_prune=auto_prune, orbit_prune=orbit_prune,
               order_prune=order_prune)
  return Set([tree[ln].saturated for ln in leafnodes]), tree, hist
end

