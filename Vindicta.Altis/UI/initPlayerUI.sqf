// Add controls to the map
#include "..\OOP_Light\OOP_Light.h"
#include "ClientMapUI\ClientMapUI_Macros.h"
#include "UndercoverUI\UndercoverUI_Macros.h"
#include "defineddikcodes.inc"

diag_log "--- Initializing player UI";

// Create map controls
//_cfg = missionConfigFile >> "ClientMapUI";
//_idd = 12;
//[_cfg, _idd] call ui_fnc_createControlsFromConfig; // Disable this, it's a weird workaround anyway

private _array = [];
{
	private _className = configName _x; 
	private _idc = getNumber (_x >> "idc");
	private _newMapCtrl = (findDisplay 12) ctrlCreate [_className, _idc];
	_newMapCtrl setVariable ["__tag", _className];
	_newMapCtrl ctrlCommit 0;
	diag_log format ["UI: Created map control: %1 %2", _newMapCtrl, _className];
	_array pushBack _newMapCtrl;
} forEach ("isClass _x" configClasses (missionConfigFile >> "ClientMapUI" >> "Controls"));
uiNamespace setVariable ["__mapControls", _array];


g_rscLayerUndercover = ["rscLayerUndercover"] call BIS_fnc_rscLayer;	// register UndercoverUI layer
uiNamespace setVariable ["undercoverUI_display", displayNull];			
g_rscLayerUndercover cutRsc ["UndercoverUI", "PLAIN", -1, false];	

// Init abstract classes representing the UI
CALLSM0("PlayerListUI", "new");
gClientMapUI = NEW("ClientMapUI", []);
gInGameUI = NEW("InGameUI", []);
gBuildUI = NEW("BuildUI", []);

// In Game Menu event handler
(finddisplay 46) displayAddEventHandler ["KeyDown", {
	params ["_displayorcontrol", "_key", "_shift", "_ctrl", "_alt"];
	//diag_log format ["KeyDown: %1", _this];
	if (_key == DIK_U) then { // U key
		if (isNil "gInGameMenu" || {!IS_OOP_OBJECT(gInGameMenu)}) then {
			gInGameMenu = NEW("InGameMenu", []);
		};
		true
	} else {
		false
	};
}];

// Update player markers
[true] call ui_fnc_enablePlayerMarkers;