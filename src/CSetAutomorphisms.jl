using Catlab.CategoricalAlgebra.CSets
using Catlab.Theories
using Catlab.Theories: adom, attr, attrtype, attr, adom, acodom
using Catlab.Present

using AutoHashEquals
using PermutationGroups

# Color assigned to each elem of each compoennt
const CDict = Dict{Symbol, Vector{Int}}

"""    pseudo_cset(g::ACSet{CD,AD})::Tuple{CSet, Vector{Vector{Any}}} where {CD, AD}

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
  for (a,t) in zip(darrs, dtabs)
    fks = [findfirst(==(v), attrvals[t]) for v in g[a]]
    set_subpart!(res, a, fks)
  end

  return res, attrvals
end

"""  pseudo_cset_inv(g::CSet, orig::ACSet{CD,AD}, attrvals::Vector{Vector{Any}})::ACSet{CD,AD} where {CD,AD}

Inverse of pseudo_cset. Requires mapping (generated by `pseudo_cset`) of indices
for each Data to the actual data values.
"""
function pseudo_cset_inv(g::StructACSet,
                         orig::StructACSet{S},
                         attrvals::Dict{Symbol,Vector{Any}}
                        )::StructACSet{S} where {S}
  orig = deepcopy(orig)
  arrs = hom(S)
  darrs, dtabs = attr(S), attrtype(S)
  for arr in arrs
    set_subpart!(orig, arr, g[arr])
  end
  for (darr,tgt) in zip(darrs, dtabs)
    set_subpart!(orig, darr, attrvals[tgt][g[darr]])
  end
  return orig
end

# The maximum color of an empty color list is 0
function max0(x::Vector{Int})::Int
  return isempty(x) ? 0 : maximum(x)
end

function check_auto(x::CDict)::Bool
  return all(map(Base.isperm, values(x)))
end

"""    apply_automorphism(c::CSet{S},d::CDict)::CSet{S} where {S}

Apply a coloring to a Cset to get an isomorphic cset
"""
function apply_automorphism(c::StructACSet{S}, d::CDict)::StructACSet{S} where {S}
  check_auto(d) || error("received coloring that is not an automorphism: $d")
  new = deepcopy(c)
  tabs, arrs, srcs, tgts = ob(S), hom(S), dom(S), codom(S)
  for (arr, src, tgt) in zip(arrs,srcs,tgts)
    set_subpart!(new, d[src],arr, d[tgt][c[arr]])
  end
  return new
end

"""    canonical_iso(g::StructACSet)::StructACSet

Lexicographic minimum of all automorphisms
"""
function canonical_iso(g::StructACSet{S})::StructACSet{S} where {S}
  isos = sort([apply_automorphism(g, Dict(a)) for a in autos(g)], by=string)
  return isempty(isos) ? g : isos[1]
end

"""
Compute automorphisms for the pseudo-cset, but then substitute in
the actual attribute values before evaluating the lexicographic order
"""
function canonical_iso(g::StructACSet{S})::StructACSet{S} where {S}
  p, avals = pseudo_cset(g)
  isos = sort([pseudo_cset_inv(apply_automorphism(p, Dict(a)), g, avals)
               for a in autos(p)], by=string)
  return isempty(isos) ? g : isos[1]
end

"""    canonical_hash(g::ACSet)::UInt64

Hash of canonical isomorphism.
"""
function canonical_hash(g::StructACSet)::UInt64
  return hash(string(canonical_iso(g)))
end

"""Data for an individual component (each vector corresponds to its elements)
1.) how many of each color (for each in-arrow) targets this point
2.) what color this point targets (for each out arrow)

This could be extended to add extra automorphism-invariant properties.
"""
@auto_hash_equals struct CDataPoint
  indata::Vector{Vector{Int}}
  outdata::Vector{Int}
end

# Data required to color a CSet (each element of each component)
const CData = Dict{Symbol, Vector{CDataPoint}}

"""
Computes colors for a CSet, distinguishing nodes by their immediate
connectivity. It is not sufficient to compute the automorphism group, but it is
a good starting point.

This does not generalize to ACSets. We cannot naively throw the attributes as
raw data into the color data. It will make indistinguishable elements (e.g. two
elements that map to different data but otherwise can be permuted) as
distinguishable.
"""
function compute_color_data(g::StructACSet{S}, color::CDict)::CData where {S}
  tabs, arrs, srcs, tgts = ob(S), hom(S), dom(S), codom(S)
  ntab = eachindex(tabs)
  res = CData()
  a_in  = [[a_ind for (a_ind, t_ind) in enumerate(tgts) if t_ind==i]
           for i in ntab]
  a_out = [[a_ind for (a_ind, s_ind) in enumerate(srcs) if s_ind==i]
           for i in ntab]

  for (tgt_ind, tgt) in enumerate(tabs)
    subres = Vector{Vector{Int}}[]  # for each table
    for arr_ind in a_in[tgt_ind]
      src = tabs[srcs[arr_ind]]
      color_src = color[src]
      n_color_src = max0(color_src)
      preimg = g.indices[arrs[arr_ind]]
      subsubres = Vector{Int}[]  # for particular elem in tgt
      for tgt_elem in 1:nparts(g, tgt)
        precolor_elem = color_src[preimg[tgt_elem]]
        n_precolor = [count(==(x), precolor_elem) for x in 1:n_color_src]
        push!(subsubres, n_precolor)
      end
      push!(subres, subsubres)
    end

    # Also compute per-element data for table `tgt` (now, regard as a src)
    outgoing_arrows = a_out[tgt_ind]
    out_subres = Vector{Int}[color[tabs[tgts[oga]]][g[arrs[oga]]]
                             for oga in outgoing_arrows]

    # Combine the two pieces of data for each elmeent in tgt, store in res
    res[tgt] = [CDataPoint([ssr[i] for ssr in subres],
                           [osr[i] for osr in out_subres])
          for i in 1:nparts(g,tgt)]
  end
  return res
end

"""
Construct permutation σ⁻¹ such that σσ⁻¹=id
"""
function invert_perm(x::CDict)::CDict
  return Dict([k=>Base.invperm(v) for (k, v) in collect(x)])
end

"""
Compose permutations
"""
function compose_perms(x::CDict, y::CDict)::CDict
  function compose_comp(xs::Vector{Int},ys::Vector{Int})::Vector{Int}
    return [ys[xs[i]] for i in eachindex(xs)]
  end
  return Dict([k=>compose_comp(v1,y[k]) for (k, v1) in collect(x)])
end

"""    color_refine(g::CSet{CD}; init_color::Union{Nothing,CDict}=nothing)::CDict where {CD}

Iterative color refinement based on the number (and identity) of incoming and
outgoing arrows.
"""
function color_refine(g::StructACSet{S};
                      init_color::Union{Nothing,CDict}=nothing
                     )::CDict where {S}
  # Default: uniform coloring
  new_color = (init_color === nothing
              ? CDict([k => ones(Int, nparts(g, k)) for k in ob(S)])
              : init_color)

  prev_n, curr_n, iter = 0, 1, 0
  while prev_n != curr_n
    iter += 1
    prev_color = new_color
    # All that matters about newdata's type is that it is hashable
    newdata = compute_color_data(g, prev_color)
    # Distinguish by both color AND newly computed color data
    new_datahash = Dict{Symbol, Vector{UInt}}(
      [k=>map(hash, zip(prev_color[k],v)) for (k, v) in collect(newdata)])
    # Identify set of new colors for each component
    hashes = Dict{Symbol, Vector{UInt}}(
      [k=>sort(collect(Set(v))) for (k, v) in new_datahash])
    # Assign new colors by hash value of color+newdata
    new_color = CDict([
      k=>[findfirst(==(new_datahash[k][i]), hashes[k])
          for i in 1:nparts(g, k)]
      for (k, v) in new_datahash])
    prev_n = sum(map(max0, values(prev_color)))
    curr_n = sum(map(max0, values(new_color)))
  end
  return new_color
end

"""
Find index at which two vectors diverge (used in `search_tree`)
"""
function common(v1::Vector{T}, v2::Vector{T})::Int where {T}
  for (i, (x, y)) in enumerate(zip(v1, v2))
    if x != y
      return i-1
    end
  end
  return i
end

"""Convert sorted permutation into a single permutation"""
function to_perm(d::CDict, csum::Vector{Int})::Perm
  res = vcat([[vi + offset for vi in v]
              for ((_, v), offset) in zip(sort(collect(d)), csum)]...)
  return Perm(res)
end

"""Convert single permutation back into sorted permutation"""
function from_perm(p::Perm, syms::Vector{Symbol}, lens::Vector{Int},
                   csum::Vector{Int})::CDict
  res = CDict()
  for (k, l, off) in zip(syms, lens, csum)
    res[k] = [p[i+off]-off for i in 1:l]
  end
  return res
end

"""Enumerate the elements of a permutation group from its generators"""
function all_perms(perm_gens::Vector{CDict})::Set{CDict}
  syms = sort(collect(keys(perm_gens[1])))
  lens = map(length, [perm_gens[1][x] for x in syms])
  csum = vcat([0], cumsum(lens)[1:end-1])
  _,_,Cs = schreier_sims([to_perm(g, csum) for g in perm_gens])
  result = Set{CDict}()

  """
  Recursive function based on (sub)chain C and partial product r
  Algorithm from Fig II.1 of Alexander Hulpke's notes on Computational
  Group Theory (Spring 2010).
  """
  function enum(i, r)
    leaf = i == length(Cs)
    C = Cs[i]
    for d ∈ C.orb
      xr = C[d]*r
      leaf ? push!(result, from_perm(xr, syms, lens, csum)) : enum(i+1, xr)
    end
  end

  enum(1, Perm(1:sum(lens)))

  return result
end


"""
DFS tree of colorings, with edges being choices in how to break symmetry
Goal is to acquire all leaf nodes.

Algorithm from "McKay’s Canonical Graph Labeling Algorithm" by Hartke and
Radcliffe (2009).

Note, there is another use of automorphisms not yet implemented:
 -"Automorphisms discovered during the search can also be used to prune the
   search tree in another way. Let d be a node being re-visited by the depth
   first search. Let Γ be the group generated by the automorphisms discovered
   thus far, and let Φ be the subgroup of Γ that fixes d. Suppose that b and c
   are children of d where some element of Φ maps b to c. If T(G,b) has already
   been examined, then, as above, there is no need to examine T(G,c). Hence
   T(G,c) can be pruned from the tree."
"""
function search_tree!(g::StructACSet{S}, res::Vector{CDict},
                     coloring::CDict,
                     split_seq::Vector{Int},
                     tree::Dict{Vector{Int},CDict},
                     perms::Set{Vector{Int}},
                     skip::Set{Vector{Int}}
                    )::Nothing where {S}

  tree[split_seq] = coloring # add the current color to the tree

  # To reduce branching factor, split on the SMALLEST nontrivial partition
  colors_by_size = []
  for (k, v) in coloring
    for color in 1:max0(v)
      n_c = count(==(color), v)
      if n_c > 1
        # Store which table and which color
        push!(colors_by_size, n_c => (k, color))
      end
    end
  end

  if isempty(colors_by_size) # We found a leaf!
    # Construct automorphisms between leaves
    # to possibly prune the search tree. See Figure 4
    tau_inv = invert_perm(coloring)
    for p in perms
      pii = tree[p]
      auto = compose_perms(pii,tau_inv)
      i = common(p, split_seq)
      a = tree[p[1:i]]
      if compose_perms(auto, a) == a
        b = tree[p[1:i+1]]
        c_location = split_seq[1:i+1]
        c = tree[c_location]
        if compose_perms(auto, b) == c
          push!(skip, c_location)
        end
      end
    end
    # Add permutation to the list of results
    push!(perms, split_seq)
    push!(res, coloring)
  else
    sort!(colors_by_size)
    split_tab, split_color = colors_by_size[1][2]
    colors = coloring[split_tab]
    split_inds = findall(==(split_color), colors)
    for split_ind in split_inds
      if  !(split_seq in skip)
        new_coloring = deepcopy(coloring)
        new_seq = vcat(split_seq, [split_ind])
        new_coloring[split_tab][split_ind] = max0(colors) + 1
        refined = color_refine(g; init_color=new_coloring)
        search_tree!(g, res, refined, new_seq, tree, perms, skip)
      end
    end
  end
  return nothing
end

"""    autos(g::CSet)::Vector{CDict}

Compute the automorphisms of a CSet
"""
function autos(g::StructACSet)::Set{CDict}
  res = CDict[]
  search_tree!(g, res, color_refine(g), Int[],
             Dict{Vector{Int},CDict}(),
             Set{Vector{Int}}(),
             Set{Vector{Int}}())
  return all_perms(res)
end

