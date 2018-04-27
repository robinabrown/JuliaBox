# if solve with SNGO
#=
include("../../bb.jl")
P = RandomStochasticModel(createModel, NS)   #RandomStochasticModel(createModel, nscen=10, nfirst=5, nparam=5)
m = copyStoModel(P)
branch_bound(m)
=#



# if solve with SCIP
mingap = 0.01
P = RandomStochasticModel(createModel, NS)
m= extensiveSimplifiedModel(P)
m = copyNLModel(m)
m.solver = SCIPSolver("limits/gap", mingap, "limits/absgap", mingap, "limits/time", 43200.0)
solve(m)



# if solve with Ipopt
#=
P = RandomStochasticModel(createModel, NS)
m= extensiveSimplifiedModel(P)
m = copyNLModel(m)
m.solver = IpoptSolver()
solve(m)
=#
