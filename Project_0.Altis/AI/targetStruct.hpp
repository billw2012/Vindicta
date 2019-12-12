// Structure of a target record
// object handle, knows about, position, age
#define TARGET_ID_UNIT			0 
#define TARGET_ID_KNOWS_ABOUT	1
#define TARGET_ID_POS			2
#define TARGET_ID_TIME			3
#define TARGET_ID_EFFICIENCY	4

#define TARGET_NEW(unit, knows, pos, time, eff) [unit, knows, pos, time, eff]