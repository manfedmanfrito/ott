function LG = lgmode(p,l,r,phi)
% lgmode -- LG mode at z = 0
%
% Usage:
% A = lgmode(p,l,r,phi);
% where
% r is in units of the beam width
% r and phi can be matrices of equal size
%
% This file is part of the package Optical tweezers toolbox 1.0.1
% Copyright 2006-2007 The University of Queensland.
% See README.txt or README.m for license and details.
%
% http://www.physics.uq.edu.au/people/nieminen/software.html

LG = sqrt(2*factorial(p)/(pi*factorial(p+abs(l)))) * (sqrt(2)*r).^abs(l) .* laguerre(p,abs(l),2*r.^2) ...
    .* exp(i*l*phi) .* exp(-r.^2) * exp(i * (2*p + abs(l) + 1) * pi/2);

return
