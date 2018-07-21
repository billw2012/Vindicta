#include "OOP_Light\OOP_Light.h"

[] spawn {
	private _group = NEW("Group", [WEST]);
	private _garrison = NEW("Garrison", [WEST]);
	private _n = 9;
	for "_i" from 0 to _n do {
		private _args = [tNato, 0, 1, 0, _group];
		private _unit = NEW("Unit", _args);
		private _valid = CALL_METHOD(_unit, "isValid", []);
		if (!_valid) then {
			DELETE(_unit);
			diag_log format ["Created an invalid unit!"];
		};
	};
	
	// Add the group to the garrison
	private _args = ["addGroup", [_group]];
	CALL_METHOD(_garrison, "postMethodAsync", _args);
	
	// Spawn the garrison
	CALL_METHOD(_garrison, "spawn", []);
	
	sleep 2;
	
	// Despawn the garrison
	CALL_METHOD(_garrison, "despawn", []);
};