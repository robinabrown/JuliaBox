using JuMP, Distributions, Gurobi, JSON

include("data_reader.jl") # provides data reader function

# Set the dimensions
n_z = 141
n_θ = 84
n_d = 141
n_f = 282
n_h = 141

# Set the covariance matrix for the uncertain parameters
θ_nom = zeros(n_θ)
nonzero_idx = [1; 13; 14; 15; 16; 50; 63]
nonzero_values = [0.739; 28.9; 7.98; 7.89; 2.95; 0.739; 0.739]
θ_nom[nonzero_idx] = nonzero_values
covar = eye(length(θ_nom)) * 100.

# Specify the network details
line_cap = 100
data = ParseFile("141bus.txt", line_cap)

# Extract information
fConsts = data["fConsts"]
fControls = data["fControls"]
fRandoms = data["fRandoms"]
hConsts = data["hConsts"]
hControls = data["hControls"]
hRandoms = data["hRandoms"]

# Set the problem parameters
c = ones(n_d) / sqrt(n_d)
c_max = 0:10:300
U = 10000
num_samples = 10000
sig_dig = 6

# Obtain samples
srand(11)
d = MvNormal(θ_nom, covar)
θs = rand(d, num_samples)

# Setup storage arrays
cont_costs = zeros(length(c_max))
cont_SFs = zeros(length(c_max))
cont_times = zeros(length(c_max))
cont_objs = zeros(length(c_max))
feasibles = Vector{Bool}(length(c_max))
cont_data = Dict()

# Iterate and solve over the different costs
for itr = 1:length(c_max)
    # Initialize the model and the variables
    m = Model(solver = GurobiSolver(OutputFlag = 0))
    @variable(m, 0 <= y[1:num_samples] <= 1)
    @variable(m, z[1:n_z, 1:num_samples])
    @variable(m, d[1:n_d] >= 0)

    # Set objective function
    @objective(m, Max, 1 / num_samples * sum(1 - y[k] for k = 1:num_samples))

    # Set the line capacity constraints
    @constraint(m, caps[j = 1:n_f - 1, k = 1:num_samples], fConsts[j] - d[Int((j % 2 + j) / 2)] + sum(fControls[j, i] * z[i, k] for i = 1:n_z) <= y[k] * U)
    @constraint(m, caps2[j = n_f, k = 1:num_samples], fConsts[j] + sum(fControls[j, i] * z[i, k] for i = 1:n_z) <= y[k] * U)

    # Set the balances
    @constraint(m, bal[j = 1:n_h, k = 1:num_samples], sum(hControls[j, i] * z[i, k] for i = 1:n_z) + sum(hRandoms[j, i] * θs[i, k] for i = 1:n_θ) == 0)

    # Enforce the max cost
    @constraint(m, max_cost, sum(c[i] * d[i] for i = 1:n_d) <= c_max[itr])

    # Solve and and obtain results
    status = solve(m)
    opt_y = getvalue(y)
    opt_d = getvalue(d)
    opt_obj = getobjectivevalue(m)
    opt_time = getsolvetime(m)

    # Estimate the value of SF
    SF = 1 - sum(opt_y .>= 1e-8) / num_samples

    # Print the results
    print("------------------RESULTS------------------\n")
    print("Optimal Objective:     ", signif(opt_obj, sig_dig), "\n")
    print("Solution Time:         ", signif(opt_time, sig_dig), "s\n")
    print("Optimal Cost:          ", signif(sum(c[i] * opt_d[i] for i = 1:n_d), sig_dig), "\n")
    print("Maximum Cost:          ", signif(c_max[itr], sig_dig), "\n")
    print("Predicted SF:          ", 100 * signif(SF, sig_dig), "%\n")
    print("Optimal Design Values: ", opt_d, "\n\n")

    # Check solution feasibility for mapped y's
    yf = zeros(num_samples)
    yf[opt_y .>= 1e-8] = 1
    m2 = Model(solver = CplexSolver(CPX_PARAM_TILIM = 3600))
    @variable(m2, z2[1:n_z, 1:num_samples])
    @variable(m2, d2[1:n_d] >= 0)

    # Set objective function
    @objective(m2, Max, 1 / num_samples * sum(1 - yf[k] for k = 1:num_samples))

    # Set the line capacity constraints
    @constraint(m2, caps[j = 1:n_f - 1, k = 1:num_samples], fConsts[j] - d2[Int((j % 2 + j) / 2)] + sum(fControls[j, i] * z2[i, k] for i = 1:n_z) <= yf[k] * U)
    @constraint(m2, caps2[j = n_f, k = 1:num_samples], fConsts[j] + sum(fControls[j, i] * z2[i, k] for i = 1:n_z) <= yf[k] * U)

    # Set the balances
    @constraint(m2, bal[j = 1:n_h, k = 1:num_samples], sum(hControls[j, i] * z2[i, k] for i = 1:n_z) + sum(hRandoms[j, i] * θs[i, k] for i = 1:n_θ) == 0)

    # Enforce the minimum SF
    @constraint(m2, sum(c[i] * d2[i] for i = 1:n_d) <= c_max[itr])

    # Solve and and obtain results
    status = solve(m2)

    # Save results
    feasibles[itr] = status == :Optimal
    cont_objs[itr] = opt_obj
    cont_costs[itr] = sum(c[i] * opt_d[i] for i = 1:n_d)
    cont_SFs[itr] = SF
    cont_times[itr] = opt_time
    cont_data[string(itr)] = Dict("y" => opt_y, "d" => opt_d, "cost" => cont_costs[itr], "SF" => SF,
                                  "time" => opt_time, "obj" => opt_obj, "feasible" => feasibles[itr])
end

# Write results to data file
open("141node_cont_data.json", "w") do f
    JSON.print(f,cont_data)
end
