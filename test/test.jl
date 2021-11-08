using Test
using Catlab.Graphs
using Catlab.CategoricalAlgebra
using Catlab.Present
using Catlab.Theories
using Catlab.CategoricalAlgebra.CSetDataStructures: struct_acset

using Random

include(joinpath(@__DIR__, "../src/CSetAutomorphisms.jl"))

# Auxillary function tests
##########################

@test common([],[]) == 0
@test common([1],Int[]) == 0
@test common([1],Int[1]) == 1
@test common([1],Int[1,2]) == 1
@test common([1,2,3],Int[1,2]) == 2

# Helper functions for writing automorphism tests
#################################################
function xs(x::Int)::Symbol
  return Symbol("x$x")
end
function xs(xx::AbstractVector{Int})::Vector{Symbol}
  return [Symbol("x$x") for x in xx]
end
function es(x::Int)::Symbol
  return Symbol("e$x")
end
function es(xx::AbstractVector{Int})::Vector{Symbol}
  [Symbol("e$x") for x in xx]
end

"""
Create a CSet type specified by a graph
Vertices are x₁,x₂,..., edges are e₁, e₂,...
all edges are indexed
"""
function graph_to_cset(grph::StructACSet, name::Symbol)::StructACSet
  pres = Presentation(FreeSchema)
  xobs = [Ob(FreeSchema,xs(i)) for i in 1:nv(grph)]
  for x in xobs
    add_generator!(pres, x)
  end
  for (i,(src, tgt)) in enumerate(zip(grph[:src], grph[:tgt]))
    add_generator!(pres, Hom(es(i), xobs[src], xobs[tgt]))
  end

  expr = struct_acset(name, StructACSet, pres, index=es(1:ne(grph)))
  eval(expr)
  csettype = eval(name)
  return Base.invokelatest(csettype)
end

"""Create n copies of a CSet based on a graph schema"""
function init_graphs(name::Symbol, schema::StructACSet, consts::Vector{Int},
                     n::Int=2)::Vector{StructACSet}
  cset = graph_to_cset(schema, name)
  for (i, con) in enumerate(consts)
    add_parts!(cset, Symbol("x$i"), con)
  end
  return [deepcopy(cset) for _ in 1:n]
end

"""Confirm canonical hash tracks with whether two ACSets are iso"""
function test_iso(a::StructACSet,b::StructACSet, eq::Bool=true)::Test.Pass
  tst = a -> eq ? a : !a
  @test tst(is_isomorphic(a,b))
  @test a != b  # confirm they're not literally equal
  @test tst(canonical_hash(a) == canonical_hash(b))
end

# Tests
#######

G,H = Graph(4), Graph(4);
add_edges!(G,[1,2,4,4,3],[2,4,3,3,2]);
add_edges!(H,[2,3,1,4,4],[1,1,4,3,3]);
test_iso(G,H) # 196 automorphisms

Triangle = Graph(3) # f;g = h
add_edges!(Triangle, [1,1,2], [2,3,3]) # f,h,g

G,H = init_graphs(:Tri, Triangle,[2,2,2])
for i in 1:3 set_subpart!(G, Symbol("e$i"), [1,1]) end
for i in 1:3 set_subpart!(H, Symbol("e$i"), [2,2]) end
test_iso(G, H)

Loop = Graph(1)
add_edge!(Loop, 1, 1)
G, H = init_graphs(:Loo, Loop, [3])
set_subpart!(G, Symbol("e1"), [3,2,1])
set_subpart!(H, Symbol("e1"), [1,3,2])
test_iso(G, H)

cyclel, cycler = Graph(3), Graph(3)
add_edges!(cyclel,[1,2,3],[2,3,1])
add_edges!(cycler,[3,2,1],[2,1,3])
test_iso(cyclel, cycler)

Loop2 = Graph(1)
add_edges!(Loop2, [1,1],[1,1])

G,H = init_graphs(:Loo2, Loop2, [2])
set_subpart!(G, :e1, [2,1])
set_subpart!(G, :e2, [2,1])
set_subpart!(H, :e1, [1,1])
set_subpart!(H, :e2, [2,2])
test_iso(G, H, false)

# Example from Hartke and Radcliffe exposition of Nauty.
# G is their optimal ordering. H is the original.
G, H = Graph(9), Graph(9)
add_edges!(G,[1,7,1,8,2,5,2,6,3,6,3,8,4,5,4,7,5,9,6,9,7,9,8,9],
             [7,1,8,1,5,2,6,2,6,3,8,3,5,4,7,4,9,5,9,6,9,7,9,8])
add_edges!(H,[1,2,1,4,3,2,3,6,7,4,7,8,9,6,9,8,2,5,4,5,6,5,8,5],
             [2,1,4,1,2,3,6,3,4,7,8,7,6,9,8,9,5,2,5,4,5,6,5,8])
res, tree = autos(H);
# When branching is restricted to :V as is the case in Nauty
# length should be 13 without auto pruning
# length is 10 with auto pruning tactic #1
# length is 6 with auto pruning tactic #2 too
# However, we can branch on :E too. This leads to just length 4 soln.

test_iso(G,H)

"""Graph corresponding to schema for finite limit sketch for categories"""
catschema = @acset Graph begin
  V = 7
  E = 17
  src = [2,2,1, 3,3,3, 4,4,5,5,4, 6,6,6, 7,7,7]
  tgt = [1,1,2, 2,2,2, 2,2,2,2,5, 1,2,3, 1,2,3]
end
random_perm = Dict([:V=>randperm(7), :E=>randperm(17)])
catschema2 = apply_automorphism(catschema, random_perm)
test_iso(catschema,catschema2)

# ACSet tests
@present TheoryDecGraph(FreeSchema) begin
  E::Ob
  V::Ob
  src::Hom(E,V)
  tgt::Hom(E,V)

  X::AttrType
  dec::Attr(E,X)
end

@acset_type Labeled(TheoryDecGraph)

G = @acset Labeled{String} begin
  V = 4
  E = 4
  src = [1,2,3,4]
  tgt = [2,3,4,1]
  dec = ["a","b","c","d"]
end;


H = @acset Labeled{String} begin
  V = 4
  E = 4
  src = [1,3,2,4]
  tgt = [3,2,4,1]
  dec = ["a","b","c","d"]
end;

test_iso(G,H) # vertices permuted

I = @acset Labeled{String} begin
V = 4
E = 4
src = [1,2,3,4]
tgt = [2,3,4,1]
dec = ["b","c","d","a"]
end;

test_iso(G,I) # labels permuted

N = @acset Labeled{String} begin
  V = 4
  E = 4
  src = [1,2,3,4]
  tgt = [2,3,4,1]
  dec = ["a","a","b","c"]
end;

test_iso(G,N, false) # label mismatch

K = @acset Labeled{String} begin
  V = 4
  E = 4
  src = [1,3,2,4]
  tgt = [2,3,4,1]
  dec = ["a","d","b","c"]
end;

test_iso(G,K,false) # vertex mismatch

G1 = @acset Labeled{String} begin
  V = 1
  E = 1
  src = [1]
  tgt = [1]
  dec = ["a"]
end;

H1 = @acset Labeled{String} begin
  V = 1
  E = 1
  src = [1]
  tgt = [1]
  dec = ["b"]
end;

test_iso(G1, H1, false) # label values different
