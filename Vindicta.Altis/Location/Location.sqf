#define OOP_INFO
#define OOP_WARNING
#include "..\OOP_Light\OOP_Light.h"
#include "..\Message\Message.hpp"
#include "Location.hpp"
#include "..\MessageTypes.hpp"

#ifndef RELEASE_BUILD
#define DEBUG_LOCATION_MARKERS
#endif

#ifdef _SQF_VM
#undef DEBUG_LOCATION_MARKERS
#endif

/*
Class: Location
Location has garrisons at a static place and spawns units.

Author: Sparker 28.07.2018
*/
#ifdef DEBUG_LOCATION_MARKERS
#define UPDATE_DEBUG_MARKER T_CALLM("updateMarker", [])
#else
#define UPDATE_DEBUG_MARKER
#endif

#define pr private

CLASS("Location", ["MessageReceiverEx" ARG "Storable"])

	/* save */ 	VARIABLE_ATTR("type", [ATTR_SAVE]);						// String, location type
	/* save */ 	VARIABLE_ATTR("side", [ATTR_SAVE]);						// Side, location side
	/* save */ 	VARIABLE_ATTR("name", [ATTR_SAVE]);						// String, location name
	/* save */ 	VARIABLE_ATTR("children", [ATTR_SAVE]);					// Children of this location if it has any (e.g. police stations are children of cities)
	/* save */ 	VARIABLE_ATTR("parent", [ATTR_SAVE]); 					// Parent of the Location if it has one (e.g. parent of police station is its containing city location)
	/* save */ 	VARIABLE_ATTR("garrisons", [ATTR_SAVE]);				// Array of garrisons registered here
	/* save */ 	VARIABLE_ATTR("boundingRadius", [ATTR_SAVE]); 			// _radius for a circle border, sqrt(a^2 + b^2) for a rectangular border
	/* save */ 	VARIABLE_ATTR("border", [ATTR_SAVE]); 					// [center, a, b, angle, isRectangle, c]
	/* save */ 	VARIABLE_ATTR("borderPatrolWaypoints", [ATTR_SAVE]);	// Array for patrol waypoints along the border
	/* save */ 	VARIABLE_ATTR("useParentPatrolWaypoints", [ATTR_SAVE]);	// If true then use the parents patrol waypoints instead
	/* save */ 	VARIABLE_ATTR("allowedAreas", [ATTR_SAVE]); 			// Array with allowed areas
	/* save */ 	VARIABLE_ATTR("pos", [ATTR_SAVE]); 						// Position of this location
	/* save */	VARIABLE_ATTR("spawnPosTypes", [ATTR_SAVE]); 			// Array with spawn positions types
				VARIABLE("spawned"); 									// Is this location spawned or not
				VARIABLE("timer"); 										// Timer object which generates messages for this location
				VARIABLE("capacityInf"); 								// Infantry capacity
	/* save */	VARIABLE_ATTR("capacityCiv", [ATTR_SAVE]); 				// Civilian capacity
				VARIABLE("cpModule"); 									// civilian module, might be replaced by custom script
	/* save */	VARIABLE_ATTR("isBuilt", [ATTR_SAVE]); 					// true if this location has been build (used for roadblocks)
	/* save */	VARIABLE_ATTR("gameModeData", [ATTR_SAVE]);				// Custom object that the game mode can use to store info about this location
				VARIABLE("hasPlayers"); 								// Bool, means that there are players at this location, updated at each process call
				VARIABLE("hasPlayerSides"); 							// Array of sides of players at this location
				VARIABLE("buildingsOpen"); 							// Handles of buildings which can be entered (have buildingPos)
				VARIABLE("objects"); 							// Handles of objects which can't be entered and other objects
	/* save */	VARIABLE_ATTR("respawnSides", [ATTR_SAVE]); 			// Sides for which player respawn is enabled
				VARIABLE_ATTR("hasRadio", [ATTR_SAVE]); 				// Bool, means that this location has a radio
	/* save */	VARIABLE_ATTR("wasOccupied", [ATTR_SAVE]); 				// Bool, false at start but sets to true when garrisons are attached here

	// Variables which are set up only for saving process
	/* save */	VARIABLE_ATTR("savedObjects", [ATTR_SAVE]);		// Array of [className, posWorld, vectorDir, vectorUp] of objects

	STATIC_VARIABLE("all");

	// |                              N E W
	/*
	Method: new

	Parameters: _pos

	_pos - position of this location
	*/
	METHOD("new") {
		params [P_THISOBJECT, ["_pos", [0,0,0], [[]]] ];

		// Check existance of neccessary global objects
		if (isNil "gTimerServiceMain") exitWith {"[MessageLoop] Error: global timer service doesn't exist!";};
		if (isNil "gMessageLoopMain") exitWith {"[MessageLoop] Error: global location message loop doesn't exist!";};
		if (isNil "gLUAP") exitWith {"[MessageLoop] Error: global location unit array provider doesn't exist!";};

		T_SETV("side", CIVILIAN);
		SET_VAR_PUBLIC(_thisObject, "name", "noname");
		SET_VAR_PUBLIC(_thisObject, "garrisons", []);
		SET_VAR_PUBLIC(_thisObject, "boundingRadius", 50);
		SET_VAR_PUBLIC(_thisObject, "border", 50);
		T_SETV("borderPatrolWaypoints", []);
		T_SETV("useParentPatrolWaypoints", false);
		SET_VAR_PUBLIC(_thisObject, "pos", _pos);
		T_SETV("spawnPosTypes", []);
		T_SETV("spawned", false);
		T_SETV("capacityInf", 0);
		SET_VAR_PUBLIC(_thisObject, "capacityInf", 0);
		T_SETV("capacityCiv", 0);
		T_SETV("cpModule",objnull);
		SET_VAR_PUBLIC(_thisObject, "isBuilt", true); // Location is built at start, except for roadblocks, it's changed in setType function
		T_SETV("children", []);
		T_SETV("parent", NULL_OBJECT);
		SET_VAR_PUBLIC(_thisObject, "parent", NULL_OBJECT);
		SET_VAR_PUBLIC(_thisObject, "gameModeData", NULL_OBJECT);
		T_SETV("hasPlayers", false);
		T_SETV("hasPlayerSides", []);

		T_SETV("buildingsOpen", []);
		T_SETV("objects", []);

		T_SETV("respawnSides", []);

		SET_VAR_PUBLIC(_thisObject, "allowedAreas", []);
		SET_VAR_PUBLIC(_thisObject, "type", LOCATION_TYPE_UNKNOWN);

		T_SETV("hasRadio", false);

		SET_VAR_PUBLIC(_thisObject, "wasOccupied", false);
		T_SETV("wasOccupied", false);


		// Setup basic border
		CALLM2(_thisObject, "setBorder", "circle", [20]);
		
		T_SETV("timer", NULL_OBJECT);


		//Push the new object into the array with all locations
		private _allArray = GET_STATIC_VAR("Location", "all");
		_allArray pushBack _thisObject;
		PUBLIC_STATIC_VAR("Location", "all");

		// Register at game mode so that it gets saved
		if (!isNil {gGameMode}) then {
			CALLM1(gGameMode, "registerLocation", _thisObject);
		};

		UPDATE_DEBUG_MARKER;
	} ENDMETHOD;

	// |                 S E T   D E B U G   N A M E
	/*
	Method: setName
	Sets debug name of this MessageLoop.

	Parameters: _name

	_name - String

	Returns: nil
	*/
	METHOD("setName") {
		params [P_THISOBJECT, ["_name", "", [""]]];
		SET_VAR_PUBLIC(_thisObject, "name", _name);
	} ENDMETHOD;

	METHOD("setCapacityInf") {
		params [P_THISOBJECT, ["_capacityInf", 0, [0]]];
		T_SETV("capacityInf", _capacityInf);		
		SET_VAR_PUBLIC(_thisObject, "capacityInf", _capacityInf);
	} ENDMETHOD;

	METHOD("setCapacityCiv") {
		params [P_THISOBJECT, ["_capacityCiv", 0, [0]]];
		T_SETV("capacityCiv", _capacityCiv);
		if(T_GETV("type") isEqualTo LOCATION_TYPE_CITY && _capacityCiv > 0)then{
			private _cpModule = [+T_GETV("pos"),T_GETV("border"), _capacityCiv] call CivPresence_fnc_init;
			if(!isNull _cpModule) then {
				T_SETV("cpModule",_cpModule);
			} else {
				T_SETV("cpModule", objNull);
			};
		};

	} ENDMETHOD;

	METHOD("setSide") {
		params [P_THISOBJECT, ["_side", EAST, [EAST]]];
		T_SETV("side", _side);
	} ENDMETHOD;

	/*
	Method: addChild
	Adds a child location to this location (also sets the childs parent).
	Child must not belong to another location already.
	*/
	METHOD("addChild") {
		params [P_THISOBJECT, P_OOP_OBJECT("_childLocation")];
		ASSERT_OBJECT_CLASS(_childLocation, "Location");
		ASSERT_MSG(IS_NULL_OBJECT(GETV(_childLocation, "parent")), "Location is already assigned to another parent");
		T_GETV("children") pushBack _childLocation;
		//SETV(_childLocation, "parent", _thisObject);
		SET_VAR_PUBLIC(_childLocation, "parent", _thisObject);
		nil
	} ENDMETHOD;

	/*
	Method: addStaticObject
	Adds an object to this location (building or another object)
	
	Arguments: _hObject
	*/
	METHOD("addObject") {
		params [P_THISOBJECT, P_OBJECT("_hObject"), P_BOOL_DEFAULT_TRUE("_addSpawnPos")];

		//OOP_INFO_1("ADD OBJECT: %1", _hObject);

		private _type = typeOf _hObject;
		private _countBP = count (_hObject buildingPos -1);

		if (_countBP > 0) then {
			T_GETV("buildingsOpen") pushBackUnique _hObject;
			if (_addSpawnPos) then {
				T_CALLM1("addSpawnPosFromBuilding", _hObject);
			};
		} else {
			T_GETV("objects") pushBackUnique _hObject;
		};

		// Check how it affects the location's infantry capacity
		private _index = location_b_capacity findIf {_type in _x#0};
		private _cap = 0;
		if (_index != -1) then {
			_cap = location_b_capacity#_index#1;
		} else {
			_cap = _countBP;
		};

		// Increase infantry capacity
		pr _capnew = T_GETV("capacityInf") + _cap;
		T_SETV("capacityInf", _capnew);		
		SET_VAR_PUBLIC(_thisObject, "capacityInf", _capnew);

		// Check if it enabled radio functionality for the location
		private _index = location_bt_radio find _type;
		if (_index != -1) then {
			T_SETV("hasRadio", _index != -1);
			// Init radio object actions
			CALLSM1("Location", "initRadioObject", _hObject);
		};

		_index = location_bt_medical find _type;
		if (_index != -1) then {
			CALLSM1("Location", "initMedicalObject", _hObject);
		};
	} ENDMETHOD;


	#ifdef DEBUG_LOCATION_MARKERS
	METHOD("updateMarker") {
		params [P_THISOBJECT];

		T_PRVAR(type);
		deleteMarker _thisObject;
		deleteMarker (_thisObject + "_label");
		T_PRVAR(pos);

		if(count _pos > 0) then {

			private _mrk = createmarker [_thisObject, _pos];
			_mrk setMarkerType (switch T_GETV("type") do {
				case LOCATION_TYPE_ROADBLOCK: { "mil_triangle" };
				case LOCATION_TYPE_BASE: { "mil_circle" };
				case LOCATION_TYPE_OUTPOST: { "mil_box" };
				case LOCATION_TYPE_CITY: { "mil_marker" };
				case LOCATION_TYPE_POLICE_STATION: { "mil_warning" };
				default { "mil_dot" };
			});
			_mrk setMarkerColor "ColorYellow";
			_mrk setMarkerAlpha 1;
			_mrk setMarkerText "";

			T_PRVAR(border);
			if(_border isEqualType []) then {
				_mrk setMarkerDir _border#2;
			};
			
			if(not (_type in [LOCATION_TYPE_ROADBLOCK])) then {
				_mrk = createmarker [_thisObject + "_label", _pos vectorAdd [-200, -200, 0]];
				_mrk setMarkerType "Empty";
				_mrk setMarkerColor "ColorYellow";
				_mrk setMarkerAlpha 1;
				T_PRVAR(name);
				T_PRVAR(type);
				_mrk setMarkerText format ["%1 (%2)(%3)", _thisObject, _name, _type];
			};
		};
	} ENDMETHOD;
	#endif
	
	// |                            D E L E T E                             |
	/*
	Method: delete
	*/
	METHOD("delete") {
		params [P_THISOBJECT];

		// Remove the timer
		private _timer = GET_VAR(_thisObject, "timer");
		if (!IS_NULL_OBJECT(_timer)) then {
			DELETE(_timer);
			T_SETV("timer", nil);
		};

		//Remove this unit from array with all units
		private _allArray = GET_STATIC_VAR("Location", "all");
		_allArray deleteAt (_allArray find _thisObject);
		PUBLIC_STATIC_VAR("Location", "all");

		#ifdef DEBUG_LOCATION_MARKERS
		deleteMarker _thisObject;
		deleteMarker _thisObject + "_label";
		#endif
	} ENDMETHOD;


	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                               G E T T I N G   M E M B E R   V A L U E S
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


	// |                            G E T   A L L
	/*
	Method: (static)getAll
	Returns an array of all locations.

	Returns: Array of location objects
	*/
	STATIC_METHOD("getAll") {
		private _all = GET_STATIC_VAR("Location", "all");
		private _return = +_all;
		_return
	} ENDMETHOD;


	// |                            G E T   P O S                           |
	/*
	Method: getPos
	Returns position of this location

	Returns: Array, position
	*/
	METHOD("getPos") {
		params [ P_THISOBJECT ];
		GETV(_thisObject, "pos")
	} ENDMETHOD;

	
	// |                         I S   S P A W N E D                        |
	/*
	Method: isSpawned
	Is the location spawned?

	Returns: bool
	*/
	METHOD("isSpawned") {
		params [ P_THISOBJECT ];
		T_GETV("spawned")
	} ENDMETHOD;

	/*
	Method: hasPlayers
	Returns true if there are any players in the location area.
	The actual value gets updated infrequently, on timer.

	Returns: Bool
	*/
	METHOD("hasPlayers") {
		params [P_THISOBJECT];
		T_GETV("hasPlayers")
	} ENDMETHOD;

	/*
	Method: getPlayerSides
	Returns array of sides of players within this location.

	Returns: Bool
	*/
	METHOD("getPlayerSides") {
		params [P_THISOBJECT];
		T_GETV("hasPlayerSides")
	} ENDMETHOD;

	// |               G E T   P A T R O L   W A Y P O I N T S
	/*
	Method: getPatrolWaypoints
	Returns array with positions for patrol waypoints.

	Returns: Array of positions
	*/
	METHOD("getPatrolWaypoints") {
		params [ P_THISOBJECT ];
		if(T_GETV("useParentPatrolWaypoints")) then {
			private _parent = T_GETV("parent");
			CALLM0(_parent, "getPatrolWaypoints");
		} else {
			T_GETV("borderPatrolWaypoints");
		}
	} ENDMETHOD;

	// |                  G E T   M E S S A G E   L O O P
	METHOD("getMessageLoop") { //Derived classes must implement this method
		gMessageLoopMain
	} ENDMETHOD;

	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	// |                               S E T T I N G   M E M B E R   V A L U E S
	// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	METHOD("registerGarrison") {
		params ["_thisObject", ["_gar", "", [""]]];
		
		pr _gars = T_GETV("garrisons");
		if (! (_gar in _gars)) then {
			_gars pushBackUnique _gar;
			PUBLIC_VAR(_thisObject, "garrisons");
			REF(_gar);

			// TODO: work out how this should work properly? This isn't terrible but we will
			// have resource constraints etc. Probably it should be in Garrison.process to build
			// at location when they have resources?
			iF(!T_GETV("isBuilt")) then {
				T_CALLM("build", []);
			};

			// Update player respawn rules
			pr _gmdata = T_GETV("gameModeData");
			if (!IS_NULL_OBJECT(_gmdata)) then {
				CALLM0(_gmdata, "updatePlayerRespawn");
			};	
		};

		// From now on this place is occupied or was occupied
		SET_VAR_PUBLIC(_thisObject, "wasOccupied", true);
	} ENDMETHOD;
	
	METHOD("unregisterGarrison") {
		params ["_thisObject", ["_gar", "", [""]]];
		
		pr _gars = T_GETV("garrisons");
		if (_gar in _gars) then {
			_gars deleteAt (_gars find _gar);
			PUBLIC_VAR(_thisObject, "garrisons");
			UNREF(_gar);

			// Update player respawn rules
			pr _gmdata = T_GETV("gameModeData");
			if (!IS_NULL_OBJECT(_gmdata)) then {
				CALLM0(_gmdata, "updatePlayerRespawn");
			};
		};
	} ENDMETHOD;
	
	
	METHOD("getGarrisons") {
		params ["_thisObject", ["_side", CIVILIAN, [CIVILIAN]]];
		
		if (_side == CIVILIAN) then {
			+T_GETV("garrisons")
		} else {
			T_GETV("garrisons") select {CALLM0(_x, "getSide") == _side}
		};
	} ENDMETHOD;
	
	
	METHOD("getGarrisonsRecursive") {
		params ["_thisObject", ["_side", CIVILIAN, [CIVILIAN]]];
		private _myGarrisons = if (_side == CIVILIAN) then {
			+T_GETV("garrisons")
		} else {
			T_GETV("garrisons") select {CALLM0(_x, "getSide") == _side}
		};
		T_PRVAR(children);
		{
			_myGarrisons = _myGarrisons + CALLM(_x, "getGarrisonsRecursive", [_side]);
		} forEach _children;
		_myGarrisons
	} ENDMETHOD;

	/*
	Method: getType
	Returns type of this location

	Returns: String
	*/
	METHOD("getType") {
		params [ P_THISOBJECT ];
		GET_VAR(_thisObject, "type")
	} ENDMETHOD;

	/*
	Method: getType
	Returns a nice string associated with this location type

	Returns: String
	*/
	STATIC_METHOD("getTypeString") {
		params [P_THISCLASS, "_type"];
		switch (_type) do {
			case LOCATION_TYPE_OUTPOST: {"Outpost"};
			case LOCATION_TYPE_CAMP: {"Camp"};
			case LOCATION_TYPE_BASE: {"Base"};
			case LOCATION_TYPE_UNKNOWN: {"Unknown"};
			case LOCATION_TYPE_CITY: {"City"};
			case LOCATION_TYPE_OBSERVATION_POST: {"Observation post"};
			case LOCATION_TYPE_ROADBLOCK: {"Roadblock"};
			case LOCATION_TYPE_POLICE_STATION: {"Police Station"};
			case LOCATION_TYPE_AIRPORT: {"Airport"};
			default {"ERROR LOC TYPE"};
		};
	} ENDMETHOD;

	/*
	Method: getName

	Returns: String
	*/
	METHOD("getName") {
		params [P_THISOBJECT];
		T_GETV("name")
	} ENDMETHOD;

	/*
	Method: getDisplayName

	Returns a display name to show in UIs. Format is: <type> <name>, like "Camp Potato".
	*/
	METHOD("getDisplayName") {
		params [P_THISOBJECT];
		pr _name = T_GETV("name");
		_name
	} ENDMETHOD;
	
	/*
	Method: getSide
	Returns side of the garrison that controls this location.

	Returns: Side, or Civilian if there is no garrison
	*/
	/*
	METHOD("getSide") {
		params [ "_thisObject" ];
		pr _gar = T_GETV("garrisonMilMain");
		if (_gar == "") then {
			CIVILIAN
		} else {
			CALLM0(_gar, "getSide");
		};
	} ENDMETHOD;
	*/

	/*
	Method: getCapacityInf
	Returns type of this location

	Returns: Integer
	*/
	METHOD("getCapacityInf") {
		params [ P_THISOBJECT ];
		GET_VAR(_thisObject, "capacityInf")
	} ENDMETHOD;

	/*
	Method: getCapacityCiv
	Returns type of this location

	Returns: Integer
	*/
	METHOD("getCapacityCiv") {
		params [ P_THISOBJECT ];
		GET_VAR(_thisObject, "capacityCiv")
	} ENDMETHOD;
	
	/*
	Method: getOpenBuildings
	Returns an array of object handles of buildings in which AI infantry can enter (they must return buildingPos positions)
	*/
	METHOD("getOpenBuildings") {
		params [P_THISOBJECT];
		T_GETV("buildingsOpen") select {damage _x < 0.98}
	} ENDMETHOD;

	/*
	Method: getGameModeData
	Returns gameModeData object
	*/
	METHOD("getGameModeData") {
		params [P_THISOBJECT];
		T_GETV("gameModeData")
	} ENDMETHOD;

	/*
	Method: hasRadio
	Returns true if this location has any object of the radio object types
	*/
	METHOD("hasRadio") {
		params [P_THISOBJECT];
		T_GETV("hasRadio")
	} ENDMETHOD;

	/*
	Method: wasOccupied
	Returns value of wasOccupied variable.
	*/
	METHOD("wasOccupied") {
		params [P_THISOBJECT];
		T_GETV("wasOccupied")
	} ENDMETHOD;

	STATIC_METHOD("findRoadblocks") {
		params [P_THISCLASS, P_POSITION("_pos")];

		//private _pos = T_CALLM("getPos", []);

		private _roadblockPositions = [];

		// Get near roads and sort them far to near, taking width into account
		private _roads_remaining = ((_pos nearRoads 1500) select {
			pr _roadPos = getPosASL _x;
			(_roadPos distance _pos > 400) &&			// Pos is far enough
			((count (_x nearRoads 20)) < 3) &&	// Not too many roads because it might mean a crossroad
			(count (roadsConnectedTo _x) == 2)			// Connected to two roads, we don't need end road elements
			// Let's not create roadblocks inside other locations
			//{count (CALLSM1("Location", "getLocationsAt", _roadPos)) == 0}	// There are no locations here
		}) apply {
			pr _width = [_x, 0.2, 20] call misc_fnc_getRoadWidth;
			pr _dist = position _x distance _pos;
			// We value wide roads more, also we value roads further away more
			[_dist*_width*_width*_width, _dist, _x]
		};

		// Sort roads by their value metric
		_roads_remaining sort DESCENDING; // We sort by the value metric!
		private _itr = 0;

		while {count _roads_remaining > 0 and _itr < 4} do {
			(_roads_remaining#0) params ["_valueMetric", "_dist", "_road"];
			private _roadscon = (roadsConnectedto _road) apply { [position _x distance _pos, _x] };
			_roadscon sort DESCENDING;
			if (count _roadscon > 0) then {
				private _roadcon = _roadscon#0#1;
				//private _dir = _roadcon getDir _road;				
				private _roadblock_pos = getPosASL _road; //[getPos _road, _x, _dir] call BIS_Fnc_relPos;
					
				_roadblockPositions pushBack _roadblock_pos; 
			};

			_roads_remaining = _roads_remaining select {
				( (getPos _road) distance (getPos (_x select 2)) > 300) &&
				{((getPos _road) vectorDiff _pos) vectorCos ((getPos (_x select 2)) vectorDiff _pos) < 0.3}
			};
			_itr = _itr + 1;
		};

		_roadblockPositions
	} ENDMETHOD;

	/*
	Method: getBorder
	gets border parameters of this location

	Returns: [center, a, b, angle, isRectangle, c]
	*/
	METHOD("getBorder") {
		params [P_THISOBJECT];
		T_GETV("border")
	} ENDMETHOD;

	/*
	Method: setType
	Set the Type.

	Parameters: _type

	_type - String

	Returns: nil
	*/
	METHOD("setType") {
		params [P_THISOBJECT, ["_type", "", [""]]];
		SET_VAR_PUBLIC(_thisObject, "type", _type);

		// Create a timer object if the type of the location is a city or a roadblock
		//if (_type in [LOCATION_TYPE_CITY, LOCATION_TYPE_ROADBLOCK]) then {
		
			T_CALLM0("initTimer");
			
		//};

		if (_type == LOCATION_TYPE_ROADBLOCK) then {
			SET_VAR_PUBLIC(_thisObject, "isBuilt", false); // Unbuild this
		};

		T_CALLM("updateWaypoints", []);

		UPDATE_DEBUG_MARKER;
	} ENDMETHOD;

	METHOD("initTimer") {
		params [P_THISOBJECT];
		
		// Delete previous timer if we had it
		pr _timer = T_GETV("timer");
		if (!IS_NULL_OBJECT(_timer)) then {
			DELETE(_timer);
		};

		// Create timer object
		private _msg = MESSAGE_NEW();
		_msg set [MESSAGE_ID_DESTINATION, _thisObject];
		_msg set [MESSAGE_ID_SOURCE, ""];
		_msg set [MESSAGE_ID_DATA, 0];
		_msg set [MESSAGE_ID_TYPE, LOCATION_MESSAGE_PROCESS];
		private _args = [_thisObject, 1, _msg, gTimerServiceMain]; //["_messageReceiver", "", [""]], ["_interval", 1, [1]], ["_message", [], [[]]], ["_timerService", "", [""]]
		private _timer = NEW("Timer", _args);
		SET_VAR(_thisObject, "timer", _timer);
	} ENDMETHOD;

	// /*
	// Method: getCurrentGarrison
	// Returns the current garrison attached to this location

	// Returns: <Garrison> or "" if there is no current garrison
	// */
	// METHOD("getCurrentGarrison") {
	// 	params [ P_THISOBJECT ];

	// 	private _garrison = GETV(_thisObject, "garrisonMilAA");
	// 	if (_garrison == "") then { _garrison = GETV(_thisObject, "garrisonMilMain"); };
	// 	if (_garrison == "") then { OOP_WARNING_1("No garrison found for location %1", _thisObject); };
	// 	_garrison
	// } ENDMETHOD;

	/*
	Method: (static)findSafePosOnRoad
	Finds an empty position for a vehicle class name on road close to specified position.

	Parameters: _startPos 
	_startPos - start position ATL where to start searching for a position.

	Returns: Array, [_pos, _dir]
	*/
	#define ROAD_DIR_LIMIT 15

	STATIC_METHOD("findSafePosOnRoad") {
		params ["_thisClass", ["_startPos", [], [[]]], ["_className", "", [""]] ];

		// Try to find a safe position on a road for this vehicle
		private _found = false;
		private _searchRadius = 100;
		pr _return = [];
		while {!_found} do {
			private _roads = _startPos nearRoads _searchRadius;
			if (count _roads < 3) then {
				// Search for more roads at the next iteration
				_searchRadius = _searchRadius * 2;
			} else {
				_roads = _roads apply { [_x distance2D _startPos, _x] };
				_roads sort ASCENDING;
				private _i = 0;
				while {_i < count _roads && !_found} do {
					(_roads select _i) params ["_dist", "_road"];
					private _rct = roadsConnectedTo _road;
					// TODO: we can preprocess spawn locations better than this probably.
					// Need a connected road (this is guaranteed probably?)
					// Avoid spawning too close to a junction
					if(count _rct > 0) then {
						private _dir = _road getDir _rct#0;
						private _count = {
								private _rctOther = roadsConnectedTo _x;
								if(count _rctOther == 0) then {
									false
								} else {
									private _dirOther = _x getDir _rctOther#0;
									private _relDir = _dir - _dirOther;
									if(_relDir < 0) then { _relDir = _relDir + 360 };
									(_relDir > ROAD_DIR_LIMIT and _relDir < 180-ROAD_DIR_LIMIT) or (_relDir > 180+ROAD_DIR_LIMIT and _relDir < 360-ROAD_DIR_LIMIT)
								};
							} count ((getPos _road) nearRoads 25);
						if ( _count == 0 ) then {
							// Check position if it's safe

							private _width = [_road, 1, 8] call misc_fnc_getRoadWidth;
							// Move to the edge
							private _pos = [getPos _road, _width - 3, _dir + (selectRandom [90, 270]) ] call BIS_Fnc_relPos;
							// Move up and down the street a bit
							_pos = [_pos, _width * 0.5, _dir + (selectRandom [0, 180]) ] call BIS_Fnc_relPos;
							// Perturb the direction a bit
							private _dirPert = _dir + random [-20, 0, 20] + (selectRandom [0, 180]);
							// Perturb the position a bit
							private _posPert = _pos vectorAdd [random [-1, 0, 1], random [-1, 0, 1], 0];
							if(CALLSM3("Location", "isPosEvenSafer", _posPert, _dirPert, _className)) then {
								_return = [_posPert, _dirPert];
								_found = true;
							};
						};
					};
					_i = _i + 1;
				};
				if (!_found) then {
					// Failed to find a position here, increase the radius
					_searchRadius = _searchRadius * 3;
				};
			};			
		};

		_return
	} ENDMETHOD;

	/*
	Method: (static)findSafePos
	Finds a safe spawn position for a vehicle with given class name.


	Parameters: _className, _pos

	_className - String, vehicle class name
	_startPos - position where to start searching from

	Returns: [_pos, _dir]
	*/
	STATIC_METHOD("findSafeSpawnPos") {
		params ["_thisClass", ["_className", "", [""]], ["_startPos", [], [[]]]];

		private _found = false;
		private _searchRadius = 50;
		pr _posAndDir = [_startPos, 0];
		while {!_found and _searchRadius < 2000} do {
			for "_i" from 0 to 16 do {
				pr _pos = _startPos vectorAdd [-_searchRadius + random(2*_searchRadius), -_searchRadius + random(2*_searchRadius), 0];
				if (CALLSM3("Location", "isPosSafe", _pos, 0, _className) && ! (surfaceIsWater _pos)) exitWith {
					_posAndDir = [_pos, 0];
					_found = true;
				};
			};
			
			if (!_found) then {
				// Search in a larger area at the next iteration
				_searchRadius = _searchRadius * 2;
			};			
		};

		_posAndDir
	} ENDMETHOD;


	/*
	Method: countAvailableUnits
	Returns an number of current units of this location

	Returns: Integer
	*/
	METHOD("countAvailableUnits") {
		params [ P_THISOBJECT, P_SIDE("_side") ];

		// TODO: Yeah we need mutex here!
		private _garrisons = T_CALLM("getGarrisons", [_side]);
		if (count _garrisons == 0) exitWith { 0 };
		private _sum = 0;
		{
			_sum = _sum + CALLM0(_x, "countAllUnits");
		} forEach _garrisons;
		_sum
	} ENDMETHOD;

	/*
	Method: setBorder
	Sets border parameters for this location

	Arguments:
	_type - "circle" or "rectange"
	_data	- for "circle":
		_radius
			- for "rectangle":
		[_a, _b, _dir] - rectangle dimensions and direction

	*/
	METHOD("setBorder") {
		params [P_THISOBJECT, P_STRING("_type"), ["_data", [50], [0, []]] ];

		switch (_type) do {
			case "circle" : {
				_data params [ ["_radius", 0, [0] ] ];
				SET_VAR_PUBLIC(_thisObject, "boundingRadius", _radius);
				pr _border = [T_GETV("pos"), _radius, _radius, 0, false, -1]; // [center, a, b, angle, isRectangle, c]
				SET_VAR_PUBLIC(_thisObject, "border", _border);
			};
			
			case "rectangle" : {
				_data params ["_a", "_b", "_dir"];
				private _radius = sqrt(_a*_a + _b*_b);
				pr _border = [T_GETV("pos"), _a, _b, _dir, true, -1]; // [center, a, b, angle, isRectangle, c]
				SET_VAR_PUBLIC(_thisObject, "border", _border);
				SET_VAR_PUBLIC(_thisObject, "boundingRadius", _radius);
			};
			
			default {
				diag_log format ["[Location::setBorder] Error: wrong border type: %1, location: %2", _type, GET_VAR(_thisObject, "name")];
			};
		};

		T_CALLM("updateWaypoints", []);
	} ENDMETHOD;

	

	// File-based methods

	// Handles messages
	METHOD_FILE("handleMessageEx", "Location\handleMessageEx.sqf");

	// Sets border parameters
	METHOD_FILE("updateWaypoints", "Location\updateWaypoints.sqf");

	// Checks if given position is inside the border
	METHOD_FILE("isInBorder", "Location\isInBorder.sqf");

	// Initializes the location from editor-plased objects
	METHOD_FILE("initFromEditor", "Location\initFromEditor.sqf");

	// Adds a spawn position
	METHOD_FILE("addSpawnPos", "Location\addSpawnPos.sqf");

	// Adds multiple spawn positions from a building
	METHOD_FILE("addSpawnPosFromBuilding", "Location\addSpawnposFromBuilding.sqf");

	// Calculates infantry capacity based on buildings at this location
	// It's old and better not to use it
	METHOD_FILE("calculateInfantryCapacity", "Location\calculateInfantryCapacity.sqf");

	// Gets a spawn position to spawn some unit
	METHOD_FILE("getSpawnPos", "Location\getSpawnPos.sqf");

	// Returns a random position within border
	METHOD_FILE("getRandomPos", "Location\getRandomPos.sqf");

	// Returns how many units of this type and group type this location can hold
	METHOD_FILE("getUnitCapacity", "Location\getUnitCapacity.sqf");

	// Checks if given position is safe to spawn a vehicle here
	STATIC_METHOD_FILE("isPosSafe", "Location\isPosSafe.sqf");

	// Checks if given position is even safer to spawn a vehicle here (conservative, doesn't allow spawning 
	// in buildings etc.)
	STATIC_METHOD_FILE("isPosEvenSafer", "Location\isPosEvenSafer.sqf");

	// Returns the nearest location to given position and distance to it
	STATIC_METHOD_FILE("getNearestLocation", "Location\getNearestLocation.sqf");

	// Returns location that has its border overlapping given position
	STATIC_METHOD_FILE("getLocationAtPos", "Location\getLocationAtPos.sqf");

	// Returns an array of locations that have their border overlapping given position
	STATIC_METHOD_FILE("getLocationsAtPos", "Location\getLocationsAtPos.sqf");

	// Adds an allowed area
	METHOD_FILE("addAllowedArea", "Location\addAllowedArea.sqf");

	// Checks if player is in any of the allowed areas
	METHOD_FILE("isInAllowedArea", "Location\isInAllowedArea.sqf");

	// Handle PROCESS message
	METHOD_FILE("process", "Location\process.sqf");

	// Spawns the location
	METHOD_FILE("spawn", "Location\spawn.sqf");

	// Despawns the location
	METHOD_FILE("despawn", "Location\despawn.sqf");

	// Builds the location
	METHOD_FILE("build", "Location\build.sqf");

	/*
	Method: setBorder
	Getter for isBuilt
	*/
	METHOD("isBuilt") { params [P_THISOBJECT]; T_GETV("isBuilt") } ENDMETHOD ;

	/*
	Method: enablePlayerRespawn
	
	Parameters: _side, _enable
	*/
	METHOD("enablePlayerRespawn") {
		params [P_THISOBJECT, P_SIDE("_side"), P_BOOL("_enable")];

		pr _markName = switch (_side) do {
			case WEST: {"respawn_west"};
			case EAST: {"respawn_east"};
			case INDEPENDENT: {"respawn_guerrila"};
			default {"respawn_civilian"};
		};

		pr _respawnSides = T_GETV("respawnSides");

		if (_enable) then {

			pr _pos = T_GETV("pos");
			pr _type = T_GETV("type");
			
			// Find an alternative spawn place for a city or police station
			if (_type == LOCATION_TYPE_CITY) then {
				// Find appropriate player spawn point, not to near and not to far from the police station, inside a house
				private _nearbyHouses = (_pos nearObjects ["House", 200]) apply { [_pos distance getPos _x, _x] };
				_nearbyHouses sort false; // Descending
				private _spawnPos = _pos vectorAdd [100, 100, 0];
				{
					_x params ["_dist", "_building"];
					private _positions = _building buildingPos -1;
					if(count _positions > 0) exitWith {
						_spawnPos = selectRandom _positions;
					}
				} forEach _nearbyHouses;
				_pos = _spawnPos;
			};

			createMarker [_markName + _thisObject, _pos];

			_respawnSides pushBackUnique _side;
		} else {
			deleteMarker (_markName + _thisObject);

			_respawnSides deleteAt (_respawnSides find _side);
		};
	} ENDMETHOD;

	/*
	Method: playerRespawnEnabled

	Parameters: _side

	Returns true if player respawn is enabled for this side
	*/
	METHOD("playerRespawnEnabled") {
		params [P_THISOBJECT, P_SIDE("_side")];
		_side in T_GETV("respawnSides")
	} ENDMETHOD;

	/*
	Method: iterates through objects inside the border and updated the buildings variable
	Parameters: _filter - String, each object will be tested with isKindOf command against this filter
	Returns: nothing
	*/
	METHOD("processObjectsInArea") {
		params [P_THISOBJECT, ["_filter", "House", [""]], ["_addSpecialObjects", false, [false]]];

		// Setup location's spawn positions
		private _radius = GET_VAR(_thisObject, "boundingRadius");
		private _locPos = GET_VAR(_thisObject, "pos");
		private _no = _locPos nearObjects _radius;

		//OOP_INFO_1("PROCESS OBJECTS IN AREA: %1", _this);
		//OOP_INFO_2("	Radius: %1, pos: %2", _radius, _locPos);
		//OOP_INFO_1("	Objects: %1", _no);

		// forEach _nO;
		{
			_object = _x;
			//OOP_INFO_1("	Object: %1", _object);
			if(T_CALLM1("isInBorder", _object)) then {
				//OOP_INFO_0("	In border");
				if (_object isKindOf _filter) then {
					//OOP_INFO_0("		Is kind of filter");
					T_CALLM1("addObject", _object);
				} else {
					//OOP_INFO_0("    	Does not match filter");
					pr _type = typeOf _object;
					if (_addSpecialObjects) then {
						// Check if this object has capacity defined
						//   or adds radio functionality
						//  or... 
						private _index = location_b_capacity findIf {_type in _x#0};
						private _indexRadio = location_bt_radio find _type;
						if (_index != -1 || _indexRadio != -1) then {
							//OOP_INFO_0("    	Is a special object");
							T_CALLM1("addObject", _object);
						};
					};
				};
			};
		} forEach _nO;
	} ENDMETHOD;

	/*
	Method: addSpawnPosFromBuildings
	Iterates its buildings and adds spawn positions from them
	*/
	METHOD("addSpawnPosFromBuildings") {
		params [P_THISOBJECT];
		pr _buildings = T_GETV("buildingsOpen");
		{
			T_CALLM1("addSpawnPosFromBuilding", _x);
		} forEach _buildings;
	} ENDMETHOD;

	/*
	Method: (static)nearLocations
	Returns an array of locations that are _radius meters from _pos. Distance is checked in 2D mode.

	Parameters: _pos, _radius

	Returns: nil
	*/
	STATIC_METHOD("nearLocations") {
		params [P_THISCLASS, P_ARRAY("_pos"), P_NUMBER("_radius")];
		GET_STATIC_VAR("Location", "all") select {
			(GETV(_x, "pos") distance2D _pos) < _radius
		}
	} ENDMETHOD;

	// Runs "process" of locations within certain distance from the point
	// Actually it only checks cities and roadblocks now, because other locations don't need to have "process" method to be called on them
	// Public, thread-safe
	STATIC_METHOD("processLocationsNearPos") {
		params [P_THISCLASS, P_POSITION("_pos")];
		
		pr _args = ["Location", "_processLocationsNearPos", [_pos]];
		CALLM2(gMessageLoopMainManager, "postMethodAsync", "callStaticMethodInThread", _args);
	} ENDMETHOD;

	// Private, thread-unsafe
	STATIC_METHOD("_processLocationsNearPos") {
		params [P_THISCLASS, P_POSITION("_pos")];
		pr _locs = CALLSM2("Location", "nearLocations", _pos, 1500) select { // todo arbitrary number for now
			(GETV(_x, "type") in [LOCATION_TYPE_CITY, LOCATION_TYPE_ROADBLOCK])
		};

		{
			CALLM0(_x, "process");
		} forEach _locs;
	} ENDMETHOD;



	// Initalization of different objects
	STATIC_METHOD("initMedicalObject") {
		params [P_THISCLASS, P_OBJECT("_object")];

		if (!isServer) exitWith {
			OOP_ERROR_0("initMedicalObject must be called on server!");
		};

		// Generate a JIP ID
		private _ID = 0;
		if(isNil "location_medical_nextID") then {
			location_medical_nextID = 0;
			_ID = 0;
		} else {
			_ID = location_medical_nextID;
		};
		location_medical_nextID = location_medical_nextID + 1;

		private _JIPID = format ["loc_medical_jip_%1", _ID];
		_object setVariable ["loc_medical_jip", _JIPID];

		// Add an event handler to delete the init from the JIP queue when the object is gone
		_object addEventHandler ["Deleted", {
			params ["_entity"];
			private _JIPID = _entity getVariable "loc_medical_jip";
			if (isNil "_JIPID") exitWith {
				OOP_ERROR_1("loc_medical_jip not found for object %1", _entity);
			};
			remoteExecCall ["", _JIPID]; // Remove it from the queue
		}];

		REMOTE_EXEC_CALL_STATIC_METHOD("Location", "initMedicalObjectAction", [_object], 0, _JIPID); // global, JIP

	} ENDMETHOD;

	STATIC_METHOD("initMedicalObjectAction") {
		params [P_THISCLASS, P_OBJECT("_object")];

		OOP_INFO_1("INIT MEDICAL OBJECT ACTION: %1", _object);

		// Estimate usage radius
		private _radius = (sizeof typeof _object) + 5;

		_object addAction ["<img size='1.5' image='\A3\ui_f\data\IGUI\Cfg\Actions\heal_ca.paa'/>  Heal Yourself", // title
			{
				player setdamage 0;
				[player] call ace_medical_treatment_fnc_fullHealLocal;
				player playMove "AinvPknlMstpSlayWrflDnon_medic";
			}, 
			0, // Arguments
			100, // Priority
			true, // ShowWindow
			false, //hideOnUse
			"", //shortcut
			"true", //condition
			_radius, //radius
			false, //unconscious
			"", //selection
			""]; //memoryPoint
	} ENDMETHOD;

	STATIC_METHOD("initRadioObject") {
		params [P_THISCLASS, P_OBJECT("_object")];

		if (!isServer) exitWith {
			OOP_ERROR_0("initRadioObject must be called on server!");
		};

		// Generate a JIP ID
		private _ID = 0;
		if(isNil "location_radio_nextID") then {
			location_radio_nextID = 0;
			_ID = 0;
		} else {
			_ID = location_radio_nextID;
		};
		location_radio_nextID = location_radio_nextID + 1;

		private _JIPID = format ["loc_radio_jip_%1", _ID];
		_object setVariable ["loc_radio_jip", _JIPID];

		// Add an event handler to delete the init from the JIP queue when the object is gone
		_object addEventHandler ["Deleted", {
			params ["_entity"];
			private _JIPID = _entity getVariable "loc_radio_jip";
			if (isNil "_JIPID") exitWith {
				OOP_ERROR_1("loc_radio_jip not found for object %1", _entity);
			};
			remoteExecCall ["", _JIPID]; // Remove it from the queue
		}];

		//OOP_INFO_2("INIT RADIO OBJECT: %1 at %2", _object, getPos _object);
		//OOP_INFO_1("  JIP ID: %1", _JIPID);

		REMOTE_EXEC_CALL_STATIC_METHOD("Location", "initRadioObjectAction", [_object], 0, _JIPID); // global, JIP
	} ENDMETHOD;

	STATIC_METHOD("initRadioObjectAction") {
		params [P_THISCLASS, P_OBJECT("_object")];

		OOP_INFO_1("INIT RADIO OBJECT ACTION: %1", _object);

		// Estimate usage radius
		private _radius = (sizeof typeof _object) + 5;

		_object addAction ["Manage radio cryptokeys", // title
			{
				// Open the radio key dialog
				private _dlg0 = NEW("RadioKeyDialog", []);
			}, 
			0, // Arguments
			100, // Priority
			true, // ShowWindow
			false, //hideOnUse
			"", //shortcut
			"['', player] call PlayerMonitor_fnc_isUnitAtFriendlyLocation", //condition
			_radius, //radius
			false, //unconscious
			"", //selection
			""]; //memoryPoint
	} ENDMETHOD;


	STATIC_METHOD("deleteEditorAllowedAreaMarkers") {
		params [P_THISCLASS];
		private _allowedAreas = (allMapMarkers select {(tolower _x) find "allowedarea" == 0});
		{_x setMarkerAlpha 0;} forEach _allowedAreas;
	} ENDMETHOD;

	// Deletes special objects placed in the editor 
	STATIC_METHOD("deleteEditorObjects") {
		params [P_THISCLASS];
		{
			{
				deleteVehicle _x;
			} forEach (entities _x);
		} forEach [	"B_Truck_01_transport_F",
					"B_Mortar_01_F",
					"B_HMG_01_F",
					"B_HMG_01_high_F",
					"B_Slingload_01_Cargo_F",
					"Sign_Arrow_Large_F",
					"Sign_Arrow_Large_Blue_F"];
	} ENDMETHOD;

	// - - - - - - S T O R A G E - - - - - -

	/* override */ METHOD("preSerialize") {
		params [P_THISOBJECT, P_OOP_OBJECT("_storage")];
		
		// Save objects which we own
		pr _gmData = T_GETV("gameModeData");
		if (!IS_NULL_OBJECT(_gmData)) then {
			CALLM1(_storage, "save", T_GETV("gameModeData"));
		};

		// Convert our objects to an array
		pr _savedObjects = ( T_GETV("objects") + T_GETV("buildingsOpen") ) apply {
			[
				typeOf _x,
				getPosWorld _x,
				vectorDir _x,
				vectorUp _x
			]
		};
		T_SETV("savedObjects", _savedObjects);

		// Save all garrisons attached here
		{
			pr _gar = _x;
			CALLM1(_storage, "save", _gar);
		} forEach T_GETV("garrisons");

		true
	} ENDMETHOD;

	// Must return true on success
	/* override */ METHOD("postSerialize") {
		params [P_THISOBJECT, P_OOP_OBJECT("_storage")];

		// Call method of all base classes
		CALL_CLASS_METHOD("MessageReceiverEx", _thisObject, "postSerialize", [_storage]);

		// Erase temporary variables
		T_SETV("savedObjects", []);

		true
	} ENDMETHOD;

	// These methods must return true on success
	
	/* override */ METHOD("postDeserialize") {
		params [P_THISOBJECT, P_OOP_OBJECT("_storage")];

		// Call method of all base classes
		CALL_CLASS_METHOD("MessageReceiverEx", _thisObject, "postDeserialize", [_storage]);

		// Set default values of variables whic hwere not saved
		T_SETV("hasPlayers", false);
		T_SETV("hasPlayerSides", []);
		T_SETV("objects", []);
		T_SETV("buildingsOpen", []);
		T_SETV("hasRadio", false);
		T_SETV("capacityInf", 0);
		T_SETV("timer", NULL_OBJECT);
		T_SETV("spawned", false);

		// Load objects which we own
		pr _gmData = T_GETV("gameModeData");
		if (!IS_NULL_OBJECT(_gmData)) then {
			CALLM1(_storage, "load", T_GETV("gameModeData"));
			PUBLIC_VAR(_thisObject, "gameModeData");
		};

		// Load garrisons
		{
			pr _gar = _x;
			CALLM1(_storage, "load", _gar);
		} forEach T_GETV("garrisons");

		// Rebuild the objects which have been constructed here
		{ // forEach T_GETV("savedObjects");
			_x params ["_type", "_posWorld", "_vDir", "_vUp"];
			// Check if there is such an object here already
			pr _objs = nearestObjects [_posWorld, [_type], 0.01, true];
			pr _hO = objNull;
			if (count _objs == 0) then {
				_hO = _type createVehicle [0, 0, 0];
				_hO setPosWorld _posWorld;
				_hO setVectorDirAndUp [_vDir, _vUp];
				_hO enableDynamicSimulation true;
			} else {
				_hO = _objs#0;
			};
			T_CALLM2("addObject", _hO, false); // Don't add spawn position, it's saved separately
		} forEach T_GETV("savedObjects");
		T_SETV("savedObjects", []);

		// Restore civ presense module
		T_CALLM1("setCapacityCiv", T_GETV("capacityCiv"));

		// Restore timer
		T_CALLM0("initTimer");

		// Enable player respawn
		{
			pr _side = _x;
			T_CALLM2("enablePlayerRespawn", _side, true);
		} forEach T_GETV("respawnSides");

		// Broadcast public variables
		PUBLIC_VAR(_thisObject, "name");
		PUBLIC_VAR(_thisObject, "garrisons");
		PUBLIC_VAR(_thisObject, "boundingRadius");
		PUBLIC_VAR(_thisObject, "border");
		PUBLIC_VAR(_thisObject, "pos");
		PUBLIC_VAR(_thisObject, "isBuilt");
		PUBLIC_VAR(_thisObject, "allowedAreas");
		PUBLIC_VAR(_thisObject, "type");
		PUBLIC_VAR(_thisObject, "wasOccupied");
		PUBLIC_VAR(_thisObject, "parent");

		//Push the new object into the array with all locations
		GETSV("Location", "all") pushBackUnique _thisObject;
		PUBLIC_STATIC_VAR("Location", "all");

		true
	} ENDMETHOD;

	/* override */ STATIC_METHOD("saveStaticVariables") {
		params [P_THISCLASS, P_OOP_OBJECT("_storage")];
	} ENDMETHOD;

	/* override */ STATIC_METHOD("loadStaticVariables") {
		params [P_THISCLASS, P_OOP_OBJECT("_storage")];
		SETSV("Location", "all", []);
	} ENDMETHOD;

ENDCLASS;

if (isNil {GETSV("Location", "all")}) then {
	SET_STATIC_VAR("Location", "all", []);
};

// Initialize arrays with building types
call compile preprocessFileLineNumbers "Location\initBuildingTypes.sqf";



// Tests
#ifdef _SQF_VM
["Location.save and load", {
	pr _loc = NEW("Location", [[0 ARG 1 ARG 2]]);
	CALLM1(_loc, "setName", "testLocationName");
	pr _storage = NEW("StorageProfileNamespace", []);
	CALLM1(_storage, "open", "testRecordLocation");
	CALLM1(_storage, "save", _loc);
	CALLSM1("Location", "saveStaticVariables", _storage);
	DELETE(_loc);
	CALLSM1("Location", "loadStaticVariables", _storage);
	CALLM1(_storage, "load", _loc);

	["Object loaded", GETV(_loc, "name") == "testLocationName"] call test_Assert;

	true
}] call test_AddTest;
#endif