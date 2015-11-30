#=
"""
This file defines additional functions to return objects of type Distribution. This is
necessary because we specify prior distributions wrt mean and SD
(for beta and gamma-distributed parameters) and ν and σ (for inverse gamma-distributed
parameters). Note these functions are NOT new methods for the Distributions.Beta, etc.
functions, but rather new functions with the same names.
"""
=#


import Distributions: params, mean, std, pdf, logpdf, rand
import Base.length

"""
BetaAlt(μ::AbstractFloat, σ::AbstractFloat)

### Parameters
`μ::AbstractFloat`: The mean of the desired distribution 
`σ::AbstractFloat`: The standard deviation of the desired distribution 

### Description:
Given μ and σ, calculate α and β and return a Distributions.Beta Distribution object.
"""
function BetaAlt(μ::AbstractFloat, σ::AbstractFloat)
    α = (1-μ) * μ^2 / σ^2 - μ
    β = α * (1/μ - 1)
    return Distributions.Beta(α, β)
end


"""
GammaAlt(μ::AbstractFloat, σ::AbstractFloat)

### Parameters
`μ::AbstractFloat`: The mean of the desired distribution 
`σ::AbstractFloat`: The standard deviation of the desired distribution 

### Description:
Given μ and σ, calculate α and β and return a Distributions.Gamma object.
"""
function GammaAlt(μ::AbstractFloat, σ::AbstractFloat)
    β = σ^2 / μ
    α = μ / β
    return Distributions.Gamma(α, β)
end


"""
type RootInverseGamma <: Distribution{Univariate, Continuous}

If x ~ RootInverseGamma(ν, τ²), then
  x² ~ ScaledInverseChiSquared(ν, τ²)
  x² ~ InverseGamma(ν/2, ντ²/2)


"""
type RootInverseGamma <: Distribution{Univariate, Continuous}
    ν::Float64
    τ::Float64
end

Distributions.params(d::RootInverseGamma) = (d.ν, d.τ)

"""
moments(dist::Distributions.Beta)

Compute the mean μ and standard deviation σ of a Distributions.Beta object. 
"""
function moments(dist::Distributions.Beta)
    α = dist.α
    β = dist.β

    μ = α / (α + β)
    σ = sqrt( α*β/((α+β)^2 * (α+β+1)) )
    return μ, σ
end

"""
moments(dist::Distributions.Gamma)

Compute the mean μ and standard deviation σ of a Distributions.Gamma object. 
"""
function moments(dist::Distributions.Gamma)
    α = dist.α
    θ = dist.θ

    μ = α / θ
    σ = α / θ^2
    return μ, σ
end


"""
Distributions.pdf(d::RootInverseGamma, x::AbstractFloat)

Compute the pdf of a RootInverseGamma distribution at x.
"""
function Distributions.pdf(d::RootInverseGamma, x::AbstractFloat)
    (ν, τ) = params(d)
    return 2 * (ν*τ^2/2)^(ν/2) * exp((-ν*τ^2)/(2x^2)) / gamma(ν/2) / x^(ν+1)
end

"""
Distributions.logpdf(d::RootInverseGamma, x::AbstractFloat)

Compute the log pdf of a RootInverseGamma distribution at x.
"""
function Distributions.logpdf(d::RootInverseGamma, x::AbstractFloat)
    (ν, τ) = params(d)
    return log(2) - log(gamma(ν/2)) + (ν/2)*log(ν*τ^2/2) - ((ν+1)/2)*log(x^2) - ν*τ^2/(2x^2)
end



"""
DegenerateMvNormal <: Distribution{Multivariate, Continuous}

The DegenerateMvNormal type implements a degenerate multivariate normal distribution as a subtype of Distribution.
en.wikipedia.org/wiki/Multivariate_normal_distribution#Degenerate_case
"""
type DegenerateMvNormal <: Distribution{Multivariate, Continuous}
    μ::Vector          # mean
    σ::Matrix          # standard deviation
end


"""
DegenerateMvNormal(μ::Vector,σ::Matrix)

Returns a DegenerateMvNormal type with mean vector μ and covariance matrix σ
"""
function DegenerateMvNormal(μ::Vector,σ::Matrix)
    return DegenerateMvNormal(μ,σ)
end

"""
rank(d::DegenerateMvNormal)

Returns the rank of d.σ.
"""
function DegenerateMvNormal(d::DegenerateMvNormal)
    return rank(d.σ)
end


"""
length(d::DegenerateMvNormal)

Returns the dimension of d.
"""
Base.length(d::DegenerateMvNormal) = length(d.μ)



"""
Distributions.rand{T<:AbstractFloat}(d::DegenerateMvNormal; cc::T = 1.0)
Generate a draw from d with variance optionally scaled by cc^2.
"""
function Distributions.rand{T<:AbstractFloat}(d::DegenerateMvNormal; cc::T = 1.0)
    return d.μ + cc*d.σ*randn(length(d))
end
