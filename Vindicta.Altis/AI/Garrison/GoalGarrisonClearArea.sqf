#include "common.hpp"
/*
Goal for a garrison to go destroy some enemies
*/

#define pr private

CLASS("GoalGarrisonClearArea", "Goal")

	// Gets called when an external goal of this class is added to AI
	STATIC_METHOD("onGoalAdded") {
		params ["_thisClass", ["_AI", "", [""]], ["_parameters", [], [[]]]];

		// Set variables in AI object so that garrison can identify targets associated with this goal
		// [[TAG_G_POS, _pos], [TAG_MOVE_RADIUS, _moveRadius], [TAG_CLEAR_RADIUS, _clearRadius], [TAG_DURATION_SECONDS, _timeOutSeconds]];
		pr _pos = CALLSM("Action", "getParameterValue", [_parameters ARG TAG_G_POS]);
		pr _radius = CALLSM("Action", "getParameterValue", [_parameters ARG TAG_CLEAR_RADIUS]);
		SETV(_AI, "assignedTargetsPos", _pos);
		SETV(_AI, "assignedTargetsRadius", _radius);
	} ENDMETHOD;

	// Gets called when an external goal of this class is removed from an AI
	STATIC_METHOD("onGoalDeleted") {
		params ["_thisClass", ["_AI", "", [""]], ["_parameters", [], [[]]]];

		SETV(_AI, "assignedTargetsPos", [0 ARG 0 ARG 0]);
		SETV(_AI, "assignedTargetsRadius", 0);
	} ENDMETHOD;

ENDCLASS;