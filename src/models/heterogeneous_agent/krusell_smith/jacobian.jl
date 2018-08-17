function jacobian(m::KrusellSmith)

    # Load in endogenous state and eq cond indices
    endo = augment_model_states(m.endogenous_states_unnormalized,
                                n_model_states_unnormalized(m))
    eq   = m.equilibrium_conditions

    # Load in grid settings
    nw::Int = get_setting(m, :nw)
    ns::Int = get_setting(m, :ns)

    zhi::Float64 = get_setting(m, :zhi)
    zlo::Float64 = get_setting(m, :zlo)
    smoother::Float64 = get_setting(m, :smoother)

    wgrid = get_grid(m, :wgrid)
    sgrid = get_grid(m, :sgrid)

    # Make the Jacobian
    JJ = zeros(4*nw+2,8*nw+4)

    # Create auxiliary variables
    g::Array{Float64,1} = trunc_lognpdf(sgrid, m[:μ_s].value, m[:σ_s].value)                   # density g (of skill, s) evaluated on sgrid

    m[:Wstar] = MPL(1.0, m[:Lstar].value, m[:Kstar].value, m[:α].value)            # Steady state wages
    m[:Rstar] = MPK(1.0, m[:Lstar].value, m[:Kstar].value, m[:α].value, m[:δ].value)     # Steady state net return on capital

    # KF equation
    KFmollificand::Array{Float64, 2} = (repmat(wgrid.points, 1, nw*ns) - m[:Rstar]*repmat(wgrid.points'-m[:cstar].value', nw, ns))/m[:Wstar] - kron(sgrid.points',ones(nw, nw))
    μRHS::Array{Float64,1} = mollifier.(KFmollificand, zhi, zlo, smoother)*kron(sgrid.weights.*(g/m[:Wstar]), wgrid.weights.*m[:μstar].value)

    # These matrices (from the Euler equation) correspond to the matrices in the PDF documentation on Dropbox
    # (note that Γ is Λ removing the Σ_i^nx, and the ω^x_i terms from the summation.
    ξ = Array{Float64, 2}(nw, nw) #zeros(nw, nw)
    Γ = Array{Float64, 2}(nw, nw) #zeros(nw, nw)

    # These matrices (from the KF equation) corresp. to the lyx document on dropbox, script A and ζ
    AA = Array{Float64,2}(nw, nw)
    ζ = Array{Float64, 2}(nw, nw)

    # i_w is the ith entry in the nw discretization of x
    # i_wp is i_w' the grid of potential future x's
    for i_w in 1:nw
        for i_wp in 1:nw
            # The following hold the sums over i=1̣̣̣̣, ..., ns
            sum_ns_ξ::Float64 = 0.0
            sum_ns_Γ::Float64 = 0.0
            sum_ns_AA::Float64 = 0.0
            sum_ns_ζ::Float64 = 0.0
            # The first part of ξ and Γ which only relies on i_w' so we calculate outside of 1:ns loop
            front = ((m[:cstar].value[i_wp].^(-m[:γ]))/m[:Wstar])
            first_part_mollificand = (wgrid.points[i_wp] - m[:Rstar] * (wgrid.points[i_w] -
                                                                        m[:cstar].value[i_w]))/m[:Wstar]
            for iss in 1:ns
                mollificand::Float64 = first_part_mollificand - sgrid.points[iss]
                # dm and mm are the mollifiers which correspond to q(mollificand) in the paper
                dm = dmollifier(mollificand, zhi, zlo, smoother)
                mm = mollifier(mollificand, zhi, zlo, smoother)
                skill_distrib_weights = g[iss] * sgrid.weights[iss]

                sum_ns_ξ += front * dm * skill_distrib_weights
                sum_ns_Γ += front * mm * skill_distrib_weights
                sum_ns_AA+= (1.0/m[:Wstar]) * mm * skill_distrib_weights
                sum_ns_ζ += (1.0/m[:Wstar]) * dm * skill_distrib_weights
            end
            ξ[i_w,i_wp] = sum_ns_ξ
            Γ[i_w,i_wp] = sum_ns_Γ
            AA[i_w,i_wp] = sum_ns_AA
            ζ[i_w,i_wp] = sum_ns_ζ
        end
    end

    dRdK::Float64 = -(1-m[:α])*((m[:Rstar]+m[:δ]-1)/m[:Kstar])
    dWdK::Float64 = (m[:α]*m[:Wstar]/m[:Kstar])
    dRdZ::Float64 = m[:Rstar]+m[:δ]-1.0
    dWdZ::Float64 = m[:Wstar].value
    lRHS = m[:β]*m[:Rstar]*Γ*wgrid.weights

    # Fill in Jacobian

    # Euler equation (EE)
    term1_EE::Array{Float64, 1} = m[:β]*Γ*wgrid.weights - m[:β]*(m[:Rstar]/m[:Wstar]) * ((wgrid.points-m[:cstar].value) .* (ξ*wgrid.weights))
    term2_EE::Array{Float64, 1} = -(1.0/m[:Wstar]) * (lRHS+((m[:β]*m[:Rstar])/m[:Wstar]) * ξ.*(repmat(wgrid.points', nw, 1) - m[:Rstar]*repmat(wgrid.points-m[:cstar].value,1,nw))*wgrid.weights)

    JJ[eq[:eq_euler], endo[:K′_t]]  = term1_EE*dRdK + term2_EE*dWdK
    JJ[eq[:eq_euler], endo[:z′_t]] = term1_EE*dRdZ + term2_EE*dWdZ

    JJ[eq[:eq_euler], endo[:l′_t]] = m[:β]*m[:Rstar]*Γ*diagm((wgrid.weights.*(m[:lstar].value.^(-(1.0+m[:γ])/m[:γ]))
                                   .*(m[:lstar].value.^(-1.0/m[:γ]) .<= wgrid.points))./m[:cstar].value)

    JJ[eq[:eq_euler], endo[:l_t]]  = -(eye(nw) + diagm((m[:β]/m[:γ])*(m[:Rstar]*m[:Rstar]/m[:Wstar])*(ξ*wgrid.weights)
                                   .*(m[:lstar].value.^(-(1.0+m[:γ])/m[:γ])).*(m[:lstar].value.^(-1.0/m[:γ]) .<= wgrid.points)) )

    # KF Equation
    JJ[eq[:eq_kolmogorov_fwd], endo[:μ_t1]]   = AA'*diagm(wgrid.weights)

    JJ[eq[:eq_kolmogorov_fwd], endo[:l_t1]] = (-(m[:Rstar]/m[:Wstar])*(1.0/m[:γ])*ζ') * diagm( m[:μstar].value.*wgrid.weights.*(m[:lstar].value.^(-(1.0+m[:γ])/m[:γ])) .*(m[:lstar].value.^(-1.0/m[:γ]) .<= wgrid.points))

    term1_KF::Array{Float64,1} = -(1.0/m[:Wstar])*(ζ'.*repmat((wgrid.points-m[:cstar].value)',nw,1))*(m[:μstar].value.*wgrid.weights)
    term2_KF::Array{Float64,1} = -(μRHS/m[:Wstar] + (1.0/(m[:Wstar]*m[:Wstar]))*(ζ'.*(repmat(wgrid.points,1,nw) - m[:Rstar]*repmat( (wgrid.points-m[:cstar].value)',nw,1)))*(m[:μstar].value.*wgrid.weights))

    JJ[eq[:eq_kolmogorov_fwd], endo[:K_t]]  = term1_KF*dRdK + term2_KF*dWdK
    JJ[eq[:eq_kolmogorov_fwd], endo[:z_t]]   = term1_KF*dRdZ + term2_KF*dWdZ

    JJ[eq[:eq_kolmogorov_fwd], endo[:μ_t]]    = -eye(nw)

    # DEFN of LM(t+1) = M(t)
    JJ[eq[:eq_μ], endo[:μ′_t1]]  = eye(nw)

    JJ[eq[:eq_μ], endo[:μ_t]]    = -eye(nw)

    # DEFN of LELL(t+1) = ELL(t)
    JJ[eq[:eq_l], endo[:l′_t1]]= eye(nw)

    JJ[eq[:eq_l], endo[:l_t]]  = -eye(nw)

    # LOM K
    JJ[eq[:eq_K_law_of_motion], endo[:l_t]]  = -(1.0/m[:γ])*m[:μstar].value'*(diagm(wgrid.weights.*(m[:lstar].value.^(-(1.0+m[:γ])/m[:γ]))
                                               .*(m[:lstar].value.^(-1.0/m[:γ]) .<= wgrid.points)))

    JJ[eq[:eq_K_law_of_motion], endo[:μ_t]]  = -(wgrid.points-m[:cstar].value)'*diagm(wgrid.weights)

    JJ[eq[:eq_K_law_of_motion], endo[:K′_t]]  = 1.0

    # TFP
    JJ[eq[:eq_TFP], endo[:z′_t]]   = 1.0

    JJ[eq[:eq_TFP], endo[:z_t]]    = -m[:ρ_z]

    return JJ
end

# The reason for this function is that the canonical form for the Klein solution method is
# as follows:
# E_t A([x_{t+1}, y_{t+1}]) = B[x_t, y_t]
# Where we only need to track [x_{t+1}, y_{t+1}] as states when
# we transform the system from canonical form to state space form
# Hence because we only keep track of the t+1 indexed variables, which we denote
# with a ′, we need a way of calculating the indices in the Jacobian corresponding
# to the t indexed variables.
function reindex_unprimed_model_states(inds::UnitRange, n_model_states::Int64)
    return inds + n_model_states
end

# Returns a model state variable symbol without the prime
function unprime(state::Symbol)
    return Symbol(replace(string(state), "′", ""))
end

# Adds the unprimed model states to the dictionary of ranges to properly
# fill the Jacobian matrix
# Note: This is not augmentation in the usual sense, which incorporates lags of
# model state variables after the transition equation has been solved for
# but rather, augmenting the model states with lags prior to solution since the
# solution method requires lags
function augment_model_states(endo::OrderedDict{Symbol, UnitRange}, n_model_states::Int64)
    endo_aug = deepcopy(endo)
    for (state::Symbol, inds::UnitRange) in endo
        unprimed_state = unprime(state)
        unprimed_inds::UnitRange  = reindex_unprimed_model_states(inds, n_model_states)
        endo_aug[unprimed_state] = unprimed_inds
    end
    return endo_aug
end
