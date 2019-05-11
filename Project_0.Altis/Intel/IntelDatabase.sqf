#define OOP_INFO
#define OOP_WARNING
#define OOP_ERROR
#define OFSTREAM_FILE "Intel.rpt"
#include "..\OOP_Light\OOP_Light.h"
#include "..\CriticalSection\CriticalSection.hpp"

/*
Class: IntelDatabase

All methods are atomic, there is no threading involved in this class.
Just call the methods to perform actions.

Author: Sparker 06.05.2019 
*/

#define pr private

CLASS("IntelDatabase", "")

	VARIABLE("items");
	VARIABLE("linkedItems"); // A hash map of linked items
	VARIABLE("side");

	/*
	Method: new

	Parameters: _side

	_side - side to which this DB is attached to
	*/
	METHOD("new") {
		params [P_THISOBJECT, P_SIDE("_side")];

		T_SETV("items", []);
		T_SETV("side", _side);
		#ifndef _SQF_VM
		pr _namespace = [false] call CBA_fnc_createNamespace;
		T_SETV("linkedItems", _namespace);
		#endif
	} ENDMETHOD;

	/*
	Method: addIntel
	Adds item to the database

	Parameters: _item

	_item - <Intel> item

	Returns: nil
	*/
	METHOD("addIntel") {
		CRITICAL_SECTION {
			params [P_THISOBJECT, P_OOP_OBJECT("_item")];

			OOP_INFO_1("ADD INTEL: %1", _item);

			// Add to the array of items
			T_GETV("items") pushBack _item;

			// Add link from the source to this item
			pr _source = GETV(_item, "source");
			// If the intel item is linked to the source intel item, add the source to hashmap
			if (!isNil "_source") then {
				pr _hashmap = T_GETV("linkedItems");
				_hashMap setVariable [_source, _item];
			};
		};
	} ENDMETHOD;

	/*
	Method: updateIntel
	Updates item in this database from another item

	Parameters: _itemDest, _itemSrc

	_itemDest - <Intel> object in this database to update
	_itemSrc - <Intel> object from which to get new values

	Returns: nil
	*/
	METHOD("updateIntel") {
		CRITICAL_SECTION {
			params [P_THISOBJECT, P_OOP_OBJECT("_itemDst"), P_OOP_OBJECT("_itemSrc")];

			OOP_INFO_2("UPDATE INTEL: %1 from %2", _itemDst, _itemSrc);

			pr _items = T_GETV("items");
			if (_itemDst in _items) then { // Make sure we have this intel item
				// Backup the source so that it doesn't get overwritten in update
				pr _prevSource = GETV(_itemDst, "source");
				UPDATE(_itemDst, _itemSrc); // Copy all variables that are not nil in itemSrc
				// Restore the source
				if (!isNil "_prevSource") then {
					SETV(_itemDst, "source", _prevSource);
				};
			};
		};
	} ENDMETHOD;

	/*
	Method: updateIntelFromSource
	Updates an intel item in this database from a source intel item, if there is an intel item linked to such source item.

	Parameters: _srcItem

	_srcItem - the <Intel> item to update from

	Returns: Bool, true if the item was updated, false if the item with given source doesn't exist in this database.
	*/
	METHOD("updateIntelFromSource") {
		pr _return = false;
		CRITICAL_SECTION {
			params [P_THISOBJECT, P_OOP_OBJECT("_srcItem")];

			OOP_INFO_1("UPDATE FROM SOURCE: %1", _srcItem);

			// Check if we have an item with given source
			pr _hashmap = T_GETV("linkedItems");
			pr _item = _hashmap getVariable _srcItem;
			if (isNil "_item") then {
				_return = false;
			} else {
				CALLM2(_thisObject, "updateIntel", _item, _srcItem);
				_return = true;
			};
		};
		_return
	} ENDMETHOD;

	/*
	Method: addIntelClone
	Adds item to the database and returns a modifiable clone.
	Don't modify _item after passing it in, modify the clone instead.
	Parameters: _item

	_item - <Intel> item

	Returns: clone of _item that can be used in further updateIntelFromClone operations.
	*/
	METHOD("addIntelClone") {
		params [P_THISOBJECT, P_OOP_OBJECT("_item")];

		pr _clone = CLONE(_item);
		SETV(_clone, "dbEntry", _item);
		SETV(_clone, "db", _thisObject);
		OOP_INFO_1("ADD INTEL: %1", _item);

		CRITICAL_SECTION {
			// Add to the array of items
			T_GETV("items") pushBack _item;

#ifdef OOP_ASSERT
			// Add link from the source to this item
			pr _source = GETV(_item, "source");
			// If the intel item is linked to the source intel item, add the source to hashmap
			if (!isNil "_source") then {
				FAILURE("Use addIntel for intel items from other sources, addIntelClone is only for cmdrs own intel!")
			};
#endif
		};

		_clone
	} ENDMETHOD;

	/*
	Method: updateIntelFromClone
	Updates item in this database from a modified clone previously returned by addIntelClone

	Parameters: _item

	_item - <Intel> object returned by addIntelClone.

	Returns: nil
	*/
	METHOD("updateIntelFromClone") {
		params [P_THISOBJECT, P_OOP_OBJECT("_item")];

		pr _dbEntry = GETV(_item, "dbEntry");
		ASSERT_OBJECT(_dbEntry);

		T_CALLM("updateIntel", [_dbEntry ARG _item]);
	} ENDMETHOD;

	/*
	Method: removeIntelForClone
	Deletes an item from this database. Doesn't delete the item object from memory.

	Parameters: _item

	_item - the <Intel> item to delete

	Returns: nil
	*/
	METHOD("removeIntelForClone") {
		params [P_THISOBJECT, P_OOP_OBJECT("_item")];

		pr _dbEntry = GETV(_item, "dbEntry");
		ASSERT_OBJECT(_dbEntry);
		pr _items = T_GETV("items");
		_items deleteAt (_items find _dbEntry);

		nil
	} ENDMETHOD;

	/*
	Method: queryIntel
	Returns an array of <Intel> objects in this database that match a query.
	The algorithm checks if all non-nil member variables of _queryItem are equal to the same member variables in 

	Parameters: _queryItem

	_queryItem - the <Intel> object

	Returns: Array of <Intel> objects
	*/
	METHOD("queryIntel") {
		pr _array = [];
		CRITICAL_SECTION {
			params [P_THISOBJECT, P_OOP_OBJECT("_queryItem")];

			pr _className = GET_OBJECT_CLASS(_queryItem);
			pr _memList = GET_CLASS_MEMBERS(_className); // First variable in member list is always class name!

			pr _items = T_GETV("items");
			_array = _items select {
				pr _dbItem = _x;
				pr _index = _memList findIf {
					_x params ["_varName"];
					pr _queryValue = FORCE_GET_MEM(_queryItem, _varName);
					pr _dbValue = FORCE_GET_MEM(_dbItem, _varName);
					!(isNil "_queryValue") && !([_queryValue] isEqualTo [_dbValue]) // Variable exists in query and is not equal to the var in db, or var in db is nil
				};
				//pr _valueprint = if (_index != -1) then {_memList select _index} else {"nothing"};
				//diag_log format ["Database item: %1, index: %2, variable: %3", _dbItem, _index, _valueprint];
				_index == -1 // We didn't find mismatched variables that exist in query
			};
		};
		_array
	} ENDMETHOD;

	/*
	Method: findFirstIntel
	Same as queryIntel, but returns the first item to match the query. Can speed up lookup if you already know that there is only one item you need.

	Parameters: _queryItem

	_queryItem - the <Intel> object

	Returns: <Intel> object or "" if such object was not found
	*/
	METHOD("findFirstIntel") {
		pr _return = "";
		CRITICAL_SECTION {
			params [P_THISOBJECT, P_OOP_OBJECT("_queryItem")];

			pr _className = GET_OBJECT_CLASS(_queryItem);
			pr _memList = GET_CLASS_MEMBERS(_className); // First variable in member list is always class name!

			pr _items = T_GETV("items");
			_index = _items findIf {
				pr _dbItem = _x;
				_memList findIf {
					_x params ["_varName"];
					pr _queryValue = FORCE_GET_MEM(_queryItem, _varName);
					pr _dbValue = FORCE_GET_MEM(_dbItem, _varName);
					!(isNil "_queryValue") && !([_queryValue] isEqualTo [_dbValue]) // Variable exists in query and is not equal to the var in db, or var in db is nil
				} == -1 // We didn't find mismatched variables that exist in query
			};
			if (_index != -1) then { _return = _items select _index; };
		};
		_return
	} ENDMETHOD;

	/*
	Method: isIntelAdded
	Returns true if given <Intel> object exists in this intel database

	Parameters: _item

	_item - the <Intel> object

	Returns: Bool
	*/
	METHOD("isIntelAdded") {
		params [P_THISOBJECT, P_OOP_OBJECT("_item")];

		_item in T_GETV("items")
	} ENDMETHOD;

	/*
	Method: getAllIntel
	Returns all items in the database

	Returns: array of items
	*/
	METHOD("getAllIntel") {
		params [P_THISOBJECT];
		+T_GETV("items")
	} ENDMETHOD;

	/*
	Method: removeIntel
	Deletes an item from this database. Doesn't delete the item object from memory.

	Parameters: _item

	_item - the <Intel> item to delete

	Returns: nil
	*/
	METHOD("removeIntel") {
		params [P_THISOBJECT, P_OOP_OBJECT("_item")];

		pr _items = T_GETV("items");
		_items deleteAt (_items find _item);

		nil
	} ENDMETHOD;

ENDCLASS;