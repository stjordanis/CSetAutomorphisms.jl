using Catlab.Theories: adom, attr, attrtype, attr, adom, acodom
using Catlab.Present
using Catlab.CategoricalAlgebra.CSetDataStructures: struct_acset

include(joinpath(@__DIR__, "Perms.jl"))
include(joinpath(@__DIR__, "ColorRefine.jl"))

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
  scorediffs, scorediff = Set(),
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
  isos = sort([apply_automorphism(g, Dict(a)) for a in autos(g)[1]], by=ord)
  return isempty(isos) ? g : isos[1]
end

"""
Compute automorphisms for the pseudo-cset, but then substitute in
the actual attribute values before evaluating the lexicographic order
"""
function canonical_iso(g::StructACSet{S})::StructACSet{S} where {S}
  os = order_syms(g)
  ord(x) = vcat([x[a] for a in attr(S)],[x[s] for s in os])

  p, avals = pseudo_cset(g)
  isos = sort([pseudo_cset_inv(apply_automorphism(p, Dict(a)), g, avals)
               for a in autos(p)[1]], by=ord)
  return isempty(isos) ? g : isos[1]
end

"""Hash of canonical isomorphism."""
function canonical_hash(g::StructACSet)::UInt64
  return hash(string(canonical_iso(g)))
end

"""Find index at which two vectors diverge (used in `search_tree`)"""
function common(v1::Vector{T}, v2::Vector{T})::Int where {T}
  for (i, (x, y)) in enumerate(zip(v1, v2))
    if x != y
      return i-1
    end
  end
  return i
end

mutable struct Tree
  coloring::CDict
  children::Dict{Pair{Symbol, Int},Tree}
  function Tree(c::CDict)
    return new(c, Dict{Pair{Symbol, Int},Tree}())
  end
end

function Base.size(t::Tree)::Int
  return isempty(t.children) ? 1 : 1 + sum(map(Base.size, values(t.children)))
end
function Base.getindex(t::Tree, pth::Vector{Pair{Symbol, Int}})::Tree
  ptr = t
  for p in pth
    ptr = ptr.children[p]
  end
  return ptr
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
"""
function search_tree!(g::StructACSet{S}, res::Set{CDict},
                     split_seq::Vector{Pair{Symbol, Int}},
                     tree::Tree,
                     leafnodes::Set{Vector{Pair{Symbol, Int}}},
                     perm_worsts::Set{Vector{VUNI}},
                     skip::Set{Vector{Pair{Symbol, Int}}};
                     verbose::Bool=false,
                     auto_prune::Bool=true,
                     orbit_prune::Bool=true,
                     order_prune::Bool=true,
                    )::Nothing where {S}
  #tree[split_seq] = coloring # add the current color to the tree
  # To reduce branching factor, split on the SMALLEST nontrivial partition
  curr_tree = tree[split_seq]
  coloring = curr_tree.coloring
  if verbose
    println("\nSTART $split_seq ||| $coloring")
  end
  colors_by_size = get_colors_by_size(coloring)

  if isempty(colors_by_size) # We found a leaf!
    if verbose
      println("\tFOUND PERM!")
    end
    if auto_prune
      t, τ = split_seq, coloring
      for p in leafnodes
        π = tree[p].coloring
        i = common(p, t)
        a = p[1:i] # == t[1:i]
        b, c = p[1:i+1], t[1:i+1]
        a_, b_, c_ = [tree[x].coloring for x in [a,b,c]]
        γ = compose_perms(π, invert_perm(τ))
        if (compose_perms(γ, a_) == a_ &&
            compose_perms(γ, b_) == c_)
          if verbose
            println("\tAUTO PRUNE using leaf $p")
          end
          # skip everything from c to a
          for i in length(c):length(t)
            push!(skip, t[1:i])
          end
          break
        end
      end
    end
    # Add permutation to the list of results
    push!(leafnodes, split_seq)
    push!(res, coloring)
  else
    # check if we can prune due to automorphisms.  See Figure 4
    # check if we can prune due to objective rank
    if order_prune
      os = order_syms(g)
      best, worst = order_perms(g, coloring, os)
      for p_worst in perm_worsts
        if compare_perms(p_worst, best) == false
          if verbose println("ORDER PRUNE") end
          return nothing
        end
      end
      # this partition isn't STRICTLY worse than anything seen so far
      push!(perm_worsts, worst)
    end

    # Branch on this leaf
    sort!(colors_by_size, rev=true)
    split_tab, split_color = colors_by_size[1][2]
    if verbose
      println("splitting on $split_tab#$split_color")
    end
    colors = coloring[split_tab]
    split_inds = findall(==(split_color), colors)
    for split_ind in split_inds
      if verbose
        println("split_ind on $split_ind (res=$res)")
      end

      orb = orbit_prune && orbit_check(curr_tree, split_tab, split_color; verbose=verbose)
      if orb && verbose
        println("\nORBIT PRUNE @ $split_seq")
      end
      if split_seq ∉ skip && !orb
        new_coloring = deepcopy(coloring)
        new_seq = vcat(split_seq, [split_tab => split_ind])
        new_coloring[split_tab][split_ind] = max0(colors) + 1
        refined = color_refine(g; init_color=new_coloring)
        new_tree = Tree(refined)
        curr_tree.children[split_tab=>split_ind] = new_tree
        search_tree!(g, res, new_seq, tree, leafnodes, perm_worsts, skip;
                    verbose=verbose,
                    auto_prune=auto_prune,
                    orbit_prune=orbit_prune,order_prune=order_prune)
      end
    end
     # all children's worsts are now in the set
    if order_prune delete!(perm_worsts, worst) end
  end

  return nothing
end
function get_leaves(t::Tree)::Vector{Vector{Pair{Symbol, Int}}}
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
"""Look at all automorphisms between leaf nodes. If they generate a group with just one orbit in the specific part where the current tree got differentiated, we need not explore further (returns true)"""
function orbit_check(t::Tree, pₛ::Symbol, pᵢ::Int; verbose::Bool=false)::Bool
  leaves, auts = get_leaves(t), Perm[]
  for i in 1:length(leaves)
    icolor = t[leaves[i]].coloring
    for j in i+1:length(leaves)
      jcolor = t[leaves[j]].coloring
      push!(auts,Perm(compose_perms(icolor, invert_perm(jcolor))[pₛ]))
    end
  end
  all_i = findall(==(pᵢ), t.coloring[pₛ])
  length(all_i) > 1 || error("branched on nontrivial color")
  o = Orbit(auts, all_i[1])
  if verbose
    println("pₛpᵢ=$pₛ$pᵢ all_i=$all_i \nauts=$auts\norb=$(collect(o))") end
  return isempty(setdiff(all_i, collect(o)))
end

"""Compute the automorphisms of a CSet"""
function autos(g::StructACSet; verbose::Bool=false,
                auto_prune::Bool=true,
                orbit_prune::Bool=true,
                order_prune::Bool=true)::Tuple{Set{CDict},Tree}
  res = Set{CDict}()
  tree = Tree(color_refine(g))
  search_tree!(g, res, Vector{Pair{Symbol, Int}}(),
             tree, Set{Vector{Pair{Symbol, Int}}}(),
             Set{Vector{VUNI}}(),Set{Vector{Pair{Symbol, Int}}}(); verbose=verbose,
             auto_prune=auto_prune,
             orbit_prune=orbit_prune,
             order_prune=order_prune)
  return res, tree # all_perms(res)
end
