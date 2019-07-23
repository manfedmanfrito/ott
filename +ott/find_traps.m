function traps = find_traps(position, force, varargin)
% FIND_TRAPS attempt to find and characterise traps from position-force data
%
% traps = find_traps(position, force, ...) attempts to find and characterise
% possible traps for the given position and force data.  Position and
% force should be vectors with position and force along one axis.
%
% The returned traps is an array of structures with information about
% the trap equilibrium position, trap depth and trap stiffness and trap range.
%
% Optional named arguments:
%   keep_unstable    bool   keep unstable equilibriums (default: false)
%   depth_threshold_e num   percentage of max depth for trap acceptance
%       Use [] for no threshold.  (default: 1e-2).
%   group_stable     bool   group stable traps separated by smaller
%       unstable traps together (useful for finding trap depth)
%       (default: false)
%
% See also ott.find_equilibrium ott.axial_equilibrium and ott.trap_stiffness.
%
% This file is part of the optical tweezers toolbox.
% See LICENSE.md for information about using/distributing this file.

% TODO: We could add options to polyfit both the minmax force and equilibrium

% Parse optional inputs
p = inputParser;
p.addParameter('keep_unstable', false);
p.addParameter('depth_threshold_e', 1e-2);
p.addParameter('group_stable', false);
p.parse(varargin{:});

% This function is not directly concerned with force/torque calculation
ott.warning('ott:findEquilibrium:move', ...
    'This function will move in a future release');

% Check the size of the inputs
assert(isvector(position), 'position must be a vector not a matrix');
assert(isvector(force), 'force must be a vector not a matrix');

% Make sure the vectors are both colum vectors
position = position(:);
force = force(:);

%% Find rough equilibrium positions

% Find first equilibrium position
if force(1) >= 0
  last = find(force < 0, 1);
else
  last = find(force >= 0, 1);
end

% Find remaing equilibriums
eqs = [];
while ~isempty(last)
  eqs(end+1) = last;

  if force(last) >= 0
    last = find(force(last:end) < 0, 1) + last - 1;
  else
    last = find(force(last:end) >= 0, 1) + last - 1;
  end
end

%% Find more precise equilibrium positions and trap stiffness
% This is based on ott.find_equilibrium

peqs = zeros(1, length(eqs));
pstiff = zeros(1, length(eqs));

for ii = 1:length(eqs)
  
  % TODO: Need to fix this for rapidly fluctuating traps
  
  % Equilibrium is between eqs(ii)-1 and eqs(ii)
  eqguess = (position(eqs(ii)) + position(eqs(ii)-1))/2;

  % Fit polynomial to points aroung equilibrium
  eqrange = max([eqs(ii)-2,1]):min([eqs(ii)+1,length(position)]);
  z = position(eqrange);

  % Scale position and force before polyfit
  zmin = min(z);
  zmax = max(z);
  z = 2 * (z - zmin) / (zmax - zmin) - 1;
  zzero = 2 * (eqguess - zmin) / (zmax - zmin) - 1;

  % Find equilibrium: fit local points to 3rd order polynomail
  % Requires small distance between positions
  if length(z) < 4
    pz=polyfit(z, force(eqrange), 2);
    dpz=[2*pz(1),1*pz(2)];
  else
    pz=polyfit(z, force(eqrange), 3);
    dpz=[3*pz(1),2*pz(2),1*pz(3)];
  end
  root_z=roots(pz);

  % Ignore non-real roots
  real_z=root_z(imag(root_z)==0);
  if numel(real_z) == 0
    error('No real roots');
  end

  % Keep only one root closest to position(eqs(ii))
  zeqs_idx = abs(real_z-zzero) == min(abs(real_z-zzero));
  real_z = real_z(zeqs_idx);
  real_z = real_z(1);

  % Get the equilibrium
  peqs(ii) = real_z;

  % Calculate stiffness (using derivative of 3rd order polynomial)
  pstiff(ii) = polyval(dpz, peqs(ii));

  % Inverse scaling of position and force after fitting
  peqs(ii) = (peqs(ii) + 1)/2*(zmax - zmin) + zmin;
  pstiff(ii) = pstiff(ii)*2/(zmax - zmin);

end

%% Calculate other properties needed for traps

traps = struct('position', {}, 'stiffness', {}, 'depth', {}, ...
    'range', {}, 'minmax_force', {}, 'minmax_position', {});

for ii = 1:length(eqs)

  % Check if stable equilibrium
  if ~p.Results.keep_unstable && pstiff(ii) >= 0
    continue;
  end
  
  idx = length(traps) + 1;

  % Store stiffness and equilibrium
  traps(idx).position = peqs(ii);
  traps(idx).stiffness = pstiff(ii);

  % Calculate trap range
  traps(idx).range = [-Inf, Inf];
  if ii ~= 1
    traps(idx).range(1) = peqs(ii-1);
  end
  if ii ~= length(eqs)
    traps(idx).range(2) = peqs(ii+1);
  end

  % Calculate trap depth
  frange = [1, length(force)];
  if ii ~= 1
    frange(1) = eqs(ii-1);
  end
  if ii ~= length(eqs)
    frange(2) = eqs(ii+1)-1;
  end
  [fn, fnidx] = min(force(frange(1):frange(2)));
  [fx, fxidx] = max(force(frange(1):frange(2)));
  traps(idx).minmax_force = [fx, fn];
  traps(idx).minmax_position = position(frange(1)+[fxidx, fnidx]-1).';
  if fnidx < fxidx
    traps(idx).minmax_force = fliplr(traps(idx).minmax_force);
    traps(idx).minmax_position = fliplr(traps(idx).minmax_position);
  end
  traps(idx).depth = min(abs(traps(idx).minmax_force));

end

%% Group traps by depth

if p.Results.group_stable && length(traps) >= 1
  
  assert(~p.Results.keep_unstable, ...
    'group_stable option incompatible with keep_unstable');
  
  % All traps data gets merged together into row vectors (or matrices)
  % Add group_range property (from min range to max range)
  % Add group_depth property (trap depth for group)
  % Add group_minmax_position and group_minmax_force

  % Identify trap groups
  minmax_force = traps(1).minmax_force;
  minmax_position = traps(1).minmax_position;
  group_idx = ones(1, length(traps));
  for ii = 2:length(traps)
    if traps(ii).minmax_force(1) < minmax_force(1) ...
        && traps(ii).minmax_force(2) < minmax_force(2)
      minmax_force(2) = traps(ii).minmax_force(2);
      minmax_position(2) = traps(ii).minmax_position(2);
      group_idx(ii) = group_idx(ii-1);
    else
      minmax_force = traps(ii).minmax_force;
      minmax_position = traps(ii).minmax_position;
      group_idx(ii) = group_idx(ii-1) + 1;
    end
  end
  
  % Create structure for new traps/groups
  old_traps = traps;
  traps = struct('position', {}, 'stiffness', {}, 'depth', {}, ...
    'range', {}, 'minmax_force', {}, 'minmax_position', {}, ...
    'group_range', {}, 'group_depth', {}, ...
    'group_minmax_position', {}, 'group_minmax_force', {});
  
  % Group traps together
  for ii = 1:max(group_idx)
    
    idx = group_idx == ii;
    
    % Group properties from old_traps
    traps(ii).position = [old_traps(idx).position].';
    traps(ii).stiffness = [old_traps(idx).stiffness].';
    traps(ii).depth = [old_traps(idx).depth].';
    traps(ii).range = reshape([old_traps(idx).range], 2, []).';
    traps(ii).minmax_force = reshape([old_traps(idx).minmax_force], 2, []).';
    traps(ii).minmax_position = reshape([old_traps(idx).minmax_position], 2, []).';
    
    % Add group properties
    traps(ii).group_range = [min(traps(ii).range), max(traps(ii).range)];
    traps(ii).group_minmax_position = [traps(ii).minmax_position(1), traps(ii).minmax_position(end)];
    traps(ii).group_minmax_force = [traps(ii).minmax_force(1), traps(ii).minmax_force(end)];
    traps(ii).group_depth = min(abs(traps(ii).group_minmax_force));
  end
  
end

%% Discard traps that are too shallow

if ~isempty(p.Results.depth_threshold_e)
  max_depth = max(abs(force));
  drop_list = false(size(traps));

  for ii = 1:length(traps)

    if traps(ii).depth < p.Results.depth_threshold_e*max_depth
      drop_list(ii) = true;
    end
  end

  traps(drop_list) = [];
end

